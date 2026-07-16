import Foundation

struct ScannedSkillInstallation: Hashable {
    var name: String
    var installedSkill: InstalledSkill
}

struct ScannedLibrarySkill: Hashable {
    var name: String
    var path: String
}

struct AgentRootDiscoveryService {
    func discoverRoots(settings: AppSettings) -> [AgentRoot] {
        deduplicated(SkillSmithPaths.defaultAgentRoots + settings.customAgentRoots)
    }

    func dynamicRoots(from cliSkills: [CLIInstalledSkill], excluding configuredRoots: [AgentRoot]) -> [AgentRoot] {
        let parentPaths = Set(cliSkills.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path })
        let unknown = parentPaths.filter { parent in
            !configuredRoots.contains { parent == $0.path || parent.hasPrefix($0.path + "/") }
        }

        return unknown.sorted().map { path in
            AgentRoot(
                id: "dynamic:\(path)",
                name: inferredRootName(from: path),
                path: path,
                isCustom: false,
                platform: inferredPlatform(from: path),
                scope: .external
            )
        }
    }

    func scanSkillInstallations(roots: [AgentRoot]) -> [ScannedSkillInstallation] {
        let fileManager = FileManager.default
        var results: [ScannedSkillInstallation] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: root.path),
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                let name = entry.lastPathComponent
                if name == ".system" { continue }

                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                let isSymlink = values?.isSymbolicLink == true
                let isDirectory = values?.isDirectory == true || isSymlink
                guard isDirectory else { continue }

                let destination = isSymlink ? SkillSmithPaths.resolvedSymlinkDestination(atPath: entry.path) : nil
                let contentPath = destination ?? entry.path
                let isBroken = isSymlink && !fileManager.fileExists(atPath: contentPath)
                guard isBroken || fileManager.fileExists(atPath: contentPath + "/SKILL.md") else { continue }

                let skill = InstalledSkill(
                    rootID: root.id,
                    rootName: root.name,
                    installedPath: entry.path,
                    agentNames: [root.name],
                    isSymlink: isSymlink,
                    symlinkDestination: destination,
                    isBroken: isBroken
                )
                results.append(ScannedSkillInstallation(name: name, installedSkill: skill))
            }
        }

        return results
    }

    func scanLibrary(at path: String) -> [ScannedLibrarySkill] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path),
              let entries = try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        return entries.compactMap { entry in
            guard fileManager.fileExists(atPath: entry.appendingPathComponent("SKILL.md").path) else { return nil }
            return ScannedLibrarySkill(name: entry.lastPathComponent, path: entry.path)
        }
    }

    private func deduplicated(_ roots: [AgentRoot]) -> [AgentRoot] {
        var seen = Set<String>()
        return roots.filter { root in
            let key = (root.path as NSString).standardizingPath.lowercased()
            return seen.insert(key).inserted
        }
    }

    private func inferredRootName(from path: String) -> String {
        let lower = path.lowercased()
        if lower.contains("antigravity") { return "Antigravity" }
        if lower.contains("openclaw") { return "OpenClaw" }
        if lower.contains("copilot") { return "GitHub Copilot" }
        if lower.contains("windsurf") { return "Windsurf" }
        return URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent.capitalized
    }

    private func inferredPlatform(from path: String) -> AgentPlatform {
        let lower = path.lowercased()
        if lower.contains("claude") { return .claude }
        if lower.contains("codex") { return .codex }
        if lower.contains("cursor") { return .cursor }
        if lower.contains("gemini") || lower.contains("antigravity") { return .gemini }
        return .other
    }
}
