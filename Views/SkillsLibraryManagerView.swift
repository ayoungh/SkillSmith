import SwiftUI

struct SkillsLibraryManagerView: View {
    @Bindable var store: SkillSmithStore
    @State private var showInspector = true
    @State private var editingSkill: SkillRecord?
    @State private var sortOrder = [KeyPathComparator(\SkillRecord.name)]

    var body: some View {
        Table(sortedSkills, selection: $store.librarySelection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \SkillRecord.name) { skill in
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .fontWeight(.medium)
                    Text(skill.description.isEmpty ? "No description" : skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 220, ideal: 300)

            TableColumn("Source", value: \SkillRecord.sourceSortValue) { skill in
                VStack(alignment: .leading, spacing: 2) {
                    Text(sourceLabel(skill.source.origin))
                    Text(skill.source.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 180, ideal: 260)

            TableColumn("Installs", value: \SkillRecord.installSortValue) { skill in
                Text("\(skill.installedTargets.filter { $0.isCanonicalSource != true }.count)")
                    .monospacedDigit()
            }
            .width(70)

            TableColumn("Status", value: \SkillRecord.statusSortValue) { skill in
                HStack(spacing: 6) {
                    if skill.hasUpdate {
                        Label("Update", systemImage: "arrow.trianglehead.clockwise")
                            .foregroundStyle(.orange)
                    } else if skill.issueCount > 0 {
                        Label("\(skill.issueCount) issue", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else {
                        Text(skill.managementState.label)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            .width(min: 110, ideal: 150)
        }
        .togglesInspectorOnRowClick(selection: $store.librarySelection, isPresented: $showInspector)
        .navigationTitle("Skills Library")
        .inspector(isPresented: $showInspector) {
            libraryInspector
                .inspectorColumnWidth(min: 310, ideal: 370, max: 480)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.createSheetPresented = true
                } label: {
                    Label("New Skill", systemImage: "plus")
                }

                Menu {
                    ForEach(store.availableRoots) { root in
                        Button(root.name) {
                            store.requestInstallSkills(store.librarySelection, into: root)
                        }
                    }
                } label: {
                    Label("Install", systemImage: "link.badge.plus")
                }
                .disabled(store.librarySelection.isEmpty)

                Button {
                    Task { await store.checkUpdatesForLibrarySelection() }
                } label: {
                    Label("Check Updates", systemImage: "arrow.trianglehead.clockwise")
                }
                .disabled(store.librarySelection.isEmpty)

                Button {
                    store.requestApplyUpdates(store.librarySelection)
                } label: {
                    Label("Apply Updates", systemImage: "arrow.down.doc")
                }
                .disabled(!store.skills.contains { store.librarySelection.contains($0.id) && $0.hasUpdate })

                Menu {
                    Button("Uninstall Everywhere", systemImage: "link.badge.minus") {
                        store.requestUninstallSkills(store.librarySelection)
                    }
                    Divider()
                    Button("Move Sources to Trash", systemImage: "trash", role: .destructive) {
                        store.requestDeleteSkills(store.librarySelection)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(store.librarySelection.isEmpty)

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .sheet(item: $editingSkill) { skill in
            SkillEditorSheet(store: store, skill: skill)
        }
        .onChange(of: store.librarySelection) {
            store.selectedSkillID = store.librarySelection.first
            if !store.librarySelection.isEmpty { showInspector = true }
        }
        .onChange(of: showInspector) {
            if !showInspector {
                store.librarySelection.removeAll()
                store.selectedSkillID = nil
            }
        }
    }

    private var sortedSkills: [SkillRecord] {
        store.filteredSkills.sorted(using: sortOrder)
    }

    @ViewBuilder
    private var libraryInspector: some View {
        if store.librarySelection.count > 1 {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("\(store.librarySelection.count) skills selected", systemImage: "checklist.checked")
                        .font(.title3.weight(.semibold))
                    Text("Use the toolbar to install, check, uninstall, or delete the selected skills as a batch.")
                        .foregroundStyle(.secondary)
                    OperationResultsView(results: store.operationResults)
                }
                .padding()
            }
        } else if let skill = store.selectedLibrarySkill {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(skill.name)
                            .font(.title2.weight(.semibold))
                        Text(skill.description.isEmpty ? skill.managementState.label : skill.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Edit SKILL.md") { editingSkill = skill }
                            .disabled(!skill.source.editable)
                        Button("Reveal") { store.reveal(path: skill.source.path) }
                    }

                    InspectorSection(title: "Source") {
                        InspectorValue(label: "Type", value: sourceLabel(skill.source.origin))
                        InspectorValue(label: "Path", value: skill.source.path)
                        InspectorValue(label: "Identity", value: skill.stableSourceIdentity)
                    }

                    InspectorSection(title: "Installed Destinations") {
                        if skill.installedTargets.isEmpty {
                            Text("Not installed in any configured agent root.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(skill.installedTargets) { install in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(install.rootName)
                                            .fontWeight(.medium)
                                        Text(install.healthLabel)
                                            .font(.caption)
                                            .foregroundStyle(install.isBroken == true ? .red : .secondary)
                                    }
                                    Spacer()
                                    if install.isCanonicalSource == true {
                                        Text("Canonical")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(.quinary, in: Capsule())
                                    } else {
                                        Button("Remove") {
                                            Task { await store.removeInstall(install, from: skill) }
                                        }
                                    }
                                }
                                Text(install.installedPath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Divider()
                        }
                    }

                    InspectorSection(title: "Management") {
                        if !skill.isManagedLibrarySource {
                            Button("Copy into SkillSmith Library") {
                                store.selectedSkillID = skill.id
                                store.adoptSelectedSkillIntoLibrary()
                            }
                        }
                        if skill.upstream == nil {
                            Button("Link Upstream Repository") {
                                store.selectedSkillID = skill.id
                                store.upstreamSheetPresented = true
                            }
                        } else {
                            Button("Check for Updates") {
                                store.selectedSkillID = skill.id
                                Task { await store.checkUpdatesForSelectedSkill() }
                            }
                        }
                        Button("Uninstall Everywhere") {
                            store.requestUninstallSkills([skill.id])
                        }
                        if skill.isManagedLibrarySource {
                            Button("Move Source to Trash", role: .destructive) {
                                store.requestDeleteSkills([skill.id])
                            }
                        }
                    }

                    if let preview = skill.updatePreview {
                        InspectorSection(title: "Latest Diff") {
                            Text(preview.summary)
                                .font(.callout)
                            Text(preview.diffText.isEmpty ? "No diff text." : preview.diffText)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(18)
                        }
                    }

                    OperationResultsView(results: store.operationResults)
                }
                .padding()
            }
        } else {
            ContentUnavailableView("Select a Skill", systemImage: "books.vertical", description: Text("Choose one or more skills to manage."))
        }
    }

    private func sourceLabel(_ origin: SkillSourceOrigin) -> String {
        switch origin {
        case .localLibrary: "SkillSmith Library"
        case .importedInstall: "Managed in Place"
        case .installedPath: "External Install"
        case .remoteInstall: "skills CLI"
        }
    }
}

struct InspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct InspectorValue: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}
