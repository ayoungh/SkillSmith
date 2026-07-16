import Foundation

enum ActivityKind: String, Hashable, Sendable {
    case bootstrap
    case refresh
    case diagnostics
    case createSkill
    case install
    case remove
    case uninstall
    case destructiveMutation
    case saveSkill
    case loadRepository
    case importSkill
    case checkUpdates
    case applyUpdate
    case previewSkillsSh
    case addSkillsSh
    case updateAll

    var isMutating: Bool {
        switch self {
        case .createSkill, .install, .remove, .uninstall, .destructiveMutation,
             .saveSkill, .importSkill, .applyUpdate, .addSkillsSh, .updateAll:
            true
        case .bootstrap, .refresh, .diagnostics, .loadRepository,
             .checkUpdates, .previewSkillsSh:
            false
        }
    }
}

enum ActivityScope: Hashable, Sendable {
    case app
    case skills
    case library
    case imports
    case agents
    case diagnostics
    case skill(UUID)
    case createSkill
    case skillsSh
    case mutation
}

struct AppActivity: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: ActivityKind
    let scope: ActivityScope
    let message: String

    init(
        id: UUID = UUID(),
        kind: ActivityKind,
        scope: ActivityScope,
        message: String
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.message = message
    }
}

struct ActivityRegistry: Sendable {
    private(set) var activities: [AppActivity] = []

    var isMutationActive: Bool {
        activities.contains { $0.kind.isMutating }
    }

    mutating func begin(
        kind: ActivityKind,
        scope: ActivityScope,
        message: String
    ) -> AppActivity.ID {
        let activity = AppActivity(kind: kind, scope: scope, message: message)
        activities.append(activity)
        return activity.id
    }

    mutating func end(_ id: AppActivity.ID) {
        activities.removeAll { $0.id == id }
    }

    func isActive(kind: ActivityKind? = nil, scope: ActivityScope? = nil) -> Bool {
        activities.contains { activity in
            (kind == nil || activity.kind == kind) &&
                (scope == nil || activity.scope == scope)
        }
    }

    func message(for scope: ActivityScope) -> String? {
        activities.last(where: { $0.scope == scope })?.message
    }
}

enum LoadingPresentation {
    static func showsInitialPlaceholder(
        hasCompletedInitialDiscovery: Bool,
        hasContent: Bool
    ) -> Bool {
        !hasCompletedInitialDiscovery && !hasContent
    }
}
