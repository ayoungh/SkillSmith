import SwiftUI

struct AgentDefinitionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SkillSmithStore
    var definition: AgentDefinition
    @State private var draft: AgentDefinition
    @State private var rawMode = false
    @State private var rawContent: String
    @State private var toolsText: String
    @State private var maxTurns: Int
    @State private var showDiff = false

    init(store: SkillSmithStore, definition: AgentDefinition) {
        self.store = store
        self.definition = definition
        _draft = State(initialValue: definition)
        _rawContent = State(initialValue: definition.rawContent)
        _toolsText = State(initialValue: definition.tools.joined(separator: ", "))
        _maxTurns = State(initialValue: definition.maxTurns ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit \(definition.name)")
                        .font(.title2.weight(.semibold))
                    Text("\(definition.platform.rawValue) · \(definition.workspaceName ?? definition.scope.rawValue)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Mode", selection: $rawMode) {
                    Text("Structured").tag(false)
                    Text("Raw").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Toggle("Diff", isOn: $showDiff)
                    .toggleStyle(.button)
            }

            HSplitView {
                Group {
                    if rawMode {
                        TextEditor(text: $rawContent)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                Form {
                                    TextField("Name", text: $draft.name)
                                    TextField("Description", text: $draft.description, axis: .vertical)
                                    TextField("Model (optional)", text: $draft.model)
                                    TextField("Tools (comma separated)", text: $toolsText)
                                    if definition.platform != .gemini {
                                        TextField(permissionLabel, text: $draft.permissionMode)
                                    }
                                    Stepper("Maximum turns: \(maxTurns == 0 ? "Inherited" : String(maxTurns))", value: $maxTurns, in: 0...200)
                                }
                                .formStyle(.grouped)

                                Text("Instructions")
                                    .font(.headline)
                                TextEditor(text: $draft.instructions)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 260)
                                    .padding(8)
                                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))

                                Text("Structured saves preserve unknown keys but may normalize formatting. Raw mode preserves the file exactly.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                    }
                }
                .frame(minWidth: 520)

                if showDiff {
                    ScrollView {
                        Text(diffText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minWidth: 360)
                }
            }

            if !validationIssues.isEmpty && !rawMode {
                ForEach(validationIssues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Button("Revert") {
                    draft = definition
                    rawContent = definition.rawContent
                    toolsText = definition.tools.joined(separator: ", ")
                    maxTurns = definition.maxTurns ?? 0
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    synchronizeDraftFields()
                    store.saveAgentDefinition(draft, rawMode: rawMode, rawContent: rawContent)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!definition.isEditable || (!rawMode && !validationIssues.isEmpty))
            }
        }
        .padding(20)
        .frame(minWidth: 920, minHeight: 680)
    }

    private var permissionLabel: String {
        definition.platform == .codex ? "Sandbox mode (optional)" : "Permission mode (optional)"
    }

    private var validationIssues: [String] {
        var candidate = draft
        candidate.tools = parsedTools
        candidate.maxTurns = maxTurns == 0 ? nil : maxTurns
        return store.validateAgentDefinition(candidate)
    }

    private var diffText: String {
        var candidate = draft
        candidate.tools = parsedTools
        candidate.maxTurns = maxTurns == 0 ? nil : maxTurns
        return store.previewAgentDefinitionChange(candidate, rawMode: rawMode, rawContent: rawContent)
    }

    private var parsedTools: [String] {
        toolsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func synchronizeDraftFields() {
        draft.tools = parsedTools
        draft.maxTurns = maxTurns == 0 ? nil : maxTurns
    }
}

struct CreateAgentDefinitionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SkillSmithStore
    @State private var name = ""
    @State private var description = ""
    @State private var instructions = ""
    @State private var locationID: AgentDefinitionLocation.ID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Agent Definition")
                .font(.title2.weight(.semibold))
            Form {
                Picker("Location", selection: $locationID) {
                    ForEach(store.definitionLocations) { location in
                        Text(location.displayName).tag(location.id)
                    }
                }
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Instructions")
                    TextEditor(text: $instructions)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    if let location = store.definitionLocations.first(where: { $0.id == locationID }) {
                        store.createAgentDefinition(name: name, description: description, instructions: instructions, location: location)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || description.isEmpty || instructions.isEmpty || locationID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .task {
            if locationID.isEmpty { locationID = store.definitionLocations.first?.id ?? "" }
        }
    }
}
