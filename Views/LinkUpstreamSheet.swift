import SwiftUI

struct LinkUpstreamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SkillSmithStore

    @State private var repo = ""
    @State private var path = "."
    @State private var ref = "main"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Link Upstream")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Repository (owner/repo or URL)", text: $repo)
                TextField("Skill path inside repo", text: $path)
                TextField("Branch or ref", text: $ref)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    store.linkUpstream(repo: repo, path: path, ref: ref)
                }
                .disabled(repo.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 240)
    }
}
