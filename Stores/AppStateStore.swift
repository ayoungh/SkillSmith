import Foundation

struct AppStateStore {
    func loadState() -> PersistedAppState {
        let defaultSettings = AppSettings(
            libraryPath: SkillSmithPaths.defaultLibraryPath,
            customAgentRoots: [],
            preferredModel: "gpt-5",
            apiKeyAccountName: "openai-api-key",
            workspaceRoots: []
        )

        guard let data = try? Data(contentsOf: SkillSmithPaths.metadataStoreURL),
              var state = try? JSONDecoder.appDecoder.decode(PersistedAppState.self, from: data) else {
            return PersistedAppState(settings: defaultSettings, skills: [])
        }

        state.schemaVersion = 2
        if state.settings.workspaceRoots == nil {
            state.settings.workspaceRoots = []
        }
        state.skills = state.skills.map { skill in
            var migrated = skill
            if migrated.sourceIdentity == nil {
                migrated.sourceIdentity = SkillSourceIdentity.pathIdentity(migrated.comparisonPath)
            }
            return migrated
        }
        return state
    }

    func saveState(_ state: PersistedAppState) throws {
        try FileManager.default.createDirectory(
            at: SkillSmithPaths.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        var versionedState = state
        versionedState.schemaVersion = 2
        let data = try JSONEncoder.pretty.encode(versionedState)
        try data.write(to: SkillSmithPaths.metadataStoreURL, options: [.atomic])
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var appDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
