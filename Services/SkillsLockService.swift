import Foundation

struct SkillsLockService {
    private struct LockFile: Decodable {
        var version: Int
        var skills: [String: LockEntry]
        var lastSelectedAgents: [String]?
    }

    private struct LockEntry: Decodable {
        var source: String
        var sourceType: String
        var sourceURL: String
        var skillPath: String
        var skillFolderHash: String?
        var installedAt: String?
        var updatedAt: String?
    }

    func loadMetadata(at url: URL = SkillSmithPaths.skillsLockURL) -> [String: SkillLockMetadata] {
        guard let data = try? Data(contentsOf: url),
              let lock = try? JSONDecoder().decode(LockFile.self, from: data) else {
            return [:]
        }

        return lock.skills.mapValues { entry in
            SkillLockMetadata(
                source: entry.source,
                sourceType: entry.sourceType,
                sourceURL: entry.sourceURL,
                skillPath: entry.skillPath,
                folderHash: entry.skillFolderHash,
                installedAt: parseDate(entry.installedAt),
                updatedAt: parseDate(entry.updatedAt)
            )
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
