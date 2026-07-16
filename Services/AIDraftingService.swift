import Foundation

struct AIDraftingService {
    private let keychain = KeychainService()

    func draftSkill(spec: SkillDraftSpec, settings: AppSettings) async throws -> String {
        guard let key = try keychain.read(account: settings.apiKeyAccountName), !key.isEmpty else {
            throw NSError(
                domain: "SkillSmith.AIDrafting",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Add an OpenAI API key in Settings to use AI drafting."]
            )
        }

        let systemPrompt = """
        You are helping generate a concise, production-ready SKILL.md file for a reusable agent skill.
        Return markdown only.
        Include YAML frontmatter with name and description.
        Prefer concrete behavior and usage guidance over marketing language.
        """

        let userPrompt = """
        Create a skill draft with these details:
        Name: \(spec.name)
        Description: \(spec.description)
        When to use: \(spec.whenToUse)
        Supported agents: \(spec.supportedAgents.joined(separator: ", "))
        Tone: \(spec.desiredTone)
        Optional upstream seed: \(spec.upstreamSeed)
        Include references folder: \(spec.includeReferencesFolder)
        Include scripts folder: \(spec.includeScriptsFolder)
        Include assets folder: \(spec.includeAssetsFolder)
        """

        let body = ResponsesRequest(
            model: settings.preferredModel,
            input: [
                .init(role: "system", content: [.init(type: "input_text", text: systemPrompt)]),
                .init(role: "user", content: [.init(type: "input_text", text: userPrompt)])
            ]
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw NSError(domain: "SkillSmith.AIDrafting", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        if let text = decoded.outputText, !text.isEmpty {
            return text
        }

        let nestedText = decoded.output?
            .flatMap(\.content)
            .compactMap(\.text)
            .joined(separator: "\n")

        guard let nestedText, !nestedText.isEmpty else {
            throw NSError(
                domain: "SkillSmith.AIDrafting",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The API response did not include draft text."]
            )
        }

        return nestedText
    }
}

private struct ResponsesRequest: Encodable {
    var model: String
    var input: [ResponsesMessage]
}

private struct ResponsesMessage: Encodable {
    var role: String
    var content: [ResponsesInputContent]
}

private struct ResponsesInputContent: Encodable {
    var type: String
    var text: String
}

private struct ResponsesResponse: Decodable {
    var outputText: String?
    var output: [ResponsesOutputItem]?

    enum CodingKeys: String, CodingKey {
        case output
        case outputText = "output_text"
    }
}

private struct ResponsesOutputItem: Decodable {
    var content: [ResponsesOutputContent]
}

private struct ResponsesOutputContent: Decodable {
    var text: String?
}
