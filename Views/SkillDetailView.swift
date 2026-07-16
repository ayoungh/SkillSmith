import SwiftUI

struct SkillDetailView: View {
    @Bindable var store: SkillSmithStore
    var skill: SkillRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                sourceCard
                installsCard
                skillFileCard
                upstreamCard
                diffCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(skill.name)
    }

    private var headerCard: some View {
        DetailCard(title: skill.name, subtitle: skill.description.isEmpty ? skill.managementState.label : skill.description) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StatusPill(text: skill.managementState.label, color: skill.hasUpdate ? .orange : .accentColor)
                    if let summary = skill.lastDiffSummary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button("Open Source") {
                        store.open(path: skill.source.path)
                    }
                    .disabled(skill.source.path.isEmpty)

                    Button("Reveal Source") {
                        store.reveal(path: skill.source.path)
                    }
                    .disabled(skill.source.path.isEmpty)

                    if skill.managementState == .externalImportable {
                        Button("Import Into SkillSmith") {
                            store.importSelectedSkill()
                        }
                    }

                    if skill.managementState != .managedLocal {
                        Button("Adopt Into Library") {
                            store.adoptSelectedSkillIntoLibrary()
                        }
                    }
                }
            }
        }
    }

    private var sourceCard: some View {
        DetailCard(title: "Source", subtitle: "Canonical source library or current install location") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Origin", value: skill.source.origin.rawValue)
                LabeledContent("Path", value: skill.source.path)
                LabeledContent("Editable", value: skill.source.editable ? "Yes" : "No")
                LabeledContent("Install Mode", value: skill.installMode.rawValue.capitalized)
            }
            .textSelection(.enabled)
        }
    }

    private var installsCard: some View {
        DetailCard(title: "Installed Targets", subtitle: "Symlink and copy installs across agent roots") {
            VStack(alignment: .leading, spacing: 10) {
                if skill.installedTargets.isEmpty {
                    Text("Not currently installed anywhere.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(skill.installedTargets) { install in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(install.rootName)
                                    .font(.headline)
                                Text(install.installedPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let destination = install.symlinkDestination {
                                    Text("→ \(destination)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Remove") {
                                Task { await store.removeInstall(install, from: skill) }
                            }
                        }
                        Divider()
                    }
                }

                if !store.availableRoots.isEmpty {
                    Menu("Install to Root") {
                        ForEach(store.availableRoots) { root in
                            Button(root.name) {
                                Task { await store.installSelectedSkill(into: root) }
                            }
                        }
                    }
                    .disabled(skill.source.path.isEmpty)
                }
            }
        }
    }

    private var skillFileCard: some View {
        DetailCard(title: "SKILL.md", subtitle: "The skill's instructions as stored on disk") {
            SkillFileView(skillPath: skill.comparisonPath)
        }
    }

    private var upstreamCard: some View {
        DetailCard(title: "Upstream Tracking", subtitle: "Preview diffs before any update is applied") {
            VStack(alignment: .leading, spacing: 10) {
                if let upstream = skill.upstream {
                    LabeledContent("Repo", value: upstream.repo)
                    LabeledContent("Path", value: upstream.path)
                    LabeledContent("Ref", value: upstream.ref)
                    LabeledContent("Tracked Revision", value: upstream.trackedRevision ?? "Not recorded")
                    LabeledContent("Remote Revision", value: upstream.lastKnownRemoteRevision ?? "Not checked")
                    if upstream.deletedUpstream {
                        Text("Upstream path appears to be deleted.")
                            .foregroundStyle(.orange)
                    }

                    HStack(spacing: 10) {
                        Button("Check for Updates") {
                            Task { await store.checkUpdatesForSelectedSkill() }
                        }
                        Button("Apply Update") {
                            Task { await store.applyUpdateForSelectedSkill() }
                        }
                    }
                } else {
                    Text("No upstream linked yet.")
                        .foregroundStyle(.secondary)
                    Button("Link Upstream") {
                        store.upstreamSheetPresented = true
                    }
                }
            }
        }
    }

    private var diffCard: some View {
        DetailCard(title: "Diff Preview", subtitle: "Current preview from the latest update check") {
            if let preview = skill.updatePreview {
                DiffPreviewView(preview: preview)
            } else {
                Text("No diff preview yet. Link an upstream source and run an update check.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SkillFileView: View {
    var skillPath: String
    @State private var content: String?
    @State private var isExpanded = false

    private static let collapsedLineLimit = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let content, !content.isEmpty {
                Text(displayedText(from: content))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if lineCount(of: content) > Self.collapsedLineLimit {
                    Button(isExpanded ? "Show Less" : "Show Full File") {
                        isExpanded.toggle()
                    }
                    .buttonStyle(.link)
                }
            } else {
                Text("No SKILL.md found at this skill's source path.")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: skillPath) {
            isExpanded = false
            let url = URL(fileURLWithPath: skillPath).appendingPathComponent("SKILL.md")
            content = try? String(contentsOf: url, encoding: .utf8)
        }
    }

    private func lineCount(of text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private func displayedText(from text: String) -> String {
        guard !isExpanded else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > Self.collapsedLineLimit else { return text }
        return lines.prefix(Self.collapsedLineLimit).joined(separator: "\n") + "\n…"
    }
}

private struct DetailCard<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LabeledContent: View {
    var title: String
    var value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
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
