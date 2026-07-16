import Foundation

struct SkillLibraryService {
    func ensureLibraryExists(at path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func createSkill(from spec: SkillDraftSpec, settings: AppSettings, draftMarkdown: String?) throws -> SkillSource {
        try ensureLibraryExists(at: settings.libraryPath)

        let folderName = slugify(spec.name)
        let baseURL = URL(fileURLWithPath: settings.libraryPath)
        let folderURL = uniqueFolderURL(base: baseURL.appendingPathComponent(folderName, isDirectory: true))

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try writeSkillContents(to: folderURL, spec: spec, draftMarkdown: draftMarkdown)

        return SkillSource(path: folderURL.path, origin: .localLibrary, editable: true)
    }

    func createTemplateMarkdown(for spec: SkillDraftSpec) -> String {
        """
        ---
        name: \(slugify(spec.name))
        description: \(spec.description)
        ---

        # \(spec.name)

        Use this skill when:

        - \(spec.whenToUse)

        ## Behavior

        - Keep the tone \(spec.desiredTone.isEmpty ? "clear and practical" : spec.desiredTone).
        - Prefer concrete workflows over generic advice.
        - Support these agents when relevant: \(spec.supportedAgents.joined(separator: ", ")).
        \(spec.upstreamSeed.isEmpty ? "" : "- Consider upstream context from: \(spec.upstreamSeed)")
        """
    }

    func createAgentMetadata(for spec: SkillDraftSpec) -> String {
        let slug = slugify(spec.name)
        return """
        interface:
          display_name: \(spec.name)
          description: \(spec.description)
          default_prompt: Use the \(slug) skill to help with \(spec.whenToUse).
        """
    }

    func adoptExistingSkill(at sourcePath: String, settings: AppSettings) throws -> SkillSource {
        try ensureLibraryExists(at: settings.libraryPath)

        let folderName = URL(fileURLWithPath: sourcePath).lastPathComponent
        let baseURL = URL(fileURLWithPath: settings.libraryPath)
        let folderURL = uniqueFolderURL(base: baseURL.appendingPathComponent(folderName, isDirectory: true))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: folderURL)

        return SkillSource(path: folderURL.path, origin: .localLibrary, editable: true)
    }

    private func writeSkillContents(to folderURL: URL, spec: SkillDraftSpec, draftMarkdown: String?) throws {
        let markdown = draftMarkdown?.isEmpty == false ? draftMarkdown! : createTemplateMarkdown(for: spec)
        try markdown.write(to: folderURL.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        if spec.includeAgentMetadata {
            let agentDirectory = folderURL.appendingPathComponent("agents", isDirectory: true)
            try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
            try createAgentMetadata(for: spec).write(
                to: agentDirectory.appendingPathComponent("openai.yaml"),
                atomically: true,
                encoding: .utf8
            )
        }

        if spec.includeReferencesFolder {
            try FileManager.default.createDirectory(
                at: folderURL.appendingPathComponent("references", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        if spec.includeScriptsFolder {
            try FileManager.default.createDirectory(
                at: folderURL.appendingPathComponent("scripts", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        if spec.includeAssetsFolder {
            try FileManager.default.createDirectory(
                at: folderURL.appendingPathComponent("assets", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func uniqueFolderURL(base: URL) -> URL {
        var candidate = base
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent)-\(counter)")
            counter += 1
        }
        return candidate
    }

    private func slugify(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
