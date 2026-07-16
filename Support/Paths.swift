import Foundation

enum SkillSmithPaths {
    static let keychainService = "SkillSmith"

    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static var defaultLibraryPath: String {
        expandTilde("~/AgentSkillsLibrary")
    }

    static var defaultAgentRoots: [AgentRoot] {
        [
            AgentRoot(
                id: "claude-global",
                name: "Claude Code",
                path: expandTilde("~/.claude/skills"),
                isCustom: false,
                platform: .claude,
                scope: .personal
            ),
            AgentRoot(
                id: "codex-global",
                name: "Codex",
                path: expandTilde("~/.codex/skills"),
                isCustom: false,
                platform: .codex,
                scope: .personal
            ),
            AgentRoot(
                id: "agents-global",
                name: "Agents (shared)",
                path: expandTilde("~/.agents/skills"),
                isCustom: false,
                platform: .shared,
                scope: .personal
            ),
            AgentRoot(
                id: "cursor-global",
                name: "Cursor",
                path: expandTilde("~/.cursor/skills"),
                isCustom: false,
                platform: .cursor,
                scope: .personal
            ),
            AgentRoot(
                id: "gemini-global",
                name: "Gemini CLI",
                path: expandTilde("~/.gemini/skills"),
                isCustom: false,
                platform: .gemini,
                scope: .personal
            )
        ]
    }

    static var skillsLockURL: URL {
        URL(fileURLWithPath: expandTilde("~/.agents/.skill-lock.json"))
    }

    static func personalAgentDefinitionDirectory(for platform: AgentPlatform) -> URL? {
        switch platform {
        case .claude:
            URL(fileURLWithPath: expandTilde("~/.claude/agents"), isDirectory: true)
        case .codex:
            URL(fileURLWithPath: expandTilde("~/.codex/agents"), isDirectory: true)
        case .gemini:
            URL(fileURLWithPath: expandTilde("~/.gemini/agents"), isDirectory: true)
        case .cursor, .shared, .other:
            nil
        }
    }

    static func projectAgentDefinitionDirectory(for platform: AgentPlatform, workspacePath: String) -> URL? {
        let root = URL(fileURLWithPath: expandTilde(workspacePath), isDirectory: true)
        switch platform {
        case .claude:
            return root.appendingPathComponent(".claude/agents", isDirectory: true)
        case .codex:
            return root.appendingPathComponent(".codex/agents", isDirectory: true)
        case .gemini:
            return root.appendingPathComponent(".gemini/agents", isDirectory: true)
        case .cursor, .shared, .other:
            return nil
        }
    }

    /// Resolves a symlink to an absolute, standardized destination path.
    /// Relative destinations are resolved against the symlink's parent directory.
    static func resolvedSymlinkDestination(atPath path: String) -> String? {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return nil
        }
        if destination.hasPrefix("/") {
            return (destination as NSString).standardizingPath
        }
        let parent = (path as NSString).deletingLastPathComponent
        return ((parent as NSString).appendingPathComponent(destination) as NSString).standardizingPath
    }

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SkillSmith", isDirectory: true)
    }

    static var metadataStoreURL: URL {
        applicationSupportDirectory.appendingPathComponent("state.json")
    }
}
