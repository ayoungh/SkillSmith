import SwiftUI

struct AddFromSkillsShSheet: View {
    @Bindable var store: SkillSmithStore
    @State private var repo = ""
    @State private var skillNames = ""
    @State private var agentNames = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add from skills.sh")
                    .font(.title2.weight(.semibold))
                Text("Pull skills from a GitHub repository via the skills.sh CLI. Installs globally.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Repository", text: $repo, prompt: Text("vercel-labs/agent-skills"))
                TextField("Skills (optional)", text: $skillNames, prompt: Text("pr-review commit — blank for all"))
                TextField("Agents (optional)", text: $agentNames, prompt: Text("claude-code cursor — blank for all"))
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)

            if !store.skillsShRepoOutput.isEmpty {
                ScrollView {
                    Text(store.skillsShRepoOutput)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 220)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Button("List Available Skills") {
                    Task { await store.previewSkillsShRepo(trimmedRepo) }
                }
                .disabled(trimmedRepo.isEmpty || store.isBusy)

                Spacer()

                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Cancel") {
                    store.addFromSkillsShPresented = false
                    store.skillsShRepoOutput = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("Install") {
                    Task {
                        await store.addSkillsFromSkillsSh(
                            repo: trimmedRepo,
                            skillNames: tokens(from: skillNames),
                            agentNames: tokens(from: agentNames)
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedRepo.isEmpty || store.isBusy)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var trimmedRepo: String {
        repo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokens(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
    }
}
