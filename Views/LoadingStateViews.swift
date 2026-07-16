import SwiftUI

struct InlineLoadingLabel: View {
    var message: String

    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct ActivityButtonLabel: View {
    var title: String
    var loadingTitle: String
    var isLoading: Bool

    var body: some View {
        HStack(spacing: 7) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(isLoading ? loadingTitle : title)
        }
        .accessibilityLabel(isLoading ? loadingTitle : title)
    }
}

struct SkillsLoadingPlaceholder: View {
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InlineLoadingLabel(message: "Discovering skills…")
                .padding(.bottom, 4)

            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 14) {
                    Image(systemName: "bolt.fill")
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(index.isMultiple(of: 2) ? "Example skill name" : "Skill name")
                            .font(.callout.weight(.semibold))
                        Text("Skill description and source information")
                            .font(.caption)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .redacted(reason: .placeholder)
        .overlay(alignment: .topLeading) {
            InlineLoadingLabel(message: "Discovering skills…")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(title)")
    }
}
