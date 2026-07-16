import SwiftUI

struct MutationConfirmationSheet: View {
    @Bindable var store: SkillSmithStore
    var preview: MutationPreview
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.title)
                        .font(.title2.weight(.semibold))
                    Text(preview.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            List(preview.steps) { step in
                VStack(alignment: .leading, spacing: 3) {
                    Label(step.summary, systemImage: icon(for: step.kind))
                        .font(.callout.weight(.medium))
                    Text(step.destination.map { "\(step.path) → \($0)" } ?? step.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 3)
            }
            .frame(minHeight: 180)

            VStack(alignment: .leading, spacing: 6) {
                Text("Type “\(preview.confirmationText)” to confirm")
                    .font(.caption.weight(.semibold))
                TextField("Confirmation", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { store.cancelPendingMutation() }
                    .keyboardShortcut(.cancelAction)
                Button("Confirm") {
                    Task { await store.confirmPendingMutation(confirmation: confirmation) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(confirmation != preview.confirmationText || store.isBusy)
            }
        }
        .padding(24)
        .frame(width: 620, height: 470)
    }

    private func icon(for kind: MutationKind) -> String {
        switch kind {
        case .copy: "doc.on.doc"
        case .symlink: "link"
        case .unlink: "link.badge.minus"
        case .trash: "trash"
        case .write: "square.and.pencil"
        case .cli: "terminal"
        }
    }
}
