import Foundation

struct SymlinkInstallService {
    func install(skill: SkillRecord, into root: AgentRoot) throws -> InstalledSkill {
        let sourcePath = skill.source.path
        let destinationURL = URL(fileURLWithPath: root.path).appendingPathComponent(skill.name, isDirectory: true)

        try FileManager.default.createDirectory(atPath: root.path, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.createSymbolicLink(atPath: destinationURL.path, withDestinationPath: sourcePath)

        return InstalledSkill(
            rootID: root.id,
            rootName: root.name,
            installedPath: destinationURL.path,
            agentNames: [root.name],
            isSymlink: true,
            symlinkDestination: sourcePath
        )
    }

    func removeInstall(_ install: InstalledSkill) throws {
        guard FileManager.default.fileExists(atPath: install.installedPath) else { return }
        try FileManager.default.removeItem(atPath: install.installedPath)
    }
}
