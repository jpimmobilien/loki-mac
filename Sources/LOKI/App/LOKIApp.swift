import SwiftUI
import AppKit

@main
struct LOKIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("LOKI", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.hardware)
                .environmentObject(model.storage)
                .environmentObject(model.network)
                .environmentObject(model.library)
                .environmentObject(model.runtime)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neuer Chat") { model.newConversation() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .sidebar) {
                Button("Home") { model.tab = .home }.keyboardShortcut("1")
                Button("Chat") { model.tab = .chat }.keyboardShortcut("2")
                Button("Modelle") { model.tab = .models }.keyboardShortcut("3")
                Button("Einstellungen") { model.tab = .settings }.keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if QARunner.isRequested {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await QARunner.run(model: AppModel.shared)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.save()
        }
    }
}
