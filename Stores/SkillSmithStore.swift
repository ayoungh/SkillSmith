import AppKit
import Foundation
import Observation

private enum PendingManagementAction {
    case installSkills(Set<UUID>, String, Bool)
    case importCandidate(UUID)
    case updateSkills(Set<UUID>)
    case deleteSkills(Set<UUID>)
    case deleteDefinitions(Set<String>)
    case uninstallSkills(Set<UUID>)
    case uninstallRoot(String)
}

@MainActor
@Observable
final class SkillSmithStore {
    var settings: AppSettings
    var skills: [SkillRecord]
    var availableRoots: [AgentRoot] = []
    var agentDefinitions: [AgentDefinition] = []
    var definitionLocations: [AgentDefinitionLocation] = []
    var importCandidates: [ImportCandidate] = []

    var selectedSection: SidebarSection? = .allSkills
    var selectedSkillID: SkillRecord.ID?
    var librarySelection: Set<SkillRecord.ID> = []
    var selectedAgentRootID: AgentRoot.ID?
    var selectedAgentDefinitionID: AgentDefinition.ID?
    var selectedImportCandidateID: ImportCandidate.ID?
    var selectedDefinitionLocationID: AgentDefinitionLocation.ID?
    var selectedImportRootIDs: Set<AgentRoot.ID> = []
    var importMode: ImportMode = .copyToLibrary
    var importConflictResolution: ImportConflictResolution = .cancel

    var searchText = ""
    var errorMessage: String?
    var infoMessage: String?
    var isBusy = false
    var createSheetPresented = false
    var upstreamSheetPresented = false
    var addFromSkillsShPresented = false
    var skillsShRepoOutput = ""
    var draftMarkdown = ""
    var cliDiagnostics = "Checking..."
    var pendingMutation: MutationPreview?
    var operationResults: [OperationResult] = []

    private let appStateStore = AppStateStore()
    private let rootDiscovery = AgentRootDiscoveryService()
    private let skillsCLI = SkillsCLIService()
    private let skillsLock = SkillsLockService()
    private let libraryService = SkillLibraryService()
    private let symlinkService = SymlinkInstallService()
    private let importService = ImportService()
    private let gitDiffService = GitDiffService()
    private let aiDraftingService = AIDraftingService()
    private let fileOperations = FileOperationService()
    private let definitionService = AgentDefinitionService()
    private let textDiffService = TextDiffService()
    private var pendingAction: PendingManagementAction?

    init() {
        let persisted = appStateStore.loadState()
        settings = persisted.settings
        skills = persisted.skills
        availableRoots = rootDiscovery.discoverRoots(settings: persisted.settings)
        definitionLocations = definitionService.locations(settings: persisted.settings)
        agentDefinitions = definitionService.discover(settings: persisted.settings)
    }

    var selectedSkill: SkillRecord? {
        if let selectedSkillID, let selected = skills.first(where: { $0.id == selectedSkillID }) {
            return selected
        }
        return filteredSkills.first
    }

    var selectedLibrarySkill: SkillRecord? {
        guard let id = librarySelection.first else { return nil }
        return skills.first(where: { $0.id == id })
    }

    var selectedAgentRoot: AgentRoot? {
        guard let selectedAgentRootID else { return nil }
        return availableRoots.first(where: { $0.id == selectedAgentRootID })
    }

    var selectedAgentDefinition: AgentDefinition? {
        guard let selectedAgentDefinitionID else { return nil }
        return agentDefinitions.first(where: { $0.id == selectedAgentDefinitionID })
    }

    var selectedImportCandidate: ImportCandidate? {
        guard let selectedImportCandidateID else { return nil }
        return importCandidates.first(where: { $0.id == selectedImportCandidateID })
    }

    var selectedDefinitionLocation: AgentDefinitionLocation? {
        guard let selectedDefinitionLocationID else { return definitionLocations.first }
        return definitionLocations.first(where: { $0.id == selectedDefinitionLocationID })
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
            scoped = skills
        case .imports:
            scoped = skills.filter { $0.managementState == .externalImportable || $0.managementState == .importedExternal }
        case .agents:
            scoped = skills
        case .settings:
            scoped = skills
        }

