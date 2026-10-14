//
//  CoreDataGraphApp.swift
//  CoreDataGraph
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Finder double-click / `open -a CoreDataGraph model.xcdatamodeld`
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            OpenRouter.shared.requestOpen(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct CoreDataGraphApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Apply persisted font scale before any layout runs
        AppSettings.shared.applyMetrics()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            // Replace "New" with "Open Model"
            CommandGroup(replacing: .newItem) {
                Button("打开模型…") {
                    NotificationCenter.default.post(name: .openModelNotification, object: nil)
                }
                .keyboardShortcut("o")
            }
            // Undo / redo of card positions
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") {
                    OpenRouter.shared.activeViewModel?.undo()
                }
                .keyboardShortcut("z")

                Button("重做") {
                    OpenRouter.shared.activeViewModel?.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("视图") {
                Button("显示/隐藏左侧栏") {
                    NotificationCenter.default.post(name: .toggleSidebarNotification, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("显示/隐藏检查器") {
                    NotificationCenter.default.post(name: .toggleInspectorNotification, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])
            }
            CommandMenu("图") {
                Button("缩放适配") {
                    NotificationCenter.default.post(name: .zoomToFitNotification, object: nil)
                }
                .keyboardShortcut("0")

                Button("重新布局") {
                    NotificationCenter.default.post(name: .relayoutNotification, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let openModelNotification = Notification.Name("CoreDataGraph.openModel")
}
