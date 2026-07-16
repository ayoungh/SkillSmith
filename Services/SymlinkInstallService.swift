import Foundation

struct SymlinkInstallService {
    func install(skill: SkillRecord, into root: AgentRoot, allowReplacing: Bool = false) throws -> InstalledSkill {
        let sourcePath = skill.source.path
        let destinationURL = URL(fileURLWithPath: root.path).appendingPathComponent(skill.installName, isDirectory: true)

        guard FileManager.default.fileExists(atPath: sourcePath + "/SKILL.md") else {
            throw NSError(
                domain: "SkillSmith.SymlinkInstall",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The source does not contain SKILL.md: \(sourcePath)"]
            )
        }

        try FileManager.default.createDirectory(atPath: root.path, withIntermediateDirectories: true)
        let existingSymlink = SkillSmithPaths.resolvedSymlinkDestination(atPath: destinationURL.path)
        if FileManager.default.fileExists(atPath: destinationURL.path) || existingSymlink != nil {
            if let existing = existingSymlink,
               (existing as NSString).standardizingPath == (sourcePath as NSString).standardizingPath {
                return InstalledSkill(
                    rootID: root.id,
                    rootName: root.name,
                    installedPath: destinationURL.path,
                    agentNames: [root.name],
                    isSymlink: true,
                    symlinkDestination: sourcePath,
                    isBroken: false
                )
            }
            guard allowReplacing else {
                throw NSError(
                    domain: "SkillSmith.SymlinkInstall",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "An item already exists at \(destinationURL.path). Review and confirm replacement first."]
                )
            }
            if existingSymlink != nil {
                try FileManager.default.removeItem(at: destinationURL)
            } else {
                try FileOperationService().moveToTrash(destinationURL)
            }
        }

        try FileManager.default.createSymbolicLink(atPath: destinationURL.path, withDestinationPath: sourcePath)

        return InstalledSkill(
            rootID: root.id,
            rootName: root.name,
            installedPath: destinationURL.path,
            agentNames: [root.name],
            isSymlink: true,
            symlinkDestination: sourcePath,
            isBroken: false
        )
    }

    func removeInstall(_ install: InstalledSkill) throws {
        guard FileManager.default.fileExists(atPath: install.installedPath) else { return }
        try FileManager.default.removeItem(atPath: install.installedPath)
    }
}
