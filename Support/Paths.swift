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
                isCustom: false
            ),
            AgentRoot(
                id: "codex-global",
                name: "Codex",
                path: expandTilde("~/.codex/skills"),
                isCustom: false
            ),
            AgentRoot(
                id: "agents-global",
                name: "Agents (shared)",
                path: expandTilde("~/.agents/skills"),
                isCustom: false
            ),
            AgentRoot(
                id: "cursor-global",
                name: "Cursor",
                path: expandTilde("~/.cursor/skills"),
                isCustom: false
            ),
            AgentRoot(
                id: "gemini-global",
                name: "Gemini CLI",
                path: expandTilde("~/.gemini/skills"),
                isCustom: false
            )
        ]
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
