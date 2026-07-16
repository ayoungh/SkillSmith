import AppKit
import SwiftUI

@main
struct SkillSmithApp: App {
    @State private var store = SkillSmithStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .task {
                    await store.bootstrap()
                }
        }
        .commands {
            CommandMenu("Skills") {
                Button("Refresh Skills") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r")

                Button("New Skill") {
                    store.createSheetPresented = true
                }
                .keyboardShortcut("n")

                Button("Check Updates") {
                    Task { await store.checkUpdatesForSelectedSkill() }
                }
                .keyboardShortcut("u")

                Divider()

                Button("Open Skill Folder") {
                    if let path = store.selectedSkill?.source.path, !path.isEmpty {
                        store.reveal(path: path)
                    }
                }
                .keyboardShortcut("o")
                .disabled(store.selectedSkill == nil)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