        guard !searchText.isEmpty else { return sorted(scoped) }
        return sorted(scoped.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.source.path.localizedCaseInsensitiveContains(searchText) ||
                $0.supportedAgents.contains { $0.localizedCaseInsensitiveContains(searchText) }
        })
    }

    var filteredAgentDefinitions: [AgentDefinition] {
        guard !searchText.isEmpty else { return agentDefinitions }
        return agentDefinitions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.platform.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    func selectSection(_ section: SidebarSection) {
        selectedSection = section
        if selectedSkillID == nil || !filteredSkills.contains(where: { $0.id == selectedSkillID }) {
            selectedSkillID = filteredSkills.first?.id
        }
        if section == .library, librarySelection.isEmpty, let first = filteredSkills.first {
            librarySelection = [first.id]
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

        let configuredRoots = rootDiscovery.discoverRoots(settings: settings)
        let lockMetadata = skillsLock.loadMetadata()
        var cliSkills: [CLIInstalledSkill] = []
        do {
            cliSkills = try await skillsCLI.listGlobalSkills()
        } catch {
            errorMessage = "Could not list skills with skills.sh: \(error.localizedDescription)"
        }

        availableRoots = configuredRoots + rootDiscovery.dynamicRoots(from: cliSkills, excluding: configuredRoots)
        var merged: [String: SkillRecord] = [:]

        func reusableRecord(identity: String, name: String, path: String, make: () -> SkillRecord) -> SkillRecord {
            if let existing = merged[identity] { return existing }
            var record = skills.first(where: { $0.stableSourceIdentity == identity })
                ?? skills.first(where: {
                    $0.name == name && standardized($0.comparisonPath) == standardized(path)
                })
                ?? make()
            record.installedTargets = []
            record.sourceIdentity = identity
            record.healthIssues = []
            return record
        }

        for librarySkill in rootDiscovery.scanLibrary(at: settings.libraryPath) {
            let identity = SkillSourceIdentity.pathIdentity(librarySkill.path)
            var record = reusableRecord(identity: identity, name: librarySkill.name, path: librarySkill.path) {
                makeRecord(
                    name: SkillMetadataParser.readName(at: librarySkill.path),
                    path: librarySkill.path,
                    origin: .localLibrary,
                    editable: true,
                    state: .managedLocal
                )
            }
            record.name = SkillMetadataParser.readName(at: librarySkill.path)
            record.description = SkillMetadataParser.readDescription(at: librarySkill.path)
            record.source = SkillSource(path: librarySkill.path, origin: .localLibrary, editable: true)
            record.managementState = .managedLocal
            record.sourceIdentity = identity
            merged[identity] = record
        }

        for cli in cliSkills {
            let resolved = SkillSmithPaths.resolvedSymlinkDestination(atPath: cli.path) ?? cli.path
            let metadata = lockMetadata[cli.name]
            let inLibrary = isInside(resolved, parent: settings.libraryPath)
            let identity = inLibrary ? SkillSourceIdentity.pathIdentity(resolved) : (metadata?.identity ?? SkillSourceIdentity.pathIdentity(resolved))
            let root = rootForInstallPath(cli.path)
            let origin: SkillSourceOrigin = inLibrary ? .localLibrary : (metadata == nil ? .installedPath : .remoteInstall)

            var record = reusableRecord(identity: identity, name: cli.name, path: resolved) {
                makeRecord(
                    name: cli.name,
                    path: resolved,
                    origin: origin,
                    editable: inLibrary,
                    state: inLibrary ? .managedLocal : .externalImportable
                )
            }
            record.name = cli.name
            record.sourceIdentity = identity
            record.lockMetadata = metadata
            record.source = SkillSource(path: resolved, origin: origin, editable: inLibrary)
            if record.description.isEmpty {
                record.description = SkillMetadataParser.readDescription(at: resolved)
            }
            if inLibrary { record.managementState = .managedLocal }
            else if record.managementState == .managedLocal { record.managementState = .externalImportable }
            record.supportedAgents = Array(Set(record.supportedAgents + cli.agents)).sorted()

            if record.upstream == nil, let metadata {
                record.upstream = SkillUpstream(
                    repo: metadata.sourceURL,
                    path: metadata.skillPath,
                    ref: "main",
                    trackedRevision: nil,
                    lastKnownRemoteRevision: nil,
                    deletedUpstream: false
                )
            }

            let destination = SkillSmithPaths.resolvedSymlinkDestination(atPath: cli.path)
            let isSymlink = destination != nil
            let install = InstalledSkill(
                rootID: root?.id ?? "dynamic:\(URL(fileURLWithPath: cli.path).deletingLastPathComponent().path)",
                rootName: root?.name ?? "skills CLI",
                installedPath: cli.path,
                agentNames: cli.agents,
                isSymlink: isSymlink,
                symlinkDestination: destination,
                isBroken: isSymlink && !FileManager.default.fileExists(atPath: resolved),
                isCanonicalSource: metadata != nil && root?.platform == .shared
            )
            record.installedTargets = mergeTargets(record.installedTargets, install)
            merged[identity] = record
        }

        let cliByName = Dictionary(grouping: cliSkills, by: \.name)
        for scanned in rootDiscovery.scanSkillInstallations(roots: availableRoots) {
            let root = availableRoots.first(where: { $0.id == scanned.installedSkill.rootID })
            let resolved = scanned.installedSkill.symlinkDestination ?? scanned.installedSkill.installedPath
            let matchingCLI = cliByName[scanned.name]?.first(where: { cli in
                cli.path == scanned.installedSkill.installedPath ||
                    cli.path == resolved ||
                    cli.agents.contains(scanned.installedSkill.rootName)
            })
            let metadata = matchingCLI.flatMap { _ in lockMetadata[scanned.name] }
            let inLibrary = isInside(resolved, parent: settings.libraryPath)
            let identity = inLibrary ? SkillSourceIdentity.pathIdentity(resolved) : (metadata?.identity ?? SkillSourceIdentity.pathIdentity(resolved))
            let origin: SkillSourceOrigin = inLibrary ? .localLibrary : (metadata == nil ? .installedPath : .remoteInstall)

            var record = reusableRecord(identity: identity, name: scanned.name, path: resolved) {
                makeRecord(
                    name: scanned.name,
                    path: resolved,
                    origin: origin,
                    editable: inLibrary,
                    state: inLibrary ? .managedLocal : .externalImportable
                )
            }
            record.sourceIdentity = identity
            record.lockMetadata = metadata ?? record.lockMetadata
            if record.source.path.isEmpty || !FileManager.default.fileExists(atPath: record.source.path) {
                record.source = SkillSource(path: resolved, origin: origin, editable: inLibrary)
            }
            if record.description.isEmpty, FileManager.default.fileExists(atPath: resolved) {
                record.description = SkillMetadataParser.readDescription(at: resolved)
            }
            var install = scanned.installedSkill
            install.isCanonicalSource = metadata != nil && root?.platform == .shared && matchingCLI?.path == install.installedPath
            record.installedTargets = mergeTargets(record.installedTargets, install)
            record.supportedAgents = Array(Set(record.supportedAgents + install.agentNames)).sorted()
            if install.isBroken == true {
                record.healthIssues = Array(Set((record.healthIssues ?? []) + ["Broken symlink at \(install.installedPath)"]))
            }
            merged[identity] = record
        }

        skills = sorted(merged.values.filter { record in
            !record.installedTargets.isEmpty || FileManager.default.fileExists(atPath: record.source.path)
        })
        synchronizeSelections()
        refreshAgentDefinitions()
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
                updatePreview: nil,
                sourceIdentity: SkillSourceIdentity.pathIdentity(source.path)
            )
            skills.append(record)
            skills = sorted(skills)
            selectedSkillID = record.id
            librarySelection = [record.id]
            createSheetPresented = false
            infoMessage = "Created \(record.name) in the local library."
            save()
        } catch {
            errorMessage = "Could not create skill: \(error.localizedDescription)"
        }
    }

    func installSelectedSkill(into root: AgentRoot, allowReplacing: Bool = false) async {
        guard let skill = selectedSkill else { return }
        await installSkills([skill.id], into: root, allowReplacing: allowReplacing)
    }

    func installLibrarySelection(into root: AgentRoot, allowReplacing: Bool = false) async {
        await installSkills(librarySelection, into: root, allowReplacing: allowReplacing)
    }

    func installSkills(_ ids: Set<UUID>, into root: AgentRoot, allowReplacing: Bool = false) async {
        guard !ids.isEmpty else { return }
        isBusy = true
        operationResults = []
        defer { isBusy = false }

        for skill in skills.filter({ ids.contains($0.id) }) {
            do {
                if let metadata = skill.lockMetadata, let agent = root.platform?.cliIdentifier {
                    let result = try await skillsCLI.addSkills(repo: metadata.source, skillNames: [skill.name], agentNames: [agent])
                    try requireSuccess(result, action: "Install \(skill.name)")
                    operationResults.append(OperationResult(summary: "Installed with skills CLI", path: root.path, succeeded: true, detail: skill.name))
                } else {
                    let install = try symlinkService.install(skill: skill, into: root, allowReplacing: allowReplacing)
                    mutateSkill(named: skill.id) { record in
                        record.installedTargets = mergeTargets(record.installedTargets, install)
                    }
                    operationResults.append(OperationResult(summary: "Installed", path: install.installedPath, succeeded: true, detail: skill.name))
                }
            } catch {
                operationResults.append(OperationResult(summary: "Install failed", path: root.path, succeeded: false, detail: "\(skill.name): \(error.localizedDescription)"))
                errorMessage = "Stopped after an install failed: \(error.localizedDescription)"
                break
            }
        }
        await refresh()
        if operationResults.allSatisfy(\.succeeded) { infoMessage = "Installed \(operationResults.count) skill operation(s)." }
    }

    func requestInstallSkills(_ ids: Set<UUID>, into root: AgentRoot) {
        let selected = skills.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        var replacing = false
        let steps = selected.map { skill -> MutationStep in
            let destination = URL(fileURLWithPath: root.path).appendingPathComponent(skill.installName).path
            let existingLink = SkillSmithPaths.resolvedSymlinkDestination(atPath: destination)
            let alreadyInstalled = existingLink.map { standardized($0) == standardized(skill.source.path) } == true
            let conflict = !alreadyInstalled && (FileManager.default.fileExists(atPath: destination) || existingLink != nil)
            replacing = replacing || conflict
            return MutationStep(
                kind: .symlink,
                summary: alreadyInstalled ? "Keep existing \(skill.name) symlink" : (conflict ? "Replace existing item with \(skill.name)" : "Install \(skill.name) into \(root.name)"),
                path: skill.source.path,
                destination: destination,
                destructive: conflict
            )
        }
        pendingMutation = MutationPreview(
            title: "Install \(selected.count) skill\(selected.count == 1 ? "" : "s") into \(root.name)?",
            message: replacing ? "At least one destination conflict will be moved to Trash or unlinked before installation." : "Review the exact source and destination paths.",
            confirmationText: root.name,
            steps: steps
        )
        pendingAction = .installSkills(Set(selected.map(\.id)), root.id, replacing)
    }

    func removeInstall(_ install: InstalledSkill, from skill: SkillRecord) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await removeInstallInternal(install, from: skill)
            operationResults = [result]
            infoMessage = result.summary
            await refresh()
        } catch {
            errorMessage = "Remove failed: \(error.localizedDescription)"
        }
    }

    func uninstallEverywhere(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        isBusy = true
        operationResults = []
        defer { isBusy = false }

        for skill in skills.filter({ ids.contains($0.id) }) {
            do {
                if skill.lockMetadata != nil {
                    let result = try await skillsCLI.removeSkill(named: skill.name, global: true)
                    try requireSuccess(result, action: "Uninstall \(skill.name)")
                    operationResults.append(OperationResult(summary: "Uninstalled everywhere", path: skill.source.path, succeeded: true, detail: skill.name))
                } else {
                    for install in skill.installedTargets where install.isCanonicalSource != true {
                        operationResults.append(try fileOperations.removeInstall(install, roots: availableRoots))
                    }
                }
            } catch {
                operationResults.append(OperationResult(summary: "Uninstall failed", path: skill.source.path, succeeded: false, detail: error.localizedDescription))
                errorMessage = "Stopped after an uninstall failed: \(error.localizedDescription)"
                break
            }
        }
        await refresh()
    }

    func requestUninstallSkills(_ ids: Set<UUID>) {
        let selected = skills.filter { ids.contains($0.id) && !$0.installedTargets.isEmpty }
        guard !selected.isEmpty else {
            infoMessage = "The selected skills are not installed anywhere."
            return
        }
        let steps = selected.flatMap { skill -> [MutationStep] in
            if skill.lockMetadata != nil {
                return [MutationStep(kind: .cli, summary: "Uninstall \(skill.name) through the skills CLI", path: skill.source.path, destination: nil, destructive: true)]
            }
            return skill.installedTargets.filter { $0.isCanonicalSource != true }.map {
                MutationStep(kind: .unlink, summary: "Remove \(skill.name) from \($0.rootName)", path: $0.installedPath, destination: nil, destructive: true)
            }
        }
        let confirmation = selected.count == 1 ? selected[0].name : "UNINSTALL"
        pendingMutation = MutationPreview(
            title: selected.count == 1 ? "Uninstall \(selected[0].name) everywhere?" : "Uninstall \(selected.count) skills everywhere?",
            message: "Canonical SkillSmith library sources will not be deleted.",
            confirmationText: confirmation,
            steps: steps
        )
        pendingAction = .uninstallSkills(Set(selected.map(\.id)))
    }

    func requestUninstallAll(from root: AgentRoot) {
        let affected = skills.compactMap { skill -> MutationStep? in
            guard let install = skill.installedTargets.first(where: { $0.rootID == root.id && $0.isCanonicalSource != true }) else { return nil }
            return MutationStep(kind: skill.lockMetadata == nil ? .unlink : .cli, summary: "Remove \(skill.name)", path: install.installedPath, destination: nil, destructive: true)
        }
        guard !affected.isEmpty else {
            infoMessage = "There are no removable installs in \(root.name)."
            return
        }
        pendingMutation = MutationPreview(
            title: "Uninstall everything from \(root.name)?",
            message: "This removes \(affected.count) install(s) from this destination only. Canonical sources remain intact.",
            confirmationText: root.name,
            steps: affected
        )
        pendingAction = .uninstallRoot(root.id)
    }

    func requestDeleteSkills(_ ids: Set<UUID>) {
        let selected = skills.filter { ids.contains($0.id) && $0.isManagedLibrarySource }
        guard !selected.isEmpty else {
            errorMessage = "Only SkillSmith library sources can be deleted. External sources can be uninstalled or imported first."
            return
        }
        let steps = selected.flatMap { skill in
            skill.installedTargets.filter { $0.isCanonicalSource != true }.map {
                MutationStep(kind: .unlink, summary: "Remove install from \($0.rootName)", path: $0.installedPath, destination: nil, destructive: true)
            } + [MutationStep(kind: .trash, summary: "Move source to Trash", path: skill.source.path, destination: nil, destructive: true)]
        }
        let confirmation = selected.count == 1 ? selected[0].name : "DELETE"
        pendingMutation = MutationPreview(
            title: selected.count == 1 ? "Delete \(selected[0].name)?" : "Delete \(selected.count) skills?",
            message: "Dependent installs will be removed first. Managed sources are moved to macOS Trash.",
            confirmationText: confirmation,
            steps: steps
        )
        pendingAction = .deleteSkills(Set(selected.map(\.id)))
    }

    func requestDeleteDefinition(_ definition: AgentDefinition) {
        guard definition.isEditable else {
            errorMessage = "This definition is read-only."
            return
        }
        pendingMutation = MutationPreview(
            title: "Delete \(definition.name)?",
            message: "The definition will be moved to macOS Trash.",
            confirmationText: definition.name,
            steps: [MutationStep(kind: .trash, summary: "Move agent definition to Trash", path: definition.path, destination: nil, destructive: true)]
        )
        pendingAction = .deleteDefinitions([definition.id])
    }

    func cancelPendingMutation() {
        pendingMutation = nil
        pendingAction = nil
    }

    func confirmPendingMutation(confirmation: String) async {
        guard let preview = pendingMutation, confirmation == preview.confirmationText, let action = pendingAction else {
            errorMessage = "The confirmation text does not match."
            return
        }
        isBusy = true
        operationResults = []
        defer { isBusy = false }

        do {
            switch action {
            case let .installSkills(ids, rootID, allowReplacing):
                guard let root = availableRoots.first(where: { $0.id == rootID }) else {
                    throw NSError(domain: "SkillSmith.Install", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected destination no longer exists."])
                }
                await installSkills(ids, into: root, allowReplacing: allowReplacing)
            case let .importCandidate(id):
                selectedImportCandidateID = id
                await importSelectedCandidate()
            case let .updateSkills(ids):
                await applyUpdates(ids: ids)
            case let .deleteSkills(ids):
                for skill in skills.filter({ ids.contains($0.id) }) {
                    for install in skill.installedTargets where install.isCanonicalSource != true {
                        operationResults.append(try await removeInstallInternal(install, from: skill))
                    }
                    operationResults.append(try fileOperations.deleteManagedSource(skill, libraryPath: settings.libraryPath))
                    skills.removeAll { $0.id == skill.id }
                }
                infoMessage = "Moved the selected skill sources to Trash."
            case let .deleteDefinitions(ids):
                for definition in agentDefinitions.filter({ ids.contains($0.id) }) {
                    try definitionService.delete(definition)
                    operationResults.append(OperationResult(summary: "Moved definition to Trash", path: definition.path, succeeded: true, detail: definition.name))
                }
                refreshAgentDefinitions()
                infoMessage = "Moved the agent definition to Trash."
            case let .uninstallSkills(ids):
                for skill in skills.filter({ ids.contains($0.id) }) {
                    try await uninstallSkillInternal(skill)
                }
                infoMessage = "Uninstalled the selected skills."
            case let .uninstallRoot(rootID):
                guard let root = availableRoots.first(where: { $0.id == rootID }) else { break }
                let affected = skills.compactMap { skill -> (SkillRecord, InstalledSkill)? in
                    guard let install = skill.installedTargets.first(where: { $0.rootID == root.id && $0.isCanonicalSource != true }) else { return nil }
                    return (skill, install)
                }
                for (skill, install) in affected {
                    operationResults.append(try await removeInstallInternal(install, from: skill))
                }
                infoMessage = "Removed installs from \(root.name)."
            }
            pendingMutation = nil
            pendingAction = nil
            await refresh()
        } catch {
            operationResults.append(OperationResult(summary: "Operation failed", path: preview.steps.first?.path ?? "", succeeded: false, detail: error.localizedDescription))
            errorMessage = "Stopped after an operation failed: \(error.localizedDescription)"
            pendingMutation = nil
            pendingAction = nil
            await refresh()
        }
    }

    func skillMarkdown(for skill: SkillRecord) -> String {
        let url = URL(fileURLWithPath: skill.comparisonPath).appendingPathComponent("SKILL.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func previewSkillMarkdownChange(for skill: SkillRecord, proposed: String) -> String {
        textDiffService.diff(original: skillMarkdown(for: skill), updated: proposed)
    }

    func saveSkillMarkdown(for skill: SkillRecord, content: String) async {
        let issues = SkillMetadataParser.validate(markdown: content)
        guard issues.isEmpty else {
            errorMessage = "Cannot save SKILL.md: \(issues.joined(separator: " "))"
            return
        }
        guard skill.source.editable else {
            errorMessage = "Import this skill into the library before editing it."
            return
        }
        do {
            let url = URL(fileURLWithPath: skill.source.path).appendingPathComponent("SKILL.md")
            try fileOperations.writeAtomically(content, to: url)
            mutateSkill(named: skill.id) { record in
                record.name = SkillMetadataParser.name(in: content)
                record.description = SkillMetadataParser.description(in: content)
            }
            save()
            infoMessage = "Saved \(skill.name)."
            await refresh()
        } catch {
            errorMessage = "Could not save SKILL.md: \(error.localizedDescription)"
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

    func queueLocalImports(_ urls: [URL], kind: ImportSourceKind = .localFolder) {
        let candidates = importService.inspectLocal(urls: urls, kind: kind)
        appendImportCandidates(candidates)
    }

    func queueDiscoveredImports() {
        appendImportCandidates(importService.inspectDiscovered(skills))
    }

    func loadRepositoryImports(_ input: String, ref: String = "") async {
        isBusy = true
        defer { isBusy = false }
        do {
            let candidates = try await importService.inspectRepository(input, ref: ref)
            appendImportCandidates(candidates)
            infoMessage = "Found \(candidates.count) skill candidate(s)."
        } catch {
            errorMessage = "Repository import failed: \(error.localizedDescription)"
        }
    }

    func removeImportCandidate(_ id: UUID) {
        importCandidates.removeAll { $0.id == id }
        if selectedImportCandidateID == id { selectedImportCandidateID = importCandidates.first?.id }
    }

    func importPreview(for candidate: ImportCandidate) -> MutationPreview {
        var steps: [MutationStep] = []
        if candidate.conflictKind == .sameSource {
            steps.append(MutationStep(kind: .write, summary: "Use existing managed source", path: candidate.sourcePath, destination: nil, destructive: false))
        } else if importMode == .manageInPlace {
            steps.append(MutationStep(kind: .write, summary: "Manage source in place", path: candidate.sourcePath, destination: nil, destructive: false))
        } else {
            let destination = importService.plannedLibraryDestination(
                for: candidate,
                settings: settings,
                resolution: importConflictResolution
            ).path
            steps.append(MutationStep(
                kind: .copy,
                summary: importConflictResolution == .replace ? "Replace library source" : "Copy into library",
                path: candidate.sourcePath,
                destination: destination,
                destructive: importConflictResolution == .replace
            ))
        }
        for rootID in selectedImportRootIDs.sorted() {
            if let root = availableRoots.first(where: { $0.id == rootID }) {
                let sourceName = importMode == .copyToLibrary
                    ? importService.plannedLibraryDestination(for: candidate, settings: settings, resolution: importConflictResolution).lastPathComponent
                    : URL(fileURLWithPath: candidate.sourcePath).lastPathComponent
                let installPath = URL(fileURLWithPath: root.path).appendingPathComponent(sourceName).path
                steps.append(MutationStep(kind: .symlink, summary: "Install into \(root.name)", path: destinationPath(for: candidate), destination: installPath, destructive: importConflictResolution == .replace))
            }
        }
        return MutationPreview(
            title: "Import \(candidate.name)",
            message: candidate.conflictKind == .sameName ? "A different source already uses this name. Resolve the conflict before importing." : "Review every planned filesystem change.",
            confirmationText: candidate.name,
            steps: steps
        )
    }

    private func destinationPath(for candidate: ImportCandidate) -> String {
        if importMode == .manageInPlace { return candidate.sourcePath }
        return importService.plannedLibraryDestination(for: candidate, settings: settings, resolution: importConflictResolution).path
    }

    func requestImportSelectedCandidate() {
        guard let candidate = selectedImportCandidate else { return }
        guard candidate.isValid else {
            errorMessage = candidate.validationIssues.joined(separator: " ")
            return
        }
        if candidate.conflictKind == .sameName && importConflictResolution == .cancel {
            errorMessage = "Choose Keep Both or Replace for this same-name conflict."
            return
        }
        var preview = importPreview(for: candidate)
        preview.confirmationText = candidate.name
        pendingMutation = preview
        pendingAction = .importCandidate(candidate.id)
    }

    func importSelectedCandidate() async {
        guard let candidate = selectedImportCandidate else { return }
        guard candidate.isValid else {
            errorMessage = candidate.validationIssues.joined(separator: " ")
            return
        }
        if candidate.conflictKind == .sameName && importConflictResolution == .cancel {
            errorMessage = "Choose Keep Both or Replace for this same-name conflict."
            return
        }

        isBusy = true
        operationResults = []
        defer { isBusy = false }
        do {
            let existing = candidate.existingSkillID.flatMap { id in skills.first(where: { $0.id == id }) }
            var record: SkillRecord
            if candidate.conflictKind == .sameSource, let existing {
                record = existing
            } else {
                let materialized = try importService.materialize(
                    candidate,
                    settings: settings,
                    mode: importMode,
                    resolution: importConflictResolution
                )
                if let existing, importConflictResolution == .replace {
                    record = existing
                    record.source = materialized.source
                    record.sourceIdentity = candidate.stableSourceIdentity
                    record.upstream = materialized.upstream
                    record.managementState = materialized.source.origin == .localLibrary ? .managedLocal : .importedExternal
                    record.description = candidate.description
                    if let index = skills.firstIndex(where: { $0.id == existing.id }) { skills[index] = record }
                } else {
                    record = SkillRecord(
                        id: UUID(),
                        name: candidate.name,
                        description: candidate.description,
                        managementState: materialized.source.origin == .localLibrary ? .managedLocal : .importedExternal,
                        source: materialized.source,
                        installMode: .symlink,
                        installedTargets: [],
                        upstream: materialized.upstream,
                        supportedAgents: [],
                        lastCheckedAt: nil,
                        lastDiffSummary: nil,
                        updatePreview: nil,
                        sourceIdentity: candidate.stableSourceIdentity
                    )
                    skills.append(record)
                }
                operationResults.append(OperationResult(summary: "Imported source", path: record.source.path, succeeded: true, detail: record.name))
            }

            for root in availableRoots.filter({ selectedImportRootIDs.contains($0.id) }) {
                let install = try symlinkService.install(skill: record, into: root, allowReplacing: importConflictResolution == .replace)
                operationResults.append(OperationResult(summary: "Installed into \(root.name)", path: install.installedPath, succeeded: true, detail: record.name))
            }
            removeImportCandidate(candidate.id)
            save()
            infoMessage = "Imported \(candidate.name)."
            await refresh()
        } catch {
            operationResults.append(OperationResult(summary: "Import failed", path: candidate.sourcePath, succeeded: false, detail: error.localizedDescription))
            errorMessage = "Import failed: \(error.localizedDescription)"
            await refresh()
        }
    }

    func refreshAgentDefinitions() {
        definitionLocations = definitionService.locations(settings: settings)
        agentDefinitions = definitionService.discover(settings: settings)
        if selectedDefinitionLocationID == nil { selectedDefinitionLocationID = definitionLocations.first?.id }
        if let selectedAgentDefinitionID, !agentDefinitions.contains(where: { $0.id == selectedAgentDefinitionID }) {
            self.selectedAgentDefinitionID = agentDefinitions.first?.id
        } else if selectedAgentDefinitionID == nil {
            selectedAgentDefinitionID = agentDefinitions.first?.id
        }
    }

    func createAgentDefinition(name: String, description: String, instructions: String, location: AgentDefinitionLocation) {
        do {
            let definition = try definitionService.create(name: name, description: description, instructions: instructions, at: location)
            refreshAgentDefinitions()
            selectedAgentDefinitionID = definition.path
            infoMessage = "Created \(definition.name)."
        } catch {
            errorMessage = "Could not create agent: \(error.localizedDescription)"
        }
    }

    func saveAgentDefinition(_ definition: AgentDefinition, rawMode: Bool, rawContent: String) {
        do {
            if rawMode { try definitionService.saveRaw(rawContent, for: definition) }
            else { try definitionService.saveStructured(definition) }
            refreshAgentDefinitions()
            selectedAgentDefinitionID = definition.id
            infoMessage = "Saved \(definition.name)."
        } catch {
            errorMessage = "Could not save agent definition: \(error.localizedDescription)"
        }
    }

    func previewAgentDefinitionChange(_ definition: AgentDefinition, rawMode: Bool, rawContent: String) -> String {
        do {
            let proposed = rawMode ? rawContent : try definitionService.renderStructured(definition)
            return textDiffService.diff(original: definition.rawContent, updated: proposed)
        } catch {
            return "Cannot preview: \(error.localizedDescription)"
        }
    }

    func validateAgentDefinition(_ definition: AgentDefinition) -> [String] {
        definitionService.validate(definition)
    }

    func duplicateAgentDefinition(_ definition: AgentDefinition) {
        do {
            let duplicate = try definitionService.duplicate(definition)
            refreshAgentDefinitions()
            selectedAgentDefinitionID = duplicate.id
            infoMessage = "Duplicated \(definition.name)."
        } catch {
            errorMessage = "Could not duplicate agent: \(error.localizedDescription)"
        }
    }

    func importAgentDefinition(from url: URL, to location: AgentDefinitionLocation) {
        do {
            let definition = try definitionService.importDefinition(from: url, to: location)
            refreshAgentDefinitions()
            selectedAgentDefinitionID = definition.id
            infoMessage = "Imported \(definition.name)."
        } catch {
            errorMessage = "Could not import agent definition: \(error.localizedDescription)"
        }
    }

    func addWorkspace(url: URL) {
        var workspaces = settings.workspaceRoots ?? []
        let path = (url.path as NSString).standardizingPath
        guard !workspaces.contains(where: { standardized($0.path) == standardized(path) }) else {
            infoMessage = "That workspace is already configured."
            return
        }
        workspaces.append(WorkspaceRoot(name: url.lastPathComponent, path: path))
        settings.workspaceRoots = workspaces
        saveSettings()
        refreshAgentDefinitions()
    }

    func removeWorkspace(_ workspace: WorkspaceRoot) {
        settings.workspaceRoots?.removeAll { $0.id == workspace.id }
        saveSettings()
        refreshAgentDefinitions()
    }

    func addCustomRoot(name: String, path: String, platform: AgentPlatform = .other) {
        let expanded = SkillSmithPaths.expandTilde(path)
        settings.customAgentRoots.append(AgentRoot(
            id: UUID().uuidString,
            name: name,
            path: expanded,
            isCustom: true,
            platform: platform,
            scope: .personal
        ))
        saveSettings()
        availableRoots = rootDiscovery.discoverRoots(settings: settings)
    }

    func updateCustomRoot(_ root: AgentRoot, name: String, path: String, platform: AgentPlatform) {
        guard let index = settings.customAgentRoots.firstIndex(where: { $0.id == root.id }) else { return }
        settings.customAgentRoots[index].name = name
        settings.customAgentRoots[index].path = SkillSmithPaths.expandTilde(path)
        settings.customAgentRoots[index].platform = platform
        saveSettings()
        availableRoots = rootDiscovery.discoverRoots(settings: settings)
    }

    func removeCustomRoot(_ root: AgentRoot) {
        guard root.isCustom else { return }
        settings.customAgentRoots.removeAll { $0.id == root.id }
        saveSettings()
        availableRoots = rootDiscovery.discoverRoots(settings: settings)
    }

    func createRootDirectory(_ root: AgentRoot) {
        do {
            try FileManager.default.createDirectory(atPath: root.path, withIntermediateDirectories: true)
            infoMessage = "Created \(root.name) at \(root.path)."
            availableRoots = rootDiscovery.discoverRoots(settings: settings)
        } catch {
            errorMessage = "Could not create agent root: \(error.localizedDescription)"
        }
    }

    func uninstallAll(from root: AgentRoot) async {
        let affected = skills.compactMap { skill -> (SkillRecord, InstalledSkill)? in
            guard let install = skill.installedTargets.first(where: { $0.rootID == root.id && $0.isCanonicalSource != true }) else { return nil }
            return (skill, install)
        }
        guard !affected.isEmpty else {
            infoMessage = "There are no removable installs in \(root.name)."
            return
        }

        isBusy = true
        operationResults = []
        defer { isBusy = false }
        for (skill, install) in affected {
            do {
                operationResults.append(try await removeInstallInternal(install, from: skill))
            } catch {
                operationResults.append(OperationResult(summary: "Uninstall failed", path: install.installedPath, succeeded: false, detail: error.localizedDescription))
                errorMessage = "Stopped after an uninstall failed: \(error.localizedDescription)"
                break
            }
        }
        await refresh()
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
            if record.managementState != .managedLocal { record.managementState = .managedRemote }
        }
        upstreamSheetPresented = false
        infoMessage = "Linked upstream for \(skill.name)."
        save()
    }

    func checkUpdatesForSelectedSkill() async {
        guard let skill = selectedSkill else { return }
        await checkUpdates(skill)
    }

    func checkUpdatesForLibrarySelection() async {
        for skill in skills.filter({ librarySelection.contains($0.id) }) {
            await checkUpdates(skill)
            if errorMessage != nil { break }
        }
    }

    func requestApplyUpdates(_ ids: Set<UUID>) {
        let selected = skills.filter { ids.contains($0.id) && $0.hasUpdate }
        guard !selected.isEmpty else {
            infoMessage = "No checked updates are available for the selected skills."
            return
        }
        let steps = selected.map { skill in
            MutationStep(
                kind: skill.lockMetadata == nil ? .write : .cli,
                summary: skill.lockMetadata == nil ? "Replace \(skill.name) with the reviewed upstream version" : "Update \(skill.name) through the skills CLI",
                path: skill.source.path,
                destination: skill.upstream.map { "\($0.repo)#\($0.path)@\($0.ref)" },
                destructive: true
            )
        }
        pendingMutation = MutationPreview(
            title: "Apply \(selected.count) reviewed update\(selected.count == 1 ? "" : "s")?",
            message: "Local library sources are replaced only after their exact diff has been checked. Previous versions move to macOS Trash.",
            confirmationText: selected.count == 1 ? selected[0].name : "UPDATE",
            steps: steps
        )
        pendingAction = .updateSkills(Set(selected.map(\.id)))
    }

    private func applyUpdates(ids: Set<UUID>) async {
        operationResults = []
        for skill in skills.filter({ ids.contains($0.id) }) {
            do {
                if skill.lockMetadata != nil {
                    let result = try await skillsCLI.updateSkill(named: skill.name)
                    try requireSuccess(result, action: "Update \(skill.name)")
                    operationResults.append(OperationResult(summary: "Updated with skills CLI", path: skill.source.path, succeeded: true, detail: skill.name))
                } else {
                    let revision = try await gitDiffService.applyUpdate(skill: skill, libraryPath: settings.libraryPath)
                    mutateSkill(named: skill.id) { record in
                        record.upstream?.trackedRevision = revision
                        record.updatePreview = nil
                    }
                    operationResults.append(OperationResult(summary: "Updated library source", path: skill.source.path, succeeded: true, detail: revision))
                }
            } catch {
                operationResults.append(OperationResult(summary: "Update failed", path: skill.source.path, succeeded: false, detail: error.localizedDescription))
                errorMessage = "Stopped after an update failed: \(error.localizedDescription)"
                break
            }
        }
    }

    private func checkUpdates(_ skill: SkillRecord) async {
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
            guard skill.lockMetadata != nil else {
                throw NSError(domain: "SkillSmith.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only skills managed by the skills CLI can currently apply updates automatically. Use the diff preview to update local skills manually."])
            }
            let result = try await skillsCLI.updateSkill(named: skill.name)
            try requireSuccess(result, action: "Update \(skill.name)")
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
            skillsShRepoOutput = stripANSICodes(from: result.stdout.isEmpty ? result.stderr : result.stdout)
        } catch {
            errorMessage = "Could not list skills in \(repo): \(error.localizedDescription)"
        }
    }

    func addSkillsFromSkillsSh(repo: String, skillNames: [String], agentNames: [String]) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await skillsCLI.addSkills(repo: repo, skillNames: skillNames, agentNames: agentNames)
            try requireSuccess(result, action: "Install from \(repo)")
            addFromSkillsShPresented = false
            skillsShRepoOutput = ""
            infoMessage = "Installed from \(repo)."
            await refresh()
        } catch {
            errorMessage = "Install from skills.sh failed: \(error.localizedDescription)"
        }
    }

    func updateAllSkillsShSkills() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await skillsCLI.updateAllGlobalSkills()
            try requireSuccess(result, action: "Update all skills")
            let output = stripANSICodes(from: result.stdout.isEmpty ? result.stderr : result.stdout)
            let lastLine = output.split(separator: "\n", omittingEmptySubsequences: true).last.map(String.init) ?? "Done."
            infoMessage = "skills.sh update: \(lastLine)"
            await refresh()
        } catch {
            errorMessage = "skills.sh update failed: \(error.localizedDescription)"
        }
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

    func installCount(for root: AgentRoot) -> Int {
        skills.reduce(0) { count, skill in
            count + skill.installedTargets.filter { $0.rootID == root.id }.count
        }
    }

    func brokenInstallCount(for root: AgentRoot) -> Int {
        skills.reduce(0) { count, skill in
            count + skill.installedTargets.filter { $0.rootID == root.id && $0.isBroken == true }.count
        }
    }

    func symlinkInstallCount(for root: AgentRoot) -> Int {
        skills.reduce(0) { count, skill in
            count + skill.installedTargets.filter { $0.rootID == root.id && $0.isSymlink }.count
        }
    }

    func copyInstallCount(for root: AgentRoot) -> Int {
        skills.reduce(0) { count, skill in
            count + skill.installedTargets.filter { $0.rootID == root.id && !$0.isSymlink }.count
        }
    }

    private func appendImportCandidates(_ candidates: [ImportCandidate]) {
        let annotated = candidates.map(annotateCandidate)
        for candidate in annotated where !importCandidates.contains(where: { standardized($0.sourcePath) == standardized(candidate.sourcePath) }) {
            importCandidates.append(candidate)
        }
        importCandidates.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if selectedImportCandidateID == nil { selectedImportCandidateID = importCandidates.first?.id }
        if candidates.isEmpty { infoMessage = "No SKILL.md candidates were found." }
    }

    private func annotateCandidate(_ candidate: ImportCandidate) -> ImportCandidate {
        var updated = candidate
        let identity = candidate.stableSourceIdentity
        if let exact = skills.first(where: { $0.stableSourceIdentity == identity || standardized($0.comparisonPath) == standardized(candidate.sourcePath) }) {
            updated.existingSkillID = exact.id
            updated.conflictKind = .sameSource
        } else if let sameName = skills.first(where: { $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame }) {
            updated.existingSkillID = sameName.id
            updated.conflictKind = .sameName
        } else {
            updated.conflictKind = ImportConflictKind.none
        }
        return updated
    }

    private func removeInstallInternal(_ install: InstalledSkill, from skill: SkillRecord) async throws -> OperationResult {
        if install.isCanonicalSource == true {
            throw NSError(domain: "SkillSmith.Remove", code: 1, userInfo: [NSLocalizedDescriptionKey: "This is the skills CLI canonical source. Use Uninstall Everywhere so the CLI lock and dependent installs stay consistent."])
        }
        if skill.lockMetadata != nil,
           let root = availableRoots.first(where: { $0.id == install.rootID }),
           let agent = root.platform?.cliIdentifier {
            let result = try await skillsCLI.removeSkill(named: skill.name, fromAgent: agent)
            try requireSuccess(result, action: "Remove \(skill.name) from \(root.name)")
            return OperationResult(summary: "Removed with skills CLI", path: install.installedPath, succeeded: true, detail: root.name)
        }
        return try fileOperations.removeInstall(install, roots: availableRoots)
    }

    private func uninstallSkillInternal(_ skill: SkillRecord) async throws {
        if skill.lockMetadata != nil {
            let result = try await skillsCLI.removeSkill(named: skill.name, global: true)
            try requireSuccess(result, action: "Uninstall \(skill.name)")
            operationResults.append(OperationResult(summary: "Uninstalled everywhere", path: skill.source.path, succeeded: true, detail: skill.name))
        } else {
            for install in skill.installedTargets where install.isCanonicalSource != true {
                operationResults.append(try fileOperations.removeInstall(install, roots: availableRoots))
            }
        }
    }

    private func makeRecord(
        name: String,
        path: String,
        origin: SkillSourceOrigin,
        editable: Bool,
        state: SkillManagementState
    ) -> SkillRecord {
        SkillRecord(
            id: UUID(),
            name: name,
            description: SkillMetadataParser.readDescription(at: path),
            managementState: state,
            source: SkillSource(path: path, origin: origin, editable: editable),
            installMode: .symlink,
            installedTargets: [],
            upstream: nil,
            supportedAgents: [],
            lastCheckedAt: nil,
            lastDiffSummary: nil,
            updatePreview: nil,
            sourceIdentity: SkillSourceIdentity.pathIdentity(path)
        )
    }

    private func rootForInstallPath(_ path: String) -> AgentRoot? {
        availableRoots.sorted { $0.path.count > $1.path.count }.first { root in
            let rootPath = standardized(root.path)
            let installPath = standardized(path)
            return installPath.hasPrefix(rootPath + "/")
        }
    }

    private func synchronizeSelections() {
        if selectedSkillID == nil || !skills.contains(where: { $0.id == selectedSkillID }) {
            selectedSkillID = skills.first?.id
        }
        librarySelection = librarySelection.filter { id in skills.contains(where: { $0.id == id }) }
        if librarySelection.isEmpty, selectedSection == .library, let first = skills.first {
            librarySelection = [first.id]
        }
        if selectedAgentRootID == nil || !availableRoots.contains(where: { $0.id == selectedAgentRootID }) {
            selectedAgentRootID = availableRoots.first?.id
        }
    }

    private func mutateSkill(named id: UUID, mutate: (inout SkillRecord) -> Void) {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return }
        mutate(&skills[index])
    }

    private func mergeTargets(_ current: [InstalledSkill], _ newTarget: InstalledSkill) -> [InstalledSkill] {
        var updated = current
        if let index = updated.firstIndex(where: { $0.id == newTarget.id }) { updated[index] = newTarget }
        else { updated.append(newTarget) }
        return updated.sorted { $0.rootName < $1.rootName }
    }

    private func sorted<S: Sequence>(_ values: S) -> [SkillRecord] where S.Element == SkillRecord {
        values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison == .orderedSame { return $0.source.path < $1.source.path }
            return comparison == .orderedAscending
        }
    }

    private func standardized(_ path: String) -> String {
        ((path as NSString).expandingTildeInPath as NSString).standardizingPath
    }

    private func isInside(_ path: String, parent: String) -> Bool {
        let child = standardized(path)
        let root = standardized(parent)
        return child == root || child.hasPrefix(root + "/")
    }

    private func requireSuccess(_ result: CommandResult, action: String) throws {
        guard result.exitCode == 0 else {
            let output = stripANSICodes(from: result.stderr.isEmpty ? result.stdout : result.stderr)
            throw NSError(domain: "SkillSmith.CLI", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: "\(action) failed: \(output.prefix(500))"])
        }
    }

    private func stripANSICodes(from text: String) -> String {
        text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }

    private func save() {
        do {
            try appStateStore.saveState(PersistedAppState(schemaVersion: 2, settings: settings, skills: skills))
        } catch {
            errorMessage = "Could not save SkillSmith state: \(error.localizedDescription)"
        }
    }
}
