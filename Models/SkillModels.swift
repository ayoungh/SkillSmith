import Foundation

enum SidebarSection: String, CaseIterable, Codable, Identifiable {
    case allSkills = "All Skills"
    case installed = "Installed"
    case updates = "Updates"
    case library = "Library"
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

struct SkillSource: Codable, Hashable {
    var path: String
    var origin: SkillSourceOrigin
    var editable: Bool
}

struct InstalledSkill: Codable, Hashable, Identifiable {
    var id: String { "\(rootID)::\(installedPath)" }
    var rootID: String
    var rootName: String
    var installedPath: String
    var agentNames: [String]
    var isSymlink: Bool
    var symlinkDestination: String?
}

struct AgentRoot: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var path: String
    var isCustom: Bool
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

    var hasUpdate: Bool {
        updatePreview?.status == .changesAvailable || upstream?.deletedUpstream == true
    }

    var comparisonPath: String {
        if !source.path.isEmpty {
            return source.path
        }
        return installedTargets.first?.installedPath ?? ""
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
    var settings: AppSettings
    var skills: [SkillRecord]
}

struct CLIInstalledSkill: Codable, Hashable {
    var name: String
    var path: String
    var scope: String
    var agents: [String]
}
