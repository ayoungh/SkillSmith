import Foundation

enum SidebarSection: String, CaseIterable, Codable, Identifiable {
    case allSkills = "All Skills"
    case installed = "Installed"
    case updates = "Updates"
    case library = "Skills Library"
    case imports = "Imports"
    case agents = "Agents"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .allSkills: "square.grid.2x2"
        case .installed: "checkmark.circle"
        case .updates: "arrow.trianglehead.clockwise"
        case .library: "books.vertical"
        case .imports: "tray.and.arrow.down"
        case .agents: "person.2"
        case .settings: "gearshape"
        }
    }
}

enum SkillManagementState: String, Codable, CaseIterable {
    case managedLocal
    case managedRemote
    case externalImportable
    case importedExternal

    var label: String {
        switch self {
        case .managedLocal: "Managed Local"
        case .managedRemote: "Managed Remote"
        case .externalImportable: "Importable"
        case .importedExternal: "Imported"
        }
    }
}

enum SkillInstallMode: String, Codable, CaseIterable {
    case symlink
    case copy
}

enum SkillSourceOrigin: String, Codable {
    case localLibrary
    case importedInstall
    case installedPath
    case remoteInstall
}

enum UpdateStatus: String, Codable {
    case noChanges
    case changesAvailable
    case deletedUpstream
    case unavailable
}

enum AgentPlatform: String, Codable, CaseIterable, Identifiable {
    case claude = "Claude Code"
    case codex = "Codex"
    case cursor = "Cursor"
    case gemini = "Gemini CLI"
    case shared = "Shared"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .claude: "brain.head.profile"
        case .codex: "terminal"
        case .cursor: "cursorarrow.rays"
        case .gemini: "sparkles"
        case .shared: "person.2"
        case .other: "shippingbox"
        }
    }

    var cliIdentifier: String? {
        switch self {
        case .claude: "claude-code"
        case .codex: "codex"
        case .cursor: "cursor"
        case .gemini: "gemini-cli"
        case .shared, .other: nil
        }
    }
}

enum ResourceScope: String, Codable, CaseIterable, Identifiable {
    case personal = "Personal"
    case project = "Project"
    case external = "External"

    var id: String { rawValue }
}

struct SkillSource: Codable, Hashable {
    var path: String
    var origin: SkillSourceOrigin
    var editable: Bool
}

struct SkillLockMetadata: Codable, Hashable {
    var source: String
    var sourceType: String
    var sourceURL: String
    var skillPath: String
    var folderHash: String?
    var installedAt: Date?
    var updatedAt: Date?

    var identity: String {
        SkillSourceIdentity.remoteIdentity(repo: sourceURL, path: skillPath)
    }
}

struct InstalledSkill: Codable, Hashable, Identifiable {
    var id: String { "\(rootID)::\(installedPath)" }
    var rootID: String
    var rootName: String
    var installedPath: String
    var agentNames: [String]
    var isSymlink: Bool
    var symlinkDestination: String?
    var isBroken: Bool? = nil
    var isCanonicalSource: Bool? = nil

    var healthLabel: String {
        if isBroken == true { return "Broken" }
        return isSymlink ? "Symlink" : "Copy"
    }
}

struct AgentRoot: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var path: String
    var isCustom: Bool
    var platform: AgentPlatform? = nil
    var scope: ResourceScope? = nil

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

struct WorkspaceRoot: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var path: String
    var enabled: Bool

    init(id: String = UUID().uuidString, name: String, path: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.path = path
        self.enabled = enabled
    }
}

struct SkillUpstream: Codable, Hashable {
    var repo: String
    var path: String
    var ref: String
    var trackedRevision: String?
    var lastKnownRemoteRevision: String?
    var deletedUpstream: Bool
}

struct DiffFile: Codable, Hashable, Identifiable {
    var id: String { path + status }
    var path: String
    var status: String
    var patch: String
}

