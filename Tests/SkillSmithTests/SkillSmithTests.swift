import Foundation
import Testing
@testable import SkillSmithApp

struct SkillSmithTests {
    private enum ExpectedFailure: Error {
        case expected
    }

    @Test
    func activityRegistryKeepsNestedAndConcurrentTokensIndependent() {
        var registry = ActivityRegistry()
        let outer = registry.begin(kind: .destructiveMutation, scope: .mutation, message: "Applying changes…")
        let refresh = registry.begin(kind: .refresh, scope: .skills, message: "Refreshing skills…")
        let secondRefresh = registry.begin(kind: .refresh, scope: .skills, message: "Refreshing again…")

        #expect(registry.isMutationActive)
        #expect(registry.isActive(kind: .refresh, scope: .skills))
        #expect(registry.message(for: .skills) == "Refreshing again…")

        registry.end(secondRefresh)
        #expect(registry.isActive(kind: .refresh, scope: .skills))
        #expect(registry.message(for: .skills) == "Refreshing skills…")

        registry.end(refresh)
        #expect(!registry.isActive(kind: .refresh, scope: .skills))
        #expect(registry.isMutationActive)

        registry.end(outer)
        #expect(!registry.isMutationActive)
    }

    @Test @MainActor
    func withActivityCleansUpAfterThrownError() async {
        let store = SkillSmithStore()

        do {
            try await store.withActivity(
                kind: .loadRepository,
                scope: .imports,
                message: "Inspecting repository…"
            ) {
                #expect(store.isActive(.loadRepository, scope: .imports))
                throw ExpectedFailure.expected
            }
        } catch ExpectedFailure.expected {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!store.isActive(.loadRepository, scope: .imports))
    }

