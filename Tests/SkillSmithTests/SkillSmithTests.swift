import Foundation
import Testing
@testable import SkillSmithApp

struct SkillSmithTests {
    @Test
    func defaultRootsIncludeKnownAgents() {
        let roots = SkillSmithPaths.defaultAgentRoots
        #expect(roots.contains(where: { $0.path.contains(".claude/skills") }))
        #expect(roots.contains(where: { $0.path.contains(".codex/skills") }))
        #expect(roots.contains(where: { $0.path.contains(".agents/skills") }))
    }

    @Test
    func relativeSymlinkDestinationResolvesToAbsolutePath() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: base) }

        let real = base.appendingPathComponent("agents/skills/my-skill")
        let linkDir = base.appendingPathComponent("claude/skills")
        try fileManager.createDirectory(at: real, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: linkDir, withIntermediateDirectories: true)

        let link = linkDir.appendingPathComponent("my-skill")
        try fileManager.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: "../../agents/skills/my-skill"
        )

        let resolved = SkillSmithPaths.resolvedSymlinkDestination(atPath: link.path)
        #expect(resolved == real.path)
    }

    @Test
    func shellCommandHandlesOutputLargerThanPipeBuffer() async throws {
        let result = try await ShellCommandService().run(
            "/bin/zsh",
            arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' 'a'"]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 200_000)
    }

    @Test
    func scanSkipsDirectoriesWithoutSkillFile() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }

        let skill = root.appendingPathComponent("real-skill")
        let notSkill = root.appendingPathComponent("random-folder")
        try fileManager.createDirectory(at: skill, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: notSkill, withIntermediateDirectories: true)
        try "---\nname: real-skill\ndescription: A real skill\n---\n".write(
            to: skill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let scanned = AgentRootDiscoveryService().scanSkillInstallations(
            roots: [AgentRoot(id: "test", name: "Test", path: root.path, isCustom: true)]
        )
        #expect(scanned.map(\.name) == ["real-skill"])
    }

    @Test
    func skillTemplateIncludesFrontmatter() {
        let service = SkillLibraryService()
        let spec = SkillDraftSpec(
            name: "Skill Smith",
            description: "Manage skills",
            whenToUse: "Need to manage skills",
            supportedAgents: ["Codex"],
            includeAgentMetadata: true,
            includeReferencesFolder: true,
            includeScriptsFolder: false,
            includeAssetsFolder: false,
            upstreamSeed: "",
            desiredTone: "sharp"
        )

        let markdown = service.createTemplateMarkdown(for: spec)
        #expect(markdown.contains("name: skill-smith"))
        #expect(markdown.contains("description: Manage skills"))
    }
}
