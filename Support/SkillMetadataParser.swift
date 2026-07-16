import Foundation

enum SkillMetadataParser {
    static func readDescription(at skillPath: String) -> String {
        let fileURL = URL(fileURLWithPath: skillPath).appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: fileURL) else {
            return ""
        }

        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("description:") {
                let value = trimmed.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        return ""
    }
}