struct UpdatePreview: Codable, Hashable {
    var status: UpdateStatus
    var summary: String
    var localRevision: String?
    var remoteRevision: String?
    var changedFiles: [DiffFile]
    var diffText: String
    var checkedAt: Date
}

struct CommandResult: Codable, Hashable {
    var launchPath: String
    var arguments: [String]
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

struct AppSettings: Codable, Hashable {
    var libraryPath: String
    var customAgentRoots: [AgentRoot]
    var preferredModel: String
    var apiKeyAccountName: String
    var workspaceRoots: [WorkspaceRoot]?

    init(
        libraryPath: String,
        customAgentRoots: [AgentRoot],
        preferredModel: String,
        apiKeyAccountName: String,
        workspaceRoots: [WorkspaceRoot]? = []
    ) {
        self.libraryPath = libraryPath
        self.customAgentRoots = customAgentRoots
        self.preferredModel = preferredModel
        self.apiKeyAccountName = apiKeyAccountName
        self.workspaceRoots = workspaceRoots
    }

    var enabledWorkspaces: [WorkspaceRoot] {
        (workspaceRoots ?? []).filter(\.enabled)
    }
}

struct SkillRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var description: String
    var managementState: SkillManagementState
    var source: SkillSource
    var installMode: SkillInstallMode
    var installedTargets: [InstalledSkill]
    var upstream: SkillUpstream?
    var supportedAgents: [String]
    var lastCheckedAt: Date?
    var lastDiffSummary: String?
    var updatePreview: UpdatePreview?
    var sourceIdentity: String? = nil
    var lockMetadata: SkillLockMetadata? = nil
    var healthIssues: [String]? = nil

    var hasUpdate: Bool {
        updatePreview?.status == .changesAvailable || upstream?.deletedUpstream == true
    }

    var comparisonPath: String {
        if !source.path.isEmpty {
            return source.path
        }
        return installedTargets.first?.installedPath ?? ""
    }

    var stableSourceIdentity: String {
        if let sourceIdentity, !sourceIdentity.isEmpty { return sourceIdentity }
        if let lockMetadata { return lockMetadata.identity }
        return SkillSourceIdentity.pathIdentity(source.path.isEmpty ? comparisonPath : source.path)
    }

    var isManagedLibrarySource: Bool {
        source.origin == .localLibrary
    }

    var issueCount: Int {
        (healthIssues ?? []).count + installedTargets.filter { $0.isBroken == true }.count
    }

    var installName: String {
        if source.origin == .localLibrary || source.editable {
            let folder = URL(fileURLWithPath: source.path).lastPathComponent
            if !folder.isEmpty { return folder }
        }
        return name
    }

    var sourceSortValue: String {
        "\(source.origin.rawValue)::\(source.path.lowercased())"
    }

    var installSortValue: Int {
        installedTargets.filter { $0.isCanonicalSource != true }.count
    }

    var statusSortValue: String {
        if hasUpdate { return "0-update" }
        if issueCount > 0 { return "1-issue-\(issueCount)" }
        return "2-\(managementState.rawValue)"
    }
}

enum SkillSourceIdentity {
    static func pathIdentity(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        return "path:\(standardized.lowercased())"
    }

    static func remoteIdentity(repo: String, path: String) -> String {
        var normalizedRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        normalizedRepo = normalizedRepo
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "http://github.com/", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "")
        if normalizedRepo.hasSuffix(".git") { normalizedRepo.removeLast(4) }
        normalizedRepo = normalizedRepo.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return "remote:\(normalizedRepo)#\(normalizedPath.isEmpty ? "." : normalizedPath)"
    }
}

struct SkillDraftSpec: Codable, Hashable {
    var name: String
    var description: String
    var whenToUse: String
    var supportedAgents: [String]
    var includeAgentMetadata: Bool
    var includeReferencesFolder: Bool
    var includeScriptsFolder: Bool
    var includeAssetsFolder: Bool
    var upstreamSeed: String
    var desiredTone: String
}

