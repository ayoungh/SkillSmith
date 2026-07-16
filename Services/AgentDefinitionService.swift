import Foundation
import TOMLKit
import Yams

struct AgentDefinitionService {
    private let fileOperations = FileOperationService()

    func locations(settings: AppSettings) -> [AgentDefinitionLocation] {
        var results: [AgentDefinitionLocation] = []
        for platform in [AgentPlatform.claude, .codex, .gemini] {
            if let url = SkillSmithPaths.personalAgentDefinitionDirectory(for: platform) {
                results.append(AgentDefinitionLocation(
                    platform: platform,
                    scope: .personal,
                    workspaceName: nil,
                    path: url.path
                ))
            }
        }

        for workspace in settings.enabledWorkspaces {
            for platform in [AgentPlatform.claude, .codex, .gemini] {
                guard let url = SkillSmithPaths.projectAgentDefinitionDirectory(for: platform, workspacePath: workspace.path) else { continue }
                results.append(AgentDefinitionLocation(
                    platform: platform,
                    scope: .project,
                    workspaceName: workspace.name,
                    path: url.path
                ))
            }
        }
        return results
    }

    func discover(settings: AppSettings) -> [AgentDefinition] {
        let editable = locations(settings: settings).flatMap(discover(in:))
        return (editable + discoverPluginDefinitions() + builtInDefinitions()).sorted {
            if $0.platform != $1.platform { return $0.platform.rawValue < $1.platform.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func discover(in location: AgentDefinitionLocation) -> [AgentDefinition] {
        let root = URL(fileURLWithPath: location.path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        let requiredExtension = location.platform == .codex ? "toml" : "md"
        var results: [AgentDefinition] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == requiredExtension {
            if let definition = try? parse(
                at: fileURL,
                platform: location.platform,
                scope: location.scope,
                workspaceName: location.workspaceName,
                editable: true
            ) {
                results.append(definition)
            } else {
                let raw = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                results.append(AgentDefinition(
                    name: fileURL.deletingPathExtension().lastPathComponent,
                    description: "Could not parse this definition.",
                    instructions: "",
                    platform: location.platform,
                    scope: location.scope,
                    workspaceName: location.workspaceName,
                    path: fileURL.path,
                    format: location.platform == .codex ? .toml : .markdownYAML,
                    model: "",
                    tools: [],
                    permissionMode: "",
                    maxTurns: nil,
                    rawContent: raw,
                    validationIssues: ["The file is not valid \(location.platform == .codex ? "TOML" : "Markdown/YAML")."],
                    isEditable: true
                ))
            }
        }
        return results
    }

    func parse(
        at url: URL,
        platform: AgentPlatform,
        scope: ResourceScope,
        workspaceName: String?,
        editable: Bool
    ) throws -> AgentDefinition {
        let raw = try String(contentsOf: url, encoding: .utf8)
        switch platform {
        case .codex:
            return try parseTOML(raw, path: url.path, scope: scope, workspaceName: workspaceName, editable: editable)
        case .claude, .gemini:
            return try parseMarkdownYAML(raw, path: url.path, platform: platform, scope: scope, workspaceName: workspaceName, editable: editable)
        case .cursor, .shared, .other:
            throw definitionError("This agent format is read-only.")
        }
    }

    func renderStructured(_ definition: AgentDefinition) throws -> String {
        switch definition.platform {
        case .codex:
            let table = try TOMLTable(string: definition.rawContent.isEmpty ? defaultTOML(for: definition) : definition.rawContent)
            table["name"] = definition.name
            table["description"] = definition.description
            table["developer_instructions"] = definition.instructions
            if definition.model.isEmpty {
                table.remove(at: "model")
            } else {
                table["model"] = definition.model
            }
            if definition.permissionMode.isEmpty {
                table.remove(at: "sandbox_mode")
            } else {
                table["sandbox_mode"] = definition.permissionMode
            }
            return table.convert(to: .toml)

        case .claude, .gemini:
            let split = try splitFrontmatter(definition.rawContent.isEmpty ? defaultMarkdown(for: definition) : definition.rawContent)
            var metadata = (try Yams.load(yaml: split.yaml) as? [String: Any]) ?? [:]
            metadata["name"] = definition.name
            metadata["description"] = definition.description
            if definition.tools.isEmpty { metadata.removeValue(forKey: "tools") }
            else { metadata["tools"] = definition.tools }
            if definition.model.isEmpty { metadata.removeValue(forKey: "model") }
            else { metadata["model"] = definition.model }

            if definition.platform == .claude {
                if definition.permissionMode.isEmpty { metadata.removeValue(forKey: "permissionMode") }
                else { metadata["permissionMode"] = definition.permissionMode }
                if let maxTurns = definition.maxTurns { metadata["maxTurns"] = maxTurns }
                else { metadata.removeValue(forKey: "maxTurns") }
            } else {
                if let maxTurns = definition.maxTurns { metadata["max_turns"] = maxTurns }
                else { metadata.removeValue(forKey: "max_turns") }
            }

            let yaml = try Yams.dump(object: metadata).trimmingCharacters(in: .whitespacesAndNewlines)
            return "---\n\(yaml)\n---\n\n\(definition.instructions.trimmingCharacters(in: .whitespacesAndNewlines))\n"

        case .cursor, .shared, .other:
            throw definitionError("This agent format is read-only.")
        }
    }

    func validate(_ definition: AgentDefinition) -> [String] {
        var issues: [String] = []
        if definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Name is required.")
        }
        if definition.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Description is required.")
        }
        if definition.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(definition.platform == .codex ? "Developer instructions are required." : "The system prompt is required.")
        }
        let validName: String
        switch definition.platform {
        case .claude: validName = "^[a-z0-9-]+$"
        case .gemini: validName = "^[a-z0-9_-]+$"
        case .codex: validName = "^[A-Za-z0-9_-]+$"
        case .cursor, .shared, .other: validName = ".+"
        }
        if definition.name.range(of: validName, options: .regularExpression) == nil {
            issues.append("The name contains characters unsupported by \(definition.platform.rawValue).")
        }
        return issues
    }

    func saveRaw(_ content: String, for definition: AgentDefinition) throws {
        _ = try parseRaw(content, basedOn: definition)
        try fileOperations.writeAtomically(content, to: URL(fileURLWithPath: definition.path))
    }

    func saveStructured(_ definition: AgentDefinition) throws {
        let issues = validate(definition)
        guard issues.isEmpty else { throw definitionError(issues.joined(separator: " ")) }
        let rendered = try renderStructured(definition)
        try fileOperations.writeAtomically(rendered, to: URL(fileURLWithPath: definition.path))
    }

    func create(
        name: String,
        description: String,
        instructions: String,
        at location: AgentDefinitionLocation
    ) throws -> AgentDefinition {
        let slug = slugify(name)
        let fileExtension = location.platform == .codex ? "toml" : "md"
        let url = URL(fileURLWithPath: location.path, isDirectory: true).appendingPathComponent("\(slug).\(fileExtension)")
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw definitionError("An agent definition already exists at \(url.path).")
        }

        let base = AgentDefinition(
            name: slug,
            description: description,
            instructions: instructions,
            platform: location.platform,
            scope: location.scope,
            workspaceName: location.workspaceName,
            path: url.path,
            format: location.platform == .codex ? .toml : .markdownYAML,
            model: "",
            tools: [],
            permissionMode: "",
            maxTurns: nil,
            rawContent: "",
            validationIssues: [],
            isEditable: true
        )
        try saveStructured(base)
        return try parse(at: url, platform: location.platform, scope: location.scope, workspaceName: location.workspaceName, editable: true)
    }

