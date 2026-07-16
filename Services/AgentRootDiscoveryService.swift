import Foundation

struct ScannedSkillInstallation: Hashable {
    var name: String
    var installedSkill: InstalledSkill
}

struct AgentRootDiscoveryService {
    func discoverRoots(settings: AppSettings) -> [AgentRoot] {
        (SkillSmithPaths.defaultAgentRoots + settings.customAgentRoots)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func scanSkillInstallations(roots: [AgentRoot]) -> [ScannedSkillInstallation] {
        let fileManager = FileManager.default
        var results: [ScannedSkillInstallation] = []

        for root in roots {
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
                guard fileManager.fileExists(atPath: contentPath + "/SKILL.md") else { continue }

                let skill = InstalledSkill(
                    rootID: root.id,
                    rootName: root.name,
                    installedPath: entry.path,
                    agentNames: [root.name],
                    isSymlink: isSymlink,
                    symlinkDestination: destination
                )
                results.append(ScannedSkillInstallation(name: name, installedSkill: skill))
            }
        }

        return results
    }
}
