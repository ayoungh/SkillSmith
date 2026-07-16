import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SkillSmithStore {
    var settings: AppSettings
    var skills: [SkillRecord]
    var availableRoots: [AgentRoot] = []
    var selectedSection: SidebarSection? = .allSkills
    var selectedSkillID: SkillRecord.ID?
    var searchText = ""
    var errorMessage: String?
    var infoMessage: String?
    var isBusy = false
    var createSheetPresented = false
    var upstreamSheetPresented = false
    var addFromSkillsShPresented = false
    var skillsShRepoOutput = ""
    var settingsWindowPresented = false
    var draftMarkdown = ""
    var cliDiagnostics = "Checking..."

    private let appStateStore = AppStateStore()
    private let rootDiscovery = AgentRootDiscoveryService()
    private let skillsCLI = SkillsCLIService()
    private let libraryService = SkillLibraryService()
    private let symlinkService = SymlinkInstallService()
    private let importService = ImportService()
    private let gitDiffService = GitDiffService()
    private let aiDraftingService = AIDraftingService()

    init() {
        let persisted = appStateStore.loadState()
        settings = persisted.settings
        skills = persisted.skills
        availableRoots = rootDiscovery.discoverRoots(settings: persisted.settings)
    }

    var selectedSkill: SkillRecord? {
        guard let selectedSkillID else { return filteredSkills.first }
        return skills.first(where: { $0.id == selectedSkillID })
    }

    var filteredSkills: [SkillRecord] {
        let scoped: [SkillRecord]
        switch selectedSection ?? .allSkills {
        case .allSkills:
            scoped = skills
        case .installed:
            scoped = skills.filter { !$0.installedTargets.isEmpty }
        case .updates:
            scoped = skills.filter(\.hasUpdate)
        case .library:
            scoped = skills.filter { $0.source.origin == .localLibrary }
        case .imports:
            scoped = skills.filter { $0.managementState == .externalImportable || $0.managementState == .importedExternal }
        case .agents:
            scoped = skills.filter { !$0.supportedAgents.isEmpty }
        case .settings:
            scoped = skills
        }

        guard !searchText.isEmpty else {
            return scoped.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return scoped
            .filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func selectSection(_ section: SidebarSection) {
        selectedSection = section
        if selectedSkillID == nil || filteredSkills.contains(where: { $0.id == selectedSkillID }) == false {
            selectedSkillID = filteredSkills.first?.id
        }
    }

    func bootstrap() async {
        availableRoots = rootDiscovery.discoverRoots(settings: settings)
        cliDiagnostics = await skillsCLI.checkAvailability()
        await refresh()
    }

    func refresh() async {
        isBusy = true
        defer { isBusy = false }

        availableRoots = rootDiscovery.discoverRoots(settings: settings)
        var merged = Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0) })

        // Rebuild install targets from what is actually on disk so removed
        // installs and deleted skills don't linger as ghost entries.
        for name in merged.keys {
            merged[name]?.installedTargets = []
        }

        do {
            let cliSkills = try await skillsCLI.listGlobalSkills()
            for cli in cliSkills {
                let root = availableRoots.first(where: { cli.path.hasPrefix($0.path) })
                let install = InstalledSkill(
                    rootID: root?.id ?? "cli",
                    rootName: root?.name ?? "skills CLI",
                    installedPath: cli.path,
                    agentNames: cli.agents,
                    isSymlink: (try? FileManager.default.destinationOfSymbolicLink(atPath: cli.path)) != nil,
                    symlinkDestination: try? FileManager.default.destinationOfSymbolicLink(atPath: cli.path)
                )
                var record = merged[cli.name] ?? SkillRecord(
                    id: UUID(),
                    name: cli.name,
                    description: SkillMetadataParser.readDescription(at: cli.path),
                    managementState: .externalImportable,
                    source: SkillSource(path: cli.path, origin: .installedPath, editable: false),
                    installMode: .symlink,
                    installedTargets: [],
                    upstream: nil,
                    supportedAgents: cli.agents,
                    lastCheckedAt: nil,
                    lastDiffSummary: nil,
                    updatePreview: nil
                )
                record.installedTargets = mergeTargets(record.installedTargets, install)
                record.supportedAgents = Array(Set(record.supportedAgents + cli.agents)).sorted()
                if record.description.isEmpty {
                    record.description = SkillMetadataParser.readDescription(at: cli.path)
                }
                merged[cli.name] = record
            }
        } catch {
            errorMessage = "Could not list skills with skills.sh: \(error.localizedDescription)"
        }

        for scanned in rootDiscovery.scanSkillInstallations(roots: availableRoots) {
            var record = merged[scanned.name] ?? SkillRecord(
                id: UUID(),
                name: scanned.name,
                description: SkillMetadataParser.readDescription(at: scanned.installedSkill.symlinkDestination ?? scanned.installedSkill.installedPath),
                managementState: .externalImportable,
                source: SkillSource(
                    path: scanned.installedSkill.symlinkDestination ?? scanned.installedSkill.installedPath,
                    origin: scanned.installedSkill.isSymlink ? .installedPath : .importedInstall,
                    editable: false
                ),
                installMode: scanned.installedSkill.isSymlink ? .symlink : .copy,
                installedTargets: [],
                upstream: nil,
                supportedAgents: scanned.installedSkill.agentNames,
                lastCheckedAt: nil,
                lastDiffSummary: nil,
                updatePreview: nil
            )
            record.installedTargets = mergeTargets(record.installedTargets, scanned.installedSkill)
            let resolvedSource = scanned.installedSkill.symlinkDestination ?? scanned.installedSkill.installedPath
            if record.source.path.isEmpty || !FileManager.default.fileExists(atPath: record.source.path) {
                record.source = SkillSource(
                    path: resolvedSource,
                    origin: scanned.installedSkill.isSymlink ? .installedPath : .importedInstall,
                    editable: record.source.editable
                )
            }
            if record.description.isEmpty {
                record.description = SkillMetadataParser.readDescription(at: resolvedSource)
            }
            merged[scanned.name] = record
        }

        // Drop records that no longer exist anywhere on disk.
        merged = merged.filter { _, record in
            !record.installedTargets.isEmpty ||
                (!record.source.path.isEmpty && FileManager.default.fileExists(atPath: record.source.path))
        }

        skills = merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if selectedSkillID == nil || !skills.contains(where: { $0.id == selectedSkillID }) {
            selectedSkillID = skills.first?.id
        }
        save()
    }

    func createSkill(spec: SkillDraftSpec, useAI: Bool) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let draft = useAI ? try await aiDraftingService.draftSkill(spec: spec, settings: settings) : libraryService.createTemplateMarkdown(for: spec)
            draftMarkdown = draft
            let source = try libraryService.createSkill(from: spec, settings: settings, draftMarkdown: draft)
            let record = SkillRecord(
                id: UUID(),
                name: spec.name,
                description: spec.description,
                managementState: .managedLocal,
                source: source,
                installMode: .symlink,
                installedTargets: [],
                upstream: spec.upstreamSeed.isEmpty ? nil : SkillUpstream(repo: spec.upstreamSeed, path: ".", ref: "main", trackedRevision: nil, lastKnownRemoteRevision: nil, deletedUpstream: false),
                supportedAgents: spec.supportedAgents,
                lastCheckedAt: nil,
                lastDiffSummary: nil,
                updatePreview: nil
            )
            skills.append(record)
            skills.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectedSkillID = record.id
            createSheetPresented = false
            infoMessage = "Created \(record.name) in the local library."
            save()
        } catch {
            errorMessage = "Could not create skill: \(error.localizedDescription)"
        }
    }

    func installSelectedSkill(into root: AgentRoot) async {
        guard let skill = selectedSkill else { return }
        do {
            let install = try symlinkService.install(skill: skill, into: root)
            mutateSkill(named: skill.id) { record in
                record.installedTargets = mergeTargets(record.installedTargets, install)
                record.managementState = record.source.origin == .localLibrary ? .managedLocal : record.managementState
            }
            infoMessage = "Installed \(skill.name) into \(root.name)."
            save()
        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    func removeInstall(_ install: InstalledSkill, from skill: SkillRecord) async {
        do {
            try symlinkService.removeInstall(install)
            mutateSkill(named: skill.id) { record in
                record.installedTargets.removeAll { $0.id == install.id }
            }
            infoMessage = "Removed install at \(install.rootName)."
            save()
        } catch {
            errorMessage = "Remove failed: \(error.localizedDescription)"
        }
    }

    func importSelectedSkill() {
        guard let skill = selectedSkill else { return }
        mutateSkill(named: skill.id) { record in
            record = importService.importSkill(record)
        }
        infoMessage = "Imported \(skill.name) into SkillSmith management."
        save()
    }

    func adoptSelectedSkillIntoLibrary() {
        guard let skill = selectedSkill else { return }
        do {
            let source = try libraryService.adoptExistingSkill(at: skill.comparisonPath, settings: settings)
            mutateSkill(named: skill.id) { record in
                record = importService.attachLibrarySource(source, to: record)
            }
            infoMessage = "Copied \(skill.name) into the local library."
            save()
        } catch {
            errorMessage = "Could not adopt skill into library: \(error.localizedDescription)"
        }
    }

    func linkUpstream(repo: String, path: String, ref: String) {
        guard let skill = selectedSkill else { return }
        mutateSkill(named: skill.id) { record in
            record.upstream = SkillUpstream(
                repo: repo,
                path: path.isEmpty ? "." : path,
                ref: ref.isEmpty ? "main" : ref,
                trackedRevision: record.upstream?.trackedRevision,
                lastKnownRemoteRevision: record.upstream?.lastKnownRemoteRevision,
                deletedUpstream: false
            )
            if record.managementState != .managedLocal {
                record.managementState = .managedRemote
            }
        }
        upstreamSheetPresented = false
        infoMessage = "Linked upstream for \(skill.name)."
        save()
    }

    func checkUpdatesForSelectedSkill() async {
        guard let skill = selectedSkill else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let preview = try await gitDiffService.checkForUpdates(skill: skill)
            mutateSkill(named: skill.id) { record in
                record.updatePreview = preview
                record.lastCheckedAt = preview.checkedAt
                record.lastDiffSummary = preview.summary
                if var upstream = record.upstream {
                    upstream.lastKnownRemoteRevision = preview.remoteRevision
                    upstream.deletedUpstream = preview.status == .deletedUpstream
                    record.upstream = upstream
                }
            }
            infoMessage = preview.summary
            save()
        } catch {
            errorMessage = "Update check failed: \(error.localizedDescription)"
        }
    }

    func applyUpdateForSelectedSkill() async {
        guard let skill = selectedSkill else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await skillsCLI.updateSkill(named: skill.name)
            mutateSkill(named: skill.id) { record in
                if var upstream = record.upstream {
                    upstream.trackedRevision = record.updatePreview?.remoteRevision ?? upstream.trackedRevision
                    upstream.lastKnownRemoteRevision = record.updatePreview?.remoteRevision ?? upstream.lastKnownRemoteRevision
                    upstream.deletedUpstream = false
                    record.upstream = upstream
                }
                record.lastDiffSummary = result.stdout.isEmpty ? "Updated \(record.name)." : result.stdout
            }
            infoMessage = "Updated \(skill.name)."
            await refresh()
        } catch {
            errorMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    func previewSkillsShRepo(_ repo: String) async {
        isBusy = true
        defer { isBusy = false }
        skillsShRepoOutput = ""

        do {
            let result = try await skillsCLI.listRepoSkills(repo: repo)
            let output = result.stdout.isEmpty ? result.stderr : result.stdout
            skillsShRepoOutput = stripANSICodes(from: output)
        } catch {
            errorMessage = "Could not list skills in \(repo): \(error.localizedDescription)"
        }
    }

    func addSkillsFromSkillsSh(repo: String, skillNames: [String], agentNames: [String]) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await skillsCLI.addSkills(repo: repo, skillNames: skillNames, agentNames: agentNames)
            if result.exitCode == 0 {
                addFromSkillsShPresented = false
                skillsShRepoOutput = ""
                infoMessage = "Installed from \(repo)."
                await refresh()
            } else {
                let output = result.stderr.isEmpty ? result.stdout : result.stderr
                errorMessage = "skills add failed: \(stripANSICodes(from: output).prefix(300))"
            }
        } catch {
            errorMessage = "Install from skills.sh failed: \(error.localizedDescription)"
        }
    }

    func updateAllSkillsShSkills() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await skillsCLI.updateAllGlobalSkills()
            let output = stripANSICodes(from: result.stdout.isEmpty ? result.stderr : result.stdout)
            let lastLine = output
                .split(separator: "\n", omittingEmptySubsequences: true)
                .last
                .map(String.init) ?? "Done."
            infoMessage = "skills.sh update: \(lastLine)"
            await refresh()
        } catch {
            errorMessage = "skills.sh update failed: \(error.localizedDescription)"
        }
    }

    private func stripANSICodes(from text: String) -> String {
        text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }

    func saveAPIKey(_ value: String) {
        do {
            try KeychainService().save(value: value, account: settings.apiKeyAccountName)
            infoMessage = "Saved OpenAI API key."
        } catch {
            errorMessage = "Could not save API key: \(error.localizedDescription)"
        }
    }

    func clearAPIKey() {
        KeychainService().delete(account: settings.apiKeyAccountName)
        infoMessage = "Removed OpenAI API key."
    }

    func saveSettings() {
        save()
    }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func open(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func mutateSkill(named id: UUID, mutate: (inout SkillRecord) -> Void) {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return }
        mutate(&skills[index])
    }

    private func mergeTargets(_ current: [InstalledSkill], _ newTarget: InstalledSkill) -> [InstalledSkill] {
        var updated = current
        if let index = updated.firstIndex(where: { $0.id == newTarget.id }) {
            updated[index] = newTarget
        } else {
            updated.append(newTarget)
        }
        return updated.sorted { $0.rootName < $1.rootName }
    }

    private func save() {
        do {
            try appStateStore.saveState(PersistedAppState(settings: settings, skills: skills))
        } catch {
            errorMessage = "Could not save SkillSmith state: \(error.localizedDescription)"
        }
    }
}
