import SwiftUI
import UniformTypeIdentifiers

private enum AgentsManagerPane: String, CaseIterable, Identifiable {
    case destinations = "Destinations"
    case definitions = "Definitions"
    var id: String { rawValue }
}

private struct AgentDestinationRow: Identifiable {
    var id: AgentRoot.ID { root.id }
    var root: AgentRoot
    var skillCount: Int
    var brokenCount: Int

    var name: String { root.name }
    var scopeSortValue: String { root.scope?.rawValue ?? (root.isCustom ? "Custom" : "Personal") }
    var healthSortValue: Int {
        if !root.isAvailable { return 2 }
        return brokenCount > 0 ? 1 : 0
    }
    var path: String { root.path }
}

struct AgentsManagerView: View {
    @Bindable var store: SkillSmithStore
    @State private var pane: AgentsManagerPane = .destinations

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Agents", selection: $pane) {
                    ForEach(AgentsManagerPane.allCases) { pane in
                        Text(pane.rawValue).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            switch pane {
            case .destinations:
                AgentDestinationsView(store: store)
            case .definitions:
                AgentDefinitionsView(store: store)
            }
        }
        .navigationTitle("Agents")
    }
}

private struct AgentDestinationsView: View {
    @Bindable var store: SkillSmithStore
    @State private var selection = Set<AgentRoot.ID>()
    @State private var showInspector = true
    @State private var showAddRoot = false
    @State private var editingRoot: AgentRoot?
    @State private var showWorkspaceImporter = false
    @State private var sortOrder = [KeyPathComparator(\AgentDestinationRow.name)]

    var body: some View {
        Table(sortedRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Destination", value: \AgentDestinationRow.name) { row in
                Label(row.root.name, systemImage: row.root.platform?.systemImage ?? "folder")
                    .fontWeight(.medium)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Scope", value: \AgentDestinationRow.scopeSortValue) { row in
                Text(row.scopeSortValue)
                    .foregroundStyle(.secondary)
            }
            .width(90)

            TableColumn("Skills", value: \AgentDestinationRow.skillCount) { row in
                Text("\(row.skillCount)")
                    .monospacedDigit()
            }
            .width(65)

            TableColumn("Health", value: \AgentDestinationRow.healthSortValue) { row in
                if !row.root.isAvailable {
                    Label("Missing", systemImage: "folder.badge.questionmark")
                        .foregroundStyle(.secondary)
                } else if row.brokenCount > 0 {
                    Label("\(row.brokenCount) broken", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else {
                    Label("Ready", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("Path", value: \AgentDestinationRow.path) { row in
                Text(row.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 220, ideal: 320)
        }
        .togglesInspectorOnRowClick(selection: $selection, isPresented: $showInspector)
        .inspector(isPresented: $showInspector) {
            destinationInspector
                .inspectorColumnWidth(min: 310, ideal: 370, max: 480)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showAddRoot = true
                } label: {
                    Label("Add Root", systemImage: "folder.badge.plus")
                }
                .disabled(store.isMutationActive)
                Button {
                    showWorkspaceImporter = true
                } label: {
                    Label("Add Workspace", systemImage: "externaldrive.badge.plus")
                }
                .disabled(store.isMutationActive)
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isActive(.refresh, scope: .skills) {
                        ActivityButtonLabel(title: "Rescan", loadingTitle: "Rescanning…", isLoading: true)
                    } else {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isActive(.refresh, scope: .skills) || store.isMutationActive)
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .sheet(isPresented: $showAddRoot) {
            AddAgentRootSheet(store: store)
        }
        .sheet(item: $editingRoot) { root in
            AddAgentRootSheet(store: store, root: root)
        }
        .fileImporter(
            isPresented: $showWorkspaceImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls): urls.forEach(store.addWorkspace)
            case let .failure(error): store.errorMessage = "Could not add workspace: \(error.localizedDescription)"
            }
        }
        .onChange(of: selection) {
            store.selectedAgentRootID = selection.first
            if !selection.isEmpty { showInspector = true }
        }
        .onChange(of: showInspector) {
            if !showInspector {
                selection.removeAll()
                store.selectedAgentRootID = nil
            }
        }
        .task {
            if selection.isEmpty, let first = store.availableRoots.first { selection = [first.id] }
        }
    }

    @ViewBuilder
    private var destinationInspector: some View {
        if let root = selectedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(root.name, systemImage: root.platform?.systemImage ?? "folder")
                            .font(.title2.weight(.semibold))
                        Text(root.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack {
                        if root.isAvailable {
                            Button("Reveal") { store.reveal(path: root.path) }
                        } else {
                            Button("Create Folder") { store.createRootDirectory(root) }
                        }
                        if root.isCustom {
                            Button("Edit") { editingRoot = root }
                            Button("Remove Configuration", role: .destructive) {
                                store.removeCustomRoot(root)
                                selection.remove(root.id)
                            }
                        }
                    }

                    InspectorSection(title: "Status") {
                        InspectorValue(label: "Platform", value: root.platform?.rawValue ?? "Other")
                        InspectorValue(label: "Scope", value: root.scope?.rawValue ?? "Custom")
                        InspectorValue(label: "Installed Skills", value: "\(store.installCount(for: root))")
                        InspectorValue(label: "Symlinks", value: "\(store.symlinkInstallCount(for: root))")
                        InspectorValue(label: "Copies", value: "\(store.copyInstallCount(for: root))")
                        InspectorValue(label: "Broken Links", value: "\(store.brokenInstallCount(for: root))")
                    }

                    Menu("Install Skill Here") {
                        ForEach(store.skills.filter { FileManager.default.fileExists(atPath: $0.source.path + "/SKILL.md") }) { skill in
                            Button(skill.name) {
                                store.requestInstallSkills([skill.id], into: root)
                            }
                        }
                    }
                    .disabled(store.isMutationActive)

                    InspectorSection(title: "Installed Here") {
                        let installed = store.skills.filter { skill in
                            skill.installedTargets.contains { $0.rootID == root.id }
                        }
                        if installed.isEmpty {
                            Text("No skills found in this destination.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(installed) { skill in
                            if let install = skill.installedTargets.first(where: { $0.rootID == root.id }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(skill.name)
                                            .fontWeight(.medium)
                                        Text(install.healthLabel)
                                            .font(.caption)
                                            .foregroundStyle(install.isBroken == true ? .red : .secondary)
                                    }
                                    Spacer()
                                    if install.isCanonicalSource != true {
                                        Button {
                                            Task { await store.removeInstall(install, from: skill) }
                                        } label: {
                                            ActivityButtonLabel(
                                                title: "Remove",
                                                loadingTitle: "Removing…",
                                                isLoading: store.isActive(.remove, scope: .skill(skill.id))
                                            )
                                        }
                                        .disabled(store.isMutationActive)
                                    }
                                }
                            }
                        }
                    }

                    Button("Uninstall Everything from \(root.name)", role: .destructive) {
                        store.requestUninstallAll(from: root)
                    }
                    .disabled(store.installCount(for: root) == 0 || store.isMutationActive)

                    InspectorSection(title: "Project Workspaces") {
                        if (store.settings.workspaceRoots ?? []).isEmpty {
                            Text("Add a workspace to manage project-level agent definitions.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(store.settings.workspaceRoots ?? []) { workspace in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workspace.name)
                                    Text(workspace.path)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove") { store.removeWorkspace(workspace) }
                            }
                        }
                    }

                    OperationResultsView(results: store.operationResults)
                }
                .padding()
            }
        } else {
            ContentUnavailableView("Select a Destination", systemImage: "folder", description: Text("Inspect an agent root and its installed skills."))
        }
    }

