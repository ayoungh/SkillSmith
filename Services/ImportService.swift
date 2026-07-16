import Foundation

struct ImportedSkillMaterialization {
    var source: SkillSource
    var upstream: SkillUpstream?
}

struct ImportService {
    private let shell = ShellCommandService()
    private let library = SkillLibraryService()
    private let fileOperations = FileOperationService()

    func importSkill(_ skill: SkillRecord) -> SkillRecord {
        var updated = skill
        if updated.managementState == .externalImportable {
            updated.managementState = .importedExternal
            updated.source.origin = .importedInstall
        }
        return updated
    }

    func attachLibrarySource(_ source: SkillSource, to skill: SkillRecord) -> SkillRecord {
        var updated = skill
        updated.source = source
        updated.sourceIdentity = SkillSourceIdentity.pathIdentity(source.path)
        updated.managementState = .managedLocal
        updated.installMode = .symlink
        return updated
    }

    func plannedLibraryDestination(
        for candidate: ImportCandidate,
        settings: AppSettings,
        resolution: ImportConflictResolution
    ) -> URL {
        let base = URL(fileURLWithPath: settings.libraryPath, isDirectory: true)
            .appendingPathComponent(slugify(candidate.name), isDirectory: true)
        if FileManager.default.fileExists(atPath: base.path), resolution == .keepBoth {
            return uniqueFolderURL(base: base)
        }
        return base
    }

    func inspectLocal(urls: [URL], kind: ImportSourceKind = .localFolder) -> [ImportCandidate] {
        var seen = Set<String>()
        var candidates: [ImportCandidate] = []

        for url in urls {
            let candidateRoots = skillDirectories(beneath: url)
            for root in candidateRoots {
                let standardized = (root.path as NSString).standardizingPath
                guard seen.insert(standardized).inserted else { continue }
                let issues = SkillMetadataParser.validate(at: standardized)
                candidates.append(ImportCandidate(
                    id: UUID(),
                    name: SkillMetadataParser.readName(at: standardized),
                    description: SkillMetadataParser.readDescription(at: standardized),
                    sourcePath: standardized,
                    sourceKind: kind,
                    sourceRepo: nil,
                    sourceRepoPath: nil,
                    sourceRef: nil,
                    sourceRevision: nil,
                    validationIssues: issues,
                    existingSkillID: nil
                ))
            }
        }
        return candidates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func inspectDiscovered(_ skills: [SkillRecord]) -> [ImportCandidate] {
        skills.filter { !$0.isManagedLibrarySource }.map { skill in
            ImportCandidate(
                id: UUID(),
                name: skill.name,
                description: skill.description,
                sourcePath: skill.comparisonPath,
                sourceKind: .discoveredInstall,
                sourceRepo: skill.lockMetadata?.sourceURL,
                sourceRepoPath: skill.lockMetadata?.skillPath,
                sourceRef: skill.upstream?.ref,
                sourceRevision: skill.lockMetadata?.folderHash,
                validationIssues: SkillMetadataParser.validate(at: skill.comparisonPath),
                existingSkillID: skill.id
            )
        }
    }

    @MainActor
    func inspectRepository(_ input: String, ref: String = "") async throws -> [ImportCandidate] {
        let parsed = try parseRepositoryInput(input)
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillSmithImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot.deletingLastPathComponent(), withIntermediateDirectories: true)

        var arguments = ["clone", "--depth", "1", "--filter=blob:none"]
        if !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--branch", ref])
        }
        arguments.append(contentsOf: [parsed.remoteURL, tempRoot.path])
        let clone = try await shell.run("/usr/bin/git", arguments: arguments, allowNonZeroExit: true)
        guard clone.exitCode == 0 else {
            throw importError(clone.stderr.isEmpty ? "Could not clone the repository." : clone.stderr)
        }

        let revisionResult = try await shell.run(
            "/usr/bin/git",
            arguments: ["-C", tempRoot.path, "rev-parse", "HEAD"],
            allowNonZeroExit: true
        )
        let revision = revisionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let directories = skillDirectories(beneath: tempRoot)
        let filtered = parsed.requestedSkill.map { requested in
            directories.filter {
                SkillMetadataParser.readName(at: $0.path) == requested || $0.lastPathComponent == requested
            }
        } ?? directories

