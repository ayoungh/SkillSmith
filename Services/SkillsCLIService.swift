import Foundation

struct SkillsCLIService {
    private let shell = ShellCommandService()

    func checkAvailability() async -> String {
        do {
            let result = try await shell.run("/usr/bin/env", arguments: ["npx", "skills", "--version"])
            let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return version.isEmpty ? "skills.sh CLI available" : "skills.sh CLI v\(version)"
        } catch {
            return "skills.sh CLI unavailable: \(error.localizedDescription)"
        }
    }

    func listGlobalSkills() async throws -> [CLIInstalledSkill] {
        // The Node-based CLI truncates large output at the 64KB pipe buffer
        // (async stdout writes are dropped on exit), so capture via a file.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsmith-ls-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        _ = try await shell.run(
            "/bin/zsh",
            arguments: ["-c", "npx skills ls -g --json > \(shellQuoted(tempURL.path))"]
        )
        let data = try Data(contentsOf: tempURL)
        return try JSONDecoder().decode([CLIInstalledSkill].self, from: data)
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func updateSkill(named name: String) async throws -> CommandResult {
        try await shell.run("/usr/bin/env", arguments: ["npx", "skills", "update", name], allowNonZeroExit: true)
    }

    func updateAllGlobalSkills() async throws -> CommandResult {
        try await shell.run("/usr/bin/env", arguments: ["npx", "skills", "update", "-g", "-y"], allowNonZeroExit: true)
    }

    /// Lists the skills available in a skills.sh package (e.g. "vercel-labs/agent-skills")
    /// without installing anything.
    func listRepoSkills(repo: String) async throws -> CommandResult {
        try await shell.run("/usr/bin/env", arguments: ["npx", "skills", "add", repo, "--list"], allowNonZeroExit: true)
    }

    func addSkills(repo: String, skillNames: [String], agentNames: [String]) async throws -> CommandResult {
        var args = ["npx", "skills", "add", repo, "-g", "-y", "--skill"]
        args.append(contentsOf: skillNames.isEmpty ? ["*"] : skillNames)
        args.append("--agent")
        args.append(contentsOf: agentNames.isEmpty ? ["*"] : agentNames)
        return try await shell.run("/usr/bin/env", arguments: args, allowNonZeroExit: true)
    }

    func removeSkill(named name: String, global: Bool = true) async throws -> CommandResult {
        var args = ["npx", "skills", "remove", name, "-y"]
        if global {
            args.append("-g")
        }
        return try await shell.run("/usr/bin/env", arguments: args, allowNonZeroExit: true)
    }

    func findSkills(query: String, owner: String? = nil) async throws -> CommandResult {
        var args = ["npx", "skills", "find", query]
        if let owner, !owner.isEmpty {
            args.append(contentsOf: ["--owner", owner])
        }
        return try await shell.run("/usr/bin/env", arguments: args, allowNonZeroExit: true)
    }
}