    @Test
    func initialPlaceholderAppearsOnlyBeforeContentOrCompletion() {
        #expect(LoadingPresentation.showsInitialPlaceholder(
            hasCompletedInitialDiscovery: false,
            hasContent: false
        ))
        #expect(!LoadingPresentation.showsInitialPlaceholder(
            hasCompletedInitialDiscovery: false,
            hasContent: true
        ))
        #expect(!LoadingPresentation.showsInitialPlaceholder(
            hasCompletedInitialDiscovery: true,
            hasContent: false
        ))
    }

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

    @Test
    func legacyStateDecodesWithoutVersionedManagementFields() throws {
        let json = #"""
        {
          "settings": {
            "libraryPath": "/tmp/library",
            "customAgentRoots": [],
            "preferredModel": "gpt-5",
            "apiKeyAccountName": "key"
          },
          "skills": []
        }
        """#

        let state = try JSONDecoder().decode(PersistedAppState.self, from: Data(json.utf8))
        #expect(state.schemaVersion == nil)
        #expect(state.settings.workspaceRoots == nil)
        #expect(state.settings.enabledWorkspaces.isEmpty)
    }

    @Test
    func sourceIdentitySeparatesSameNamedSkills() {
        let first = makeSkill(name: "review", path: "/tmp/first/review")
        let second = makeSkill(name: "review", path: "/tmp/second/review")

        #expect(first.name == second.name)
        #expect(first.stableSourceIdentity != second.stableSourceIdentity)
    }

    @Test
    func lockMetadataParsesRemoteOriginIdentity() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appendingPathComponent(".skill-lock.json")
        let json = #"""
        {
          "version": 3,
          "skills": {
            "review": {
              "source": "owner/repo",
              "sourceType": "github",
              "sourceURL": "https://github.com/owner/repo.git",
              "skillPath": "skills/review",
              "skillFolderHash": "abc123",
              "installedAt": "2026-07-16T09:00:00Z",
              "updatedAt": "2026-07-16T09:30:00Z"
            }
          }
        }
        """#
        try json.write(to: lockURL, atomically: true, encoding: .utf8)

        let metadata = SkillsLockService().loadMetadata(at: lockURL)["review"]
        #expect(metadata?.source == "owner/repo")
        #expect(metadata?.folderHash == "abc123")
        #expect(metadata?.identity == "remote:owner/repo#skills/review")
    }

    @Test
    func discoveryReportsBrokenLinksAndDynamicRoots() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let skillsRoot = root.appendingPathComponent("unknown-agent/skills")
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)
        let broken = skillsRoot.appendingPathComponent("missing-skill")
        try FileManager.default.createSymbolicLink(atPath: broken.path, withDestinationPath: "../../missing/source")

        let service = AgentRootDiscoveryService()
        let dynamic = service.dynamicRoots(
            from: [CLIInstalledSkill(name: "missing-skill", path: broken.path, scope: "global", agents: ["other"])],
            excluding: []
        )
        let scanned = service.scanSkillInstallations(roots: dynamic)

        #expect(dynamic.count == 1)
        #expect(dynamic[0].path == skillsRoot.path)
        #expect(scanned.count == 1)
        #expect(scanned[0].installedSkill.isBroken == true)
    }

    @Test(arguments: [AgentPlatform.claude, .gemini])
    func markdownAgentDefinitionRoundTripPreservesUnknownFields(platform: AgentPlatform) throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("reviewer.md")
        let raw = """
        ---
        name: reviewer
        description: Reviews changes
        model: inherit
        tools:
          - Read
          - Grep
        vendor_extension: keep-me
        ---

        Review the selected files.
        """
        try raw.write(to: url, atomically: true, encoding: .utf8)

        let service = AgentDefinitionService()
        var definition = try service.parse(at: url, platform: platform, scope: .personal, workspaceName: nil, editable: true)
        definition.description = "Reviews code changes"
        let rendered = try service.renderStructured(definition)

        #expect(rendered.contains("vendor_extension: keep-me"))
        #expect(rendered.contains("Reviews code changes"))
        #expect(rendered.contains("Review the selected files."))
    }

    @Test
    func codexAgentDefinitionRoundTripPreservesUnknownFields() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("reviewer.toml")
        let raw = """
        name = "reviewer"
        description = "Reviews changes"
        developer_instructions = "Review the selected files."
        custom_setting = "keep-me"
        """
        try raw.write(to: url, atomically: true, encoding: .utf8)

        let service = AgentDefinitionService()
        var definition = try service.parse(at: url, platform: .codex, scope: .personal, workspaceName: nil, editable: true)
        definition.description = "Reviews code changes"
        let rendered = try service.renderStructured(definition)

        #expect(rendered.contains("custom_setting"))
        #expect(rendered.contains("keep-me"))
        #expect(rendered.contains("Reviews code changes"))
    }

    @Test
    func rawAgentDefinitionSavePreservesExactText() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("reviewer.md")
        let original = "---\nname: reviewer\ndescription: Reviews changes\n---\n\nOriginal prompt.\n"
        let replacement = "---\nname: reviewer\ndescription: Reviews changes\nextra: exact\n---\n\nReplacement prompt.\n"
        try original.write(to: url, atomically: true, encoding: .utf8)

        let service = AgentDefinitionService()
        let definition = try service.parse(at: url, platform: .claude, scope: .personal, workspaceName: nil, editable: true)
        try service.saveRaw(replacement, for: definition)

        #expect(try String(contentsOf: url, encoding: .utf8) == replacement)
    }

    @Test
    func importConflictDefaultsToCancelAndKeepBothDoesNotOverwrite() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("library")
        let incoming = root.appendingPathComponent("incoming/review")
        let existing = library.appendingPathComponent("review")
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try "---\nname: review\ndescription: Incoming\n---\n".write(to: incoming.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "existing".write(to: existing.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let candidate = ImportService().inspectLocal(urls: [incoming]).first!
        let settings = AppSettings(libraryPath: library.path, customAgentRoots: [], preferredModel: "gpt-5", apiKeyAccountName: "key")

        #expect(throws: Error.self) {
            try ImportService().materialize(candidate, settings: settings, mode: .copyToLibrary, resolution: .cancel)
        }
        let imported = try ImportService().materialize(candidate, settings: settings, mode: .copyToLibrary, resolution: .keepBoth)

        #expect(imported.source.path.hasSuffix("review-2"))
        #expect(try String(contentsOf: existing.appendingPathComponent("SKILL.md"), encoding: .utf8) == "existing")
    }

    @Test
    func fileOperationsRejectPathEscapes() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let allowed = root.appendingPathComponent("skills")
        let outside = root.appendingPathComponent("outside/skill")
        let agentRoot = AgentRoot(id: "test", name: "Test", path: allowed.path, isCustom: true)

        #expect(throws: Error.self) {
            try FileOperationService().validateInstallPath(outside.path, roots: [agentRoot])
        }
        #expect(throws: Error.self) {
            try FileOperationService().validateLibrarySource(outside.path, libraryPath: allowed.path)
        }
    }

    @Test
    func localGitFixtureProducesDiffFirstUpdatePreview() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        let remoteSkill = repo.appendingPathComponent("skills/review")
        let localSkill = root.appendingPathComponent("library/review")
        try FileManager.default.createDirectory(at: remoteSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localSkill, withIntermediateDirectories: true)
        try "---\nname: review\ndescription: Remote v2\n---\n".write(to: remoteSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "---\nname: review\ndescription: Local v1\n---\n".write(to: localSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let shell = ShellCommandService()
        _ = try await shell.run("/usr/bin/git", arguments: ["init", "-b", "main", repo.path])
        _ = try await shell.run("/usr/bin/git", arguments: ["-C", repo.path, "config", "user.email", "test@example.com"])
        _ = try await shell.run("/usr/bin/git", arguments: ["-C", repo.path, "config", "user.name", "SkillSmith Tests"])
        _ = try await shell.run("/usr/bin/git", arguments: ["-C", repo.path, "add", "."])
        _ = try await shell.run("/usr/bin/git", arguments: ["-C", repo.path, "commit", "-m", "fixture"])

        var skill = makeSkill(name: "review", path: localSkill.path)
        skill.upstream = SkillUpstream(
            repo: repo.path,
            path: "skills/review",
            ref: "main",
            trackedRevision: nil,
            lastKnownRemoteRevision: nil,
            deletedUpstream: false
        )
        let preview = try await GitDiffService().checkForUpdates(skill: skill)

        #expect(preview.status == .changesAvailable)
        #expect(preview.diffText.contains("Remote v2"))
        #expect(preview.diffText.contains("Local v1"))
        #expect(preview.remoteRevision != nil)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSkill(name: String, path: String) -> SkillRecord {
        SkillRecord(
            id: UUID(),
            name: name,
            description: "",
            managementState: .managedLocal,
            source: SkillSource(path: path, origin: .localLibrary, editable: true),
            installMode: .symlink,
            installedTargets: [],
            upstream: nil,
            supportedAgents: [],
            lastCheckedAt: nil,
            lastDiffSummary: nil,
            updatePreview: nil
        )
    }
}
