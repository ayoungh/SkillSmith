import SwiftUI

struct SkillEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SkillSmithStore
    var skill: SkillRecord
    @State private var content: String
    @State private var showDiff = false

    init(store: SkillSmithStore, skill: SkillRecord) {
        self.store = store
        self.skill = skill
        _content = State(initialValue: store.skillMarkdown(for: skill))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit \(skill.name)")
                        .font(.title2.weight(.semibold))
                    Text(skill.source.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Diff", isOn: $showDiff)
                    .toggleStyle(.button)
                    .disabled(isSaving)
            }

            HSplitView {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(minWidth: 480)
                    .disabled(isSaving)

                if showDiff {
                    ScrollView {
                        Text(store.previewSkillMarkdownChange(for: skill, proposed: content))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minWidth: 360)
                }
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))

            if !validationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
            }

            HStack {
                Button("Revert") { content = store.skillMarkdown(for: skill) }
                    .disabled(!hasChanges || isSaving)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button {
                    Task { await store.saveSkillMarkdown(for: skill, content: content) }
                } label: {
                    ActivityButtonLabel(
                        title: "Save",
                        loadingTitle: "Saving…",
                        isLoading: isSaving
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges || !validationIssues.isEmpty || !skill.source.editable || isSaving)
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 640)
        .interactiveDismissDisabled(isSaving)
    }

    private var hasChanges: Bool {
        content != store.skillMarkdown(for: skill)
    }

    private var isSaving: Bool {
        store.isActive(.saveSkill, scope: .skill(skill.id))
    }

    private var validationIssues: [String] {
        SkillMetadataParser.validate(markdown: content)
    }
}
