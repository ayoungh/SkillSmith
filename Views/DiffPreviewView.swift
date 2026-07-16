import SwiftUI

struct DiffPreviewView: View {
    var preview: UpdatePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusPill(text: preview.status.rawValue, color: color(for: preview.status))
                Text(preview.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !preview.changedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Changed Files")
                        .font(.headline)
                    ForEach(preview.changedFiles.prefix(8)) { file in
                        Text(file.path)
                            .font(.caption.monospaced())
                    }
                }
            }

            ScrollView {
                Text(preview.diffText.isEmpty ? "No diff text available." : preview.diffText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180)
            .padding(12)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func color(for status: UpdateStatus) -> Color {
        switch status {
        case .noChanges: .green
        case .changesAvailable: .orange
        case .deletedUpstream: .red
        case .unavailable: .secondary
        }
    }
}

private struct StatusPill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15), in: Capsule())
    }
}
