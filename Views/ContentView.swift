import SwiftUI

struct ContentView: View {
    @Bindable var store: SkillSmithStore
    @Environment(\.openSettings) private var openSettings
    @State private var path: [SkillRecord.ID] = []

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                SkillsHomeView(store: store) { skill in
                    store.selectedSkillID = skill.id
                    path = [skill.id]
                }
                .navigationDestination(for: SkillRecord.ID.self) { skillID in
                    if let skill = store.skills.first(where: { $0.id == skillID }) {
                        SkillDetailView(store: store, skill: skill)
                    } else {
                        ContentUnavailableView(
                            "Skill Not Found",
                            systemImage: "wand.and.stars",
                            description: Text("This skill is no longer in the library.")
                        )
                    }
                }
            }
        }
        .searchable(text: $store.searchText, placement: .toolbar)
        .sheet(isPresented: $store.createSheetPresented) {
            CreateSkillSheet(store: store)
        }
        .sheet(isPresented: $store.upstreamSheetPresented) {
            LinkUpstreamSheet(store: store)
        }
        .sheet(isPresented: $store.addFromSkillsShPresented) {
            AddFromSkillsShSheet(store: store)
        }
        .toolbar {
            ToolbarItemGroup {
                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh installed skills")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: store.selectedSection) {
            path.removeAll()
        }
        .overlay(alignment: .bottom) {
            if let message = store.errorMessage {
                BannerView(text: message, tint: .red) {
                    store.errorMessage = nil
                }
            } else if let message = store.infoMessage {
                BannerView(text: message, tint: .blue) {
                    store.infoMessage = nil
                }
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("Skills") {
                sidebarRow(.allSkills)
                sidebarRow(.installed)
                sidebarRow(.updates)
            }
            Section("Manage") {
                sidebarRow(.library)
                sidebarRow(.imports)
                sidebarRow(.agents)
            }
            Section("Config") {
                sidebarRow(.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        .navigationTitle("SkillSmith")
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        Button {
            handleSidebarSelection(section)
        } label: {
            SidebarRow(
                section: section,
                isSelected: store.selectedSection == section
            )
        }
        .buttonStyle(.plain)
    }

    private func handleSidebarSelection(_ section: SidebarSection) {
        if section == .settings {
            openSettings()
        } else {
            store.selectSection(section)
        }
    }
}

private struct SidebarRow: View {
    var section: SidebarSection
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.subheadline)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            Text(section.rawValue)
                .font(.callout)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

private struct BannerView: View {
    var text: String
    var tint: Color

    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.link)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding()
        .frame(maxWidth: 720)
    }
}
