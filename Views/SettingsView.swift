import SwiftUI

struct SettingsView: View {
    @Bindable var store: SkillSmithStore
    @State private var apiKey = ""
    @State private var newRootName = ""
    @State private var newRootPath = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            rootsTab
                .tabItem { Label("Agent Roots", systemImage: "person.2") }
            aiTab
                .tabItem { Label("AI", systemImage: "sparkles") }
            diagnosticsTab
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 640, height: 420)
        .scenePadding()
    }

    private var generalTab: some View {
        Form {
            TextField("Skill library path", text: $store.settings.libraryPath)
            TextField("Preferred model", text: $store.settings.preferredModel)
            Button("Save Settings") {
                store.saveSettings()
            }
        }
    }

    private var rootsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            List {
                Section("Discovered Roots") {
                    ForEach(store.availableRoots) { root in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(root.name)
                            Text(root.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Custom Roots") {
                    ForEach(store.settings.customAgentRoots) { root in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(root.name)
                            Text(root.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                TextField("Root name", text: $newRootName)
                TextField("Path", text: $newRootPath)
                Button("Add") {
                    store.settings.customAgentRoots.append(
                        AgentRoot(id: UUID().uuidString, name: newRootName, path: newRootPath, isCustom: true)
                    )
                    newRootName = ""
                    newRootPath = ""
                    store.saveSettings()
                }
                .disabled(newRootName.isEmpty || newRootPath.isEmpty)
            }
        }
    }

    private var aiTab: some View {
        Form {
            SecureField("OpenAI API Key", text: $apiKey)
            HStack {
                Button("Save API Key") {
                    store.saveAPIKey(apiKey)
                    apiKey = ""
                }
                .disabled(apiKey.isEmpty)
                Button("Clear API Key") {
                    store.clearAPIKey()
                }
            }
            Text("Draft generation is preview-first and requires an API key stored in macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var diagnosticsTab: some View {
        Form {
            LabeledContent("skills CLI", value: store.cliDiagnostics)
            Button("Re-run Discovery") {
                Task { await store.refresh() }
            }
        }
    }
}