struct PersistedAppState: Codable {
    var schemaVersion: Int?
    var settings: AppSettings
    var skills: [SkillRecord]

    init(schemaVersion: Int? = 2, settings: AppSettings, skills: [SkillRecord]) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.skills = skills
    }
}

struct CLIInstalledSkill: Codable, Hashable {
    var name: String
    var path: String
    var scope: String
    var agents: [String]
}

enum AgentDefinitionFormat: String, Codable {
    case markdownYAML
    case toml
}

struct AgentDefinition: Hashable, Identifiable {
    var id: String { path }
    var name: String
    var description: String
    var instructions: String
    var platform: AgentPlatform
    var scope: ResourceScope
    var workspaceName: String?
    var path: String
    var format: AgentDefinitionFormat
    var model: String
    var tools: [String]
    var permissionMode: String
    var maxTurns: Int?
    var rawContent: String
    var validationIssues: [String]
    var isEditable: Bool

    var isValid: Bool { validationIssues.isEmpty }
    var platformSortValue: String { platform.rawValue }
    var scopeSortValue: String { workspaceName ?? scope.rawValue }
    var statusSortValue: Int { validationIssues.count }
}

struct AgentDefinitionLocation: Hashable, Identifiable {
    var id: String { "\(platform.rawValue)::\(scope.rawValue)::\(path)" }
    var platform: AgentPlatform
    var scope: ResourceScope
    var workspaceName: String?
    var path: String

    var displayName: String {
        if let workspaceName { return "\(platform.rawValue) — \(workspaceName)" }
        return "\(platform.rawValue) — \(scope.rawValue)"
    }
}

enum ImportSourceKind: String, Codable, CaseIterable, Identifiable {
    case localFolder = "Local Folder"
    case droppedItem = "Dropped Item"
    case discoveredInstall = "Discovered Install"
    case repository = "Repository"

    var id: String { rawValue }
}

enum ImportMode: String, Codable, CaseIterable, Identifiable {
    case copyToLibrary = "Copy to Library"
    case manageInPlace = "Manage in Place"

    var id: String { rawValue }
}

enum ImportConflictResolution: String, Codable, CaseIterable, Identifiable {
    case cancel = "Cancel"
    case keepBoth = "Keep Both"
    case replace = "Replace"

    var id: String { rawValue }
}

enum ImportConflictKind: String, Codable {
    case none
    case sameSource
    case sameName
}

struct ImportCandidate: Hashable, Identifiable {
    var id: UUID
    var name: String
    var description: String
    var sourcePath: String
    var sourceKind: ImportSourceKind
    var sourceRepo: String?
    var sourceRepoPath: String?
    var sourceRef: String?
    var sourceRevision: String?
    var validationIssues: [String]
    var existingSkillID: UUID?
    var conflictKind: ImportConflictKind? = nil

    var isValid: Bool { validationIssues.isEmpty }

    var stableSourceIdentity: String {
        if let sourceRepo {
            return SkillSourceIdentity.remoteIdentity(repo: sourceRepo, path: sourceRepoPath ?? ".")
        }
        return SkillSourceIdentity.pathIdentity(sourcePath)
    }

    var sourceKindSortValue: String { sourceKind.rawValue }
    var conflictSortValue: Int {
        switch conflictKind ?? .none {
        case .none: 0
        case .sameSource: 1
        case .sameName: 2
        }
    }
    var validationSortValue: Int { validationIssues.count }
}

enum MutationKind: String, Codable {
    case copy
    case symlink
    case unlink
    case trash
    case write
    case cli
}

struct MutationStep: Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: MutationKind
    var summary: String
    var path: String
    var destination: String?
    var destructive: Bool
}

struct MutationPreview: Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var message: String
    var confirmationText: String
    var steps: [MutationStep]
}

struct OperationResult: Hashable, Identifiable {
    var id: UUID = UUID()
    var summary: String
    var path: String
    var succeeded: Bool
    var detail: String
}
