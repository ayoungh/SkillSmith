import Foundation

struct FileOperationService {
    private let fileManager = FileManager.default

    func writeAtomically(_ content: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func validateInstallPath(_ path: String, roots: [AgentRoot]) throws {
        let standardizedPath = (path as NSString).standardizingPath
        let parent = (standardizedPath as NSString).deletingLastPathComponent
        let allowed = roots.contains { root in
            (root.path as NSString).standardizingPath == parent
        }
        guard allowed else {
            throw operationError("Refusing to modify a path outside the configured agent roots: \(path)")
        }
    }

    func validateLibrarySource(_ path: String, libraryPath: String) throws {
        let source = (path as NSString).standardizingPath
        let library = (libraryPath as NSString).standardizingPath
        guard source != library, source.hasPrefix(library + "/") else {
            throw operationError("Refusing to delete a source outside the SkillSmith library: \(path)")
        }
    }

    func removeInstall(_ install: InstalledSkill, roots: [AgentRoot]) throws -> OperationResult {
        try validateInstallPath(install.installedPath, roots: roots)
        guard fileManager.fileExists(atPath: install.installedPath) || install.isBroken == true else {
            return OperationResult(summary: "Already removed", path: install.installedPath, succeeded: true, detail: "The install no longer exists.")
        }

        if install.isSymlink || install.isBroken == true {
            try fileManager.removeItem(atPath: install.installedPath)
            return OperationResult(summary: "Removed symlink", path: install.installedPath, succeeded: true, detail: "The source was not changed.")
        }

        try moveToTrash(URL(fileURLWithPath: install.installedPath))
        return OperationResult(summary: "Moved install to Trash", path: install.installedPath, succeeded: true, detail: "The canonical source was not changed.")
    }

    func deleteManagedSource(_ skill: SkillRecord, libraryPath: String) throws -> OperationResult {
        guard skill.source.origin == .localLibrary else {
            throw operationError("Only sources inside the SkillSmith library can be deleted.")
        }
        try validateLibrarySource(skill.source.path, libraryPath: libraryPath)
        guard fileManager.fileExists(atPath: skill.source.path) else {
            return OperationResult(summary: "Source already missing", path: skill.source.path, succeeded: true, detail: "Metadata can be removed safely.")
        }
        try moveToTrash(URL(fileURLWithPath: skill.source.path))
        return OperationResult(summary: "Moved source to Trash", path: skill.source.path, succeeded: true, detail: "The source can be restored from macOS Trash.")
    }

    func replaceManagedSource(at sourceURL: URL, with incomingURL: URL, libraryPath: String) throws {
        try validateLibrarySource(sourceURL.path, libraryPath: libraryPath)
        guard fileManager.fileExists(atPath: incomingURL.appendingPathComponent("SKILL.md").path) else {
            throw operationError("The update candidate does not contain SKILL.md: \(incomingURL.path)")
        }

        let parent = sourceURL.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".skillsmith-update-\(UUID().uuidString)", isDirectory: true)
        let backup = parent.appendingPathComponent(".skillsmith-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.copyItem(at: incomingURL, to: staging)
        do {
            try fileManager.moveItem(at: sourceURL, to: backup)
            do {
                try fileManager.moveItem(at: staging, to: sourceURL)
            } catch {
                try? fileManager.moveItem(at: backup, to: sourceURL)
                throw error
            }
            try moveToTrash(backup)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func moveToTrash(_ url: URL) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    }

    private func operationError(_ message: String) -> NSError {
        NSError(domain: "SkillSmith.FileOperations", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
