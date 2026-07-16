import SwiftUI

struct CreateSkillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SkillSmithStore

    @State private var name = ""
    @State private var description = ""
    @State private var whenToUse = ""
    @State private var supportedAgents = "Codex"
    @State private var includeAgentMetadata = true
    @State private var includeReferencesFolder = true
    @State private var includeScriptsFolder = false
    @State private var includeAssetsFolder = false
    @State private var upstreamSeed = ""
    @State private var desiredTone = "clear and practical"
    @State private var useAI = true

    private var isCreating: Bool {
        store.isActive(.createSkill, scope: .createSkill)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create Skill")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $name)
                TextField("Description", text: $description)
                TextField("When to use", text: $whenToUse, axis: .vertical)
                TextField("Supported agents (comma separated)", text: $supportedAgents)
                TextField("Upstream seed (optional)", text: $upstreamSeed)
                TextField("Desired tone", text: $desiredTone)

                Toggle("Generate agents/openai.yaml", isOn: $includeAgentMetadata)
                Toggle("Create references folder", isOn: $includeReferencesFolder)
                Toggle("Create scripts folder", isOn: $includeScriptsFolder)
                Toggle("Create assets folder", isOn: $includeAssetsFolder)
                Toggle("Draft with AI first", isOn: $useAI)
            }
            .formStyle(.grouped)
            .disabled(isCreating)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isCreating)
                Button {
                    let spec = SkillDraftSpec(
                        name: name,
                        description: description,
                        whenToUse: whenToUse,
                        supportedAgents: supportedAgents.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                        includeAgentMetadata: includeAgentMetadata,
                        includeReferencesFolder: includeReferencesFolder,
                        includeScriptsFolder: includeScriptsFolder,
                        includeAssetsFolder: includeAssetsFolder,
                        upstreamSeed: upstreamSeed,
                        desiredTone: desiredTone
                    )
                    Task { await store.createSkill(spec: spec, useAI: useAI) }
                } label: {
                    ActivityButtonLabel(
                        title: "Create Skill",
                        loadingTitle: "Creating…",
                        isLoading: isCreating
                    )
                }
                .disabled(name.isEmpty || description.isEmpty || whenToUse.isEmpty || isCreating || store.isMutationActive)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .interactiveDismissDisabled(isCreating)
    }
}