        return filtered.map { root in
            let relative = root.path.replacingOccurrences(of: tempRoot.path + "/", with: "")
            return ImportCandidate(
                id: UUID(),
                name: SkillMetadataParser.readName(at: root.path),
                description: SkillMetadataParser.readDescription(at: root.path),
                sourcePath: root.path,
                sourceKind: .repository,
                sourceRepo: parsed.repository,
                sourceRepoPath: relative,
                sourceRef: ref.isEmpty ? "main" : ref,
                sourceRevision: revision.isEmpty ? nil : revision,
                validationIssues: SkillMetadataParser.validate(at: root.path),
                existingSkillID: nil
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func materialize(
        _ candidate: ImportCandidate,
        settings: AppSettings,
        mode: ImportMode,
        resolution: ImportConflictResolution
    ) throws -> ImportedSkillMaterialization {
        guard candidate.isValid else {
            throw importError(candidate.validationIssues.joined(separator: " "))
        }

        let source: SkillSource
        if mode == .manageInPlace {
            guard candidate.sourceKind != .repository else {
                throw importError("Repository imports must be copied into the SkillSmith library.")
            }
            guard FileManager.default.isWritableFile(atPath: candidate.sourcePath) else {
                throw importError("This source is not writable and cannot be managed in place.")
            }
            source = SkillSource(path: candidate.sourcePath, origin: .importedInstall, editable: true)
        } else {
            try library.ensureLibraryExists(at: settings.libraryPath)
            let base = plannedLibraryDestination(for: candidate, settings: settings, resolution: .cancel)
            let destination: URL
            if FileManager.default.fileExists(atPath: base.path) {
                switch resolution {
                case .cancel:
                    throw importError("A library skill already exists at \(base.path). Choose Keep Both or Replace.")
                case .keepBoth:
                    destination = plannedLibraryDestination(for: candidate, settings: settings, resolution: .keepBoth)
                case .replace:
                    try fileOperations.moveToTrash(base)
                    destination = base
                }
            } else {
                destination = base
            }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: candidate.sourcePath), to: destination)
            source = SkillSource(path: destination.path, origin: .localLibrary, editable: true)
        }

        let upstream = candidate.sourceRepo.map {
            SkillUpstream(
                repo: $0,
                path: candidate.sourceRepoPath ?? ".",
                ref: candidate.sourceRef ?? "main",
                trackedRevision: candidate.sourceRevision,
                lastKnownRemoteRevision: candidate.sourceRevision,
                deletedUpstream: false
            )
        }
        return ImportedSkillMaterialization(source: source, upstream: upstream)
    }

    private func skillDirectories(beneath input: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        let inputPath = input.path
        guard FileManager.default.fileExists(atPath: inputPath, isDirectory: &isDirectory) else { return [] }

        if !isDirectory.boolValue {
            guard input.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame else { return [] }
            return [input.deletingLastPathComponent()]
        }
        if FileManager.default.fileExists(atPath: input.appendingPathComponent("SKILL.md").path) {
            return [input]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: input,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            if [".git", ".build", "node_modules"].contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            var directoryFlag: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directoryFlag), directoryFlag.boolValue else { continue }
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) {
                results.append(url)
                enumerator.skipDescendants()
            }
        }
        return results
    }

    private func parseRepositoryInput(_ input: String) throws -> (repository: String, remoteURL: String, requestedSkill: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw importError("Enter a GitHub repository or skills.sh URL.") }

        if let url = URL(string: trimmed), url.host?.lowercased() == "skills.sh" {
            let components = url.pathComponents.filter { $0 != "/" }
            guard components.count >= 2 else { throw importError("The skills.sh URL must include an owner and repository.") }
            let repository = "\(components[0])/\(components[1])"
            return (repository, "https://github.com/\(repository).git", components.count > 2 ? components[2] : nil)
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("git@") {
            var repository = trimmed
                .replacingOccurrences(of: "https://github.com/", with: "")
                .replacingOccurrences(of: "http://github.com/", with: "")
                .replacingOccurrences(of: "git@github.com:", with: "")
            if repository.hasSuffix(".git") { repository.removeLast(4) }
            repository = repository.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let remote = trimmed.hasSuffix(".git") ? trimmed : trimmed + ".git"
            return (repository, remote, nil)
        }

        let parts = trimmed.split(separator: "/")
        guard parts.count >= 2 else { throw importError("Use owner/repository, a GitHub URL, or a skills.sh URL.") }
        let repository = "\(parts[0])/\(parts[1])"
        return (repository, "https://github.com/\(repository).git", parts.count > 2 ? String(parts[2]) : nil)
    }

    private func uniqueFolderURL(base: URL) -> URL {
        var counter = 2
        var candidate = base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent)-\(counter)")
        while FileManager.default.fileExists(atPath: candidate.path) {
            counter += 1
            candidate = base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent)-\(counter)")
        }
        return candidate
    }

    private func slugify(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func importError(_ message: String) -> NSError {
        NSError(domain: "SkillSmith.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