    func duplicate(_ definition: AgentDefinition) throws -> AgentDefinition {
        guard definition.isEditable else {
            throw definitionError("Built-in and plugin agent definitions are read-only.")
        }
        let originalURL = URL(fileURLWithPath: definition.path)
        var counter = 2
        var candidate = originalURL.deletingLastPathComponent().appendingPathComponent("\(originalURL.deletingPathExtension().lastPathComponent)-copy.\(originalURL.pathExtension)")
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = originalURL.deletingLastPathComponent().appendingPathComponent("\(originalURL.deletingPathExtension().lastPathComponent)-copy-\(counter).\(originalURL.pathExtension)")
            counter += 1
        }
        var copy = definition
        copy.path = candidate.path
        copy.name = slugify(definition.name + "-copy")
        copy.rawContent = try renderStructured(copy)
        try fileOperations.writeAtomically(copy.rawContent, to: candidate)
        return try parse(at: candidate, platform: definition.platform, scope: definition.scope, workspaceName: definition.workspaceName, editable: true)
    }

    func importDefinition(from sourceURL: URL, to location: AgentDefinitionLocation) throws -> AgentDefinition {
        let parsed = try parse(at: sourceURL, platform: location.platform, scope: location.scope, workspaceName: location.workspaceName, editable: true)
        let fileExtension = location.platform == .codex ? "toml" : "md"
        let destination = URL(fileURLWithPath: location.path, isDirectory: true).appendingPathComponent("\(slugify(parsed.name)).\(fileExtension)")
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw definitionError("A definition named \(parsed.name) already exists in \(location.displayName).")
        }
        try fileOperations.writeAtomically(parsed.rawContent, to: destination)
        return try parse(at: destination, platform: location.platform, scope: location.scope, workspaceName: location.workspaceName, editable: true)
    }

    func delete(_ definition: AgentDefinition) throws {
        guard definition.isEditable else { throw definitionError("This definition is read-only.") }
        try fileOperations.moveToTrash(URL(fileURLWithPath: definition.path))
    }

    private func parseRaw(_ content: String, basedOn definition: AgentDefinition) throws -> AgentDefinition {
        let temporaryURL = URL(fileURLWithPath: definition.path)
        switch definition.platform {
        case .codex:
            return try parseTOML(content, path: temporaryURL.path, scope: definition.scope, workspaceName: definition.workspaceName, editable: definition.isEditable)
        case .claude, .gemini:
            return try parseMarkdownYAML(content, path: temporaryURL.path, platform: definition.platform, scope: definition.scope, workspaceName: definition.workspaceName, editable: definition.isEditable)
        case .cursor, .shared, .other:
            throw definitionError("This agent format is read-only.")
        }
    }

    private func discoverPluginDefinitions() -> [AgentDefinition] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [(URL, AgentPlatform)] = [
            (home.appendingPathComponent(".claude/plugins/cache", isDirectory: true), .claude),
            (home.appendingPathComponent(".codex/plugins/cache", isDirectory: true), .codex)
        ]
        var definitions: [AgentDefinition] = []
        var seen = Set<String>()

        for (root, platform) in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "md",
                      url.pathComponents.contains("agents"),
                      !url.lastPathComponent.hasSuffix(".md.tmpl") else { continue }
                let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                guard let parsed = try? parseMarkdownYAML(
                    raw,
                    path: url.path,
                    platform: platform,
                    scope: .external,
                    workspaceName: "Plugin",
                    editable: false
                ) else { continue }
                let key = "\(platform.rawValue)::\(parsed.name)::\(raw.hashValue)"
                if seen.insert(key).inserted { definitions.append(parsed) }
            }
        }
        return definitions
    }

    private func builtInDefinitions() -> [AgentDefinition] {
        let values: [(AgentPlatform, String, String)] = [
            (.claude, "Explore", "Built-in read-only codebase exploration agent."),
            (.claude, "Plan", "Built-in research agent used while planning."),
            (.claude, "general-purpose", "Built-in agent for complex multi-step work."),
            (.codex, "default", "Built-in general-purpose fallback agent."),
            (.codex, "worker", "Built-in execution-focused agent."),
            (.codex, "explorer", "Built-in read-heavy codebase exploration agent.")
        ]
        return values.map { platform, name, description in
            AgentDefinition(
                name: name,
                description: description,
                instructions: "Managed by \(platform.rawValue).",
                platform: platform,
                scope: .external,
                workspaceName: "Built-in",
                path: "builtin://\(platform.rawValue)/\(name)",
                format: platform == .codex ? .toml : .markdownYAML,
                model: "",
                tools: [],
                permissionMode: "",
                maxTurns: nil,
                rawContent: "",
                validationIssues: [],
                isEditable: false
            )
        }
    }

    private func parseMarkdownYAML(
        _ raw: String,
        path: String,
        platform: AgentPlatform,
        scope: ResourceScope,
        workspaceName: String?,
        editable: Bool
    ) throws -> AgentDefinition {
        let split = try splitFrontmatter(raw)
        guard let metadata = try Yams.load(yaml: split.yaml) as? [String: Any] else {
            throw definitionError("The YAML frontmatter is not a mapping.")
        }
        let tools: [String]
        if let values = metadata["tools"] as? [String] {
            tools = values
        } else if let value = metadata["tools"] as? String {
            tools = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } else {
            tools = []
        }
        let maxTurnsKey = platform == .claude ? "maxTurns" : "max_turns"
        var definition = AgentDefinition(
            name: metadata["name"] as? String ?? "",
            description: metadata["description"] as? String ?? "",
            instructions: split.body.trimmingCharacters(in: .whitespacesAndNewlines),
            platform: platform,
            scope: scope,
            workspaceName: workspaceName,
            path: path,
            format: .markdownYAML,
            model: metadata["model"] as? String ?? "",
            tools: tools,
            permissionMode: metadata["permissionMode"] as? String ?? "",
            maxTurns: metadata[maxTurnsKey] as? Int,
            rawContent: raw,
            validationIssues: [],
            isEditable: editable
        )
        definition.validationIssues = validate(definition)
        return definition
    }

    private func parseTOML(
        _ raw: String,
        path: String,
        scope: ResourceScope,
        workspaceName: String?,
        editable: Bool
    ) throws -> AgentDefinition {
        let table = try TOMLTable(string: raw)
        var definition = AgentDefinition(
            name: table["name"]?.string ?? "",
            description: table["description"]?.string ?? "",
            instructions: table["developer_instructions"]?.string ?? "",
            platform: .codex,
            scope: scope,
            workspaceName: workspaceName,
            path: path,
            format: .toml,
            model: table["model"]?.string ?? "",
            tools: [],
            permissionMode: table["sandbox_mode"]?.string ?? "",
            maxTurns: nil,
            rawContent: raw,
            validationIssues: [],
            isEditable: editable
        )
        definition.validationIssues = validate(definition)
        return definition
    }

    private func splitFrontmatter(_ raw: String) throws -> (yaml: String, body: String) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n"),
              let closingRange = normalized.range(of: "\n---", range: normalized.index(normalized.startIndex, offsetBy: 4)..<normalized.endIndex) else {
            throw definitionError("Markdown agent definitions must start with YAML frontmatter.")
        }
        let yamlStart = normalized.index(normalized.startIndex, offsetBy: 4)
        let yaml = String(normalized[yamlStart..<closingRange.lowerBound])
        var bodyStart = closingRange.upperBound
        if bodyStart < normalized.endIndex, normalized[bodyStart] == "\n" {
            bodyStart = normalized.index(after: bodyStart)
        }
        return (yaml, String(normalized[bodyStart...]))
    }

    private func defaultMarkdown(for definition: AgentDefinition) -> String {
        "---\nname: \(definition.name)\ndescription: \(definition.description)\n---\n\n\(definition.instructions)\n"
    }

    private func defaultTOML(for definition: AgentDefinition) -> String {
        "name = \"\(definition.name)\"\ndescription = \"\(definition.description)\"\ndeveloper_instructions = \"\"\"\n\(definition.instructions)\n\"\"\"\n"
    }

    private func slugify(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }

    private func definitionError(_ message: String) -> NSError {
        NSError(domain: "SkillSmith.AgentDefinitions", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
