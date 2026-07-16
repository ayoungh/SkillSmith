import Foundation

enum SkillMetadataParser {
    static func readName(at skillPath: String) -> String {
        readFrontmatterValue("name", at: skillPath) ?? URL(fileURLWithPath: skillPath).lastPathComponent
    }

    static func readDescription(at skillPath: String) -> String {
        readFrontmatterValue("description", at: skillPath) ?? ""
    }

    static func validate(at skillPath: String) -> [String] {
        let fileURL = URL(fileURLWithPath: skillPath).appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ["SKILL.md is missing or unreadable."]
        }
        return validate(markdown: text)
    }

    static func validate(markdown text: String) -> [String] {
        var issues: [String] = []
        if readFrontmatterValue("name", in: text)?.isEmpty != false {
            issues.append("Frontmatter name is required.")
        }
        if readFrontmatterValue("description", in: text)?.isEmpty != false {
            issues.append("Frontmatter description is required.")
        }
        return issues
    }

    static func description(in markdown: String) -> String {
        readFrontmatterValue("description", in: markdown) ?? ""
    }

    static func name(in markdown: String) -> String {
        readFrontmatterValue("name", in: markdown) ?? ""
    }

    private static func readFrontmatterValue(_ key: String, at skillPath: String) -> String? {
        let fileURL = URL(fileURLWithPath: skillPath).appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        return readFrontmatterValue(key, in: text)
    }

    private static func readFrontmatterValue(_ key: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let prefix = "\(key):"
            if trimmed.hasPrefix(prefix) {
                let value = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }
}
