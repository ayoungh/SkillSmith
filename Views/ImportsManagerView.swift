import SwiftUI
import UniformTypeIdentifiers

struct ImportsManagerView: View {
    @Bindable var store: SkillSmithStore
    @State private var selection = Set<ImportCandidate.ID>()
    @State private var showFileImporter = false
    @State private var repository = ""
    @State private var repositoryRef = ""
    @State private var showInspector = true
    @State private var sortOrder = [KeyPathComparator(\ImportCandidate.name)]

    var body: some View {
        VStack(spacing: 0) {
            importToolbar
            Divider()

            Table(sortedCandidates, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Skill", value: \ImportCandidate.name) { candidate in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.name)
                            .fontWeight(.medium)
                        Text(candidate.description.isEmpty ? "No description" : candidate.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .width(min: 220, ideal: 300)

                TableColumn("Source", value: \ImportCandidate.sourceKindSortValue) { candidate in
                    Text(candidate.sourceKind.rawValue)
                        .foregroundStyle(.secondary)
                }
                .width(min: 110, ideal: 140)

                TableColumn("Conflict", value: \ImportCandidate.conflictSortValue) { candidate in
                    switch candidate.conflictKind ?? .none {
                    case .none:
                        Text("None").foregroundStyle(.secondary)
                    case .sameSource:
                        Label("Already known", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    case .sameName:
                        Label("Same name", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .width(min: 100, ideal: 130)

                TableColumn("Validation", value: \ImportCandidate.validationSortValue) { candidate in
                    Label(
                        candidate.isValid ? "Ready" : "\(candidate.validationIssues.count) issue(s)",
                        systemImage: candidate.isValid ? "checkmark.circle" : "xmark.octagon"
                    )
                    .foregroundStyle(candidate.isValid ? .green : .red)
                }
                .width(110)

                TableColumn("Path", value: \ImportCandidate.sourcePath) { candidate in
                    Text(candidate.sourcePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 220, ideal: 320)
            }
            .togglesInspectorOnRowClick(selection: $selection, isPresented: $showInspector)
            .overlay {
                if store.importCandidates.isEmpty {
                    ContentUnavailableView(
                        "No Imports Queued",
                        systemImage: "tray.and.arrow.down",
                        description: Text("Choose folders, drop skills here, scan discovered installs, or load a repository.")
                    )
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                store.queueLocalImports(urls, kind: .droppedItem)
                return true
            }
            .inspector(isPresented: $showInspector) {
                importInspector
                    .inspectorColumnWidth(min: 330, ideal: 400, max: 520)
            }
        }
        .navigationTitle("Imports")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Choose Files", systemImage: "folder.badge.plus")
                }
                Button {
                    store.queueDiscoveredImports()
                } label: {
                    Label("Scan Existing", systemImage: "magnifyingglass")
                }
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.folder, .plainText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls): store.queueLocalImports(urls)
            case let .failure(error): store.errorMessage = "Could not inspect selected files: \(error.localizedDescription)"
            }
        }
        .onChange(of: selection) {
            store.selectedImportCandidateID = selection.first
            if !selection.isEmpty { showInspector = true }
            if store.selectedImportCandidate?.sourceKind == .repository {
                store.importMode = .copyToLibrary
            }
        }
        .onChange(of: showInspector) {
            if !showInspector {
                selection.removeAll()
                store.selectedImportCandidateID = nil
            }
        }
        .task {
            if selection.isEmpty, let first = store.importCandidates.first { selection = [first.id] }
        }
    }

    private var sortedCandidates: [ImportCandidate] {
        store.importCandidates.sorted(using: sortOrder)
    }

    private var importToolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .foregroundStyle(.secondary)
            TextField("GitHub owner/repo or skills.sh URL", text: $repository)
                .textFieldStyle(.roundedBorder)
            TextField("Ref (optional)", text: $repositoryRef)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
            Button("Load Repository") {
                Task { await store.loadRepositoryImports(repository, ref: repositoryRef) }
            }
            .disabled(repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy)
            if store.isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var importInspector: some View {
        if let candidate = selectedCandidate {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.name)
                            .font(.title2.weight(.semibold))
                        Text(candidate.description.isEmpty ? candidate.sourceKind.rawValue : candidate.description)
                            .foregroundStyle(.secondary)
                    }

                    InspectorSection(title: "Candidate") {
                        InspectorValue(label: "Source", value: candidate.sourceKind.rawValue)
                        InspectorValue(label: "Path", value: candidate.sourcePath)
                        if let repo = candidate.sourceRepo {
                            InspectorValue(label: "Repository", value: repo)
                            InspectorValue(label: "Repository Path", value: candidate.sourceRepoPath ?? ".")
                        }
                    }

                    if !candidate.validationIssues.isEmpty {
                        InspectorSection(title: "Validation") {
                            ForEach(candidate.validationIssues, id: \.self) { issue in
                                Label(issue, systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    InspectorSection(title: "Import Behavior") {
                        Picker("Source", selection: $store.importMode) {
                            ForEach(ImportMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .disabled(candidate.sourceKind == .repository)

                        if candidate.conflictKind == .sameName {
                            Picker("Name conflict", selection: $store.importConflictResolution) {
                                ForEach(ImportConflictResolution.allCases) { resolution in
                                    Text(resolution.rawValue).tag(resolution)
                                }
                            }
                            Text("Cancel is the safe default. Replace moves an existing library source to Trash; Keep Both creates a suffixed library folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if candidate.conflictKind == .sameSource {
                            Label("This source is already known. Import will reuse it and only add selected destinations.", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    InspectorSection(title: "Install Destinations") {
                        if store.availableRoots.isEmpty {
                            Text("No agent roots are configured.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(store.availableRoots) { root in
                            Toggle(isOn: rootSelectionBinding(root.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(root.name)
                                    Text(root.path)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    InspectorSection(title: "Operation Preview") {
                        ForEach(store.importPreview(for: candidate).steps) { step in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(step.summary, systemImage: icon(for: step.kind))
                                    .font(.callout.weight(.medium))
                                Text(step.destination.map { "\(step.path) → \($0)" } ?? step.path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Divider()
                        }
                    }

                    HStack {
                        Button("Remove from Queue") {
                            store.removeImportCandidate(candidate.id)
                            selection.remove(candidate.id)
                        }
                        Spacer()
                        Button("Import Skill") {
                            store.requestImportSelectedCandidate()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!candidate.isValid || (candidate.conflictKind == .sameName && store.importConflictResolution == .cancel) || store.isBusy)
                    }

                    OperationResultsView(results: store.operationResults)
                }
                .padding()
            }
        } else {
            ContentUnavailableView("Select an Import", systemImage: "tray.and.arrow.down", description: Text("Review validation, conflicts, destinations, and exact operations before importing."))
        }
    }

    private var selectedCandidate: ImportCandidate? {
        guard let id = selection.first else { return nil }
        return store.importCandidates.first(where: { $0.id == id })
    }

    private func rootSelectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { store.selectedImportRootIDs.contains(id) },
            set: { selected in
                if selected { store.selectedImportRootIDs.insert(id) }
                else { store.selectedImportRootIDs.remove(id) }
            }
        )
    }

    private func icon(for kind: MutationKind) -> String {
        switch kind {
        case .copy: "doc.on.doc"
        case .symlink: "link.badge.plus"
        case .unlink: "link.badge.minus"
        case .trash: "trash"
        case .write: "square.and.pencil"
        case .cli: "terminal"
        }
    }
}