    private var selectedRoot: AgentRoot? {
        guard let id = selection.first else { return nil }
        return store.availableRoots.first(where: { $0.id == id })
    }

    private var sortedRows: [AgentDestinationRow] {
        store.availableRoots.map { root in
            AgentDestinationRow(
                root: root,
                skillCount: store.installCount(for: root),
                brokenCount: store.brokenInstallCount(for: root)
            )
        }
        .sorted(using: sortOrder)
    }
}

private struct AgentDefinitionsView: View {
    @Bindable var store: SkillSmithStore
    @State private var selection = Set<AgentDefinition.ID>()
    @State private var showInspector = true
    @State private var showCreate = false
    @State private var showImporter = false
    @State private var editingDefinition: AgentDefinition?
    @State private var sortOrder = [KeyPathComparator(\AgentDefinition.name)]

    var body: some View {
        Table(sortedDefinitions, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \AgentDefinition.name) { definition in
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.name)
                        .fontWeight(.medium)
                    Text(definition.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 220, ideal: 300)
            TableColumn("Platform", value: \AgentDefinition.platformSortValue) { definition in
                Label(definition.platform.rawValue, systemImage: definition.platform.systemImage)
            }
            .width(min: 120, ideal: 150)
            TableColumn("Scope", value: \AgentDefinition.scopeSortValue) { definition in
                Text(definition.workspaceName ?? definition.scope.rawValue)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Status", value: \AgentDefinition.statusSortValue) { definition in
                Label(
                    definition.isValid ? "Valid" : "\(definition.validationIssues.count) issue(s)",
                    systemImage: definition.isValid ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .foregroundStyle(definition.isValid ? .green : .red)
            }
            .width(110)
        }
        .togglesInspectorOnRowClick(selection: $selection, isPresented: $showInspector)
        .inspector(isPresented: $showInspector) {
            definitionInspector
                .inspectorColumnWidth(min: 310, ideal: 370, max: 480)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showCreate = true
                } label: {
                    Label("New Agent", systemImage: "plus")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import Agent", systemImage: "square.and.arrow.down")
                }
                .disabled(store.selectedDefinitionLocation == nil)
                Button {
                    if let selectedDefinition { store.duplicateAgentDefinition(selectedDefinition) }
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .disabled(selectedDefinition?.isEditable != true)
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateAgentDefinitionSheet(store: store)
        }
        .sheet(item: $editingDefinition) { definition in
            AgentDefinitionEditorSheet(store: store, definition: definition)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText]) { result in
            switch result {
            case let .success(url):
                if let location = store.selectedDefinitionLocation {
                    store.importAgentDefinition(from: url, to: location)
                }
            case let .failure(error):
                store.errorMessage = "Could not import definition: \(error.localizedDescription)"
            }
        }
        .onChange(of: selection) {
            store.selectedAgentDefinitionID = selection.first
            if !selection.isEmpty { showInspector = true }
        }
        .onChange(of: showInspector) {
            if !showInspector {
                selection.removeAll()
                store.selectedAgentDefinitionID = nil
            }
        }
        .task {
            if selection.isEmpty, let first = store.filteredAgentDefinitions.first { selection = [first.id] }
        }
    }

    @ViewBuilder
    private var definitionInspector: some View {
        if let definition = selectedDefinition {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(definition.name, systemImage: definition.platform.systemImage)
                            .font(.title2.weight(.semibold))
                        Text(definition.description)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Edit") { editingDefinition = definition }
                            .disabled(!definition.isEditable)
                        Button("Duplicate") { store.duplicateAgentDefinition(definition) }
                            .disabled(!definition.isEditable)
                        Button("Reveal") { store.reveal(path: definition.path) }
                            .disabled(definition.path.hasPrefix("builtin://"))
                    }

                    InspectorSection(title: "Configuration") {
                        InspectorValue(label: "Platform", value: definition.platform.rawValue)
                        InspectorValue(label: "Scope", value: definition.workspaceName ?? definition.scope.rawValue)
                        InspectorValue(label: "Model", value: definition.model.isEmpty ? "Inherited" : definition.model)
                        InspectorValue(label: "Tools", value: definition.tools.isEmpty ? "Inherited" : definition.tools.joined(separator: ", "))
                        InspectorValue(label: "Path", value: definition.path)
                    }

                    if !definition.validationIssues.isEmpty {
                        InspectorSection(title: "Validation") {
                            ForEach(definition.validationIssues, id: \.self) { issue in
                                Label(issue, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    InspectorSection(title: "Instructions") {
                        Text(definition.instructions)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(24)
                    }

                    Button("Move Definition to Trash", role: .destructive) {
                        store.requestDeleteDefinition(definition)
                    }
                    .disabled(!definition.isEditable || store.isMutationActive)

                    OperationResultsView(results: store.operationResults)
                }
                .padding()
            }
        } else {
            ContentUnavailableView("Select an Agent", systemImage: "person.crop.circle.badge.gearshape", description: Text("Create or inspect a custom agent definition."))
        }
    }

    private var selectedDefinition: AgentDefinition? {
        guard let id = selection.first else { return nil }
        return store.agentDefinitions.first(where: { $0.id == id })
    }

    private var sortedDefinitions: [AgentDefinition] {
        store.filteredAgentDefinitions.sorted(using: sortOrder)
    }
}

private struct AddAgentRootSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SkillSmithStore
    @State private var name = ""
    @State private var path = ""
    @State private var platform: AgentPlatform = .other

    private let root: AgentRoot?

    init(store: SkillSmithStore, root: AgentRoot? = nil) {
        self.store = store
        self.root = root
        _name = State(initialValue: root?.name ?? "")
        _path = State(initialValue: root?.path ?? "")
        _platform = State(initialValue: root?.platform ?? .other)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(root == nil ? "Add Agent Root" : "Edit Agent Root")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $name)
                TextField("Skills directory", text: $path, prompt: Text("~/.my-agent/skills"))
                Picker("Platform", selection: $platform) {
                    ForEach(AgentPlatform.allCases) { platform in
                        Text(platform.rawValue).tag(platform)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(root == nil ? "Add" : "Save") {
                    if let root {
                        store.updateCustomRoot(root, name: name, path: path, platform: platform)
                    } else {
                        store.addCustomRoot(name: name, path: path, platform: platform)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || path.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 280)
    }
}
