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

    /// Dock icon right-click menu: open recent models
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let items = RecentFilesStore.shared.items
        guard !items.isEmpty else { return nil }
        let menu = NSMenu(title: "最近打开")
        for item in items {
            let mi = NSMenuItem(title: item.name, action: #selector(dockOpenRecent(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = item.id.uuidString
            menu.addItem(mi)
        }
        return menu
    }

    @objc private func dockOpenRecent(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let item = RecentFilesStore.shared.items.first(where: { $0.id.uuidString == idStr }),
              let url = RecentFilesStore.shared.resolve(item) else { return }
        OpenRouter.shared.requestOpen(url)
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
            // File → Open Recent ▸ (submenu)
            CommandGroup(after: .newItem) {
                Menu("Open Recent", systemImage: "clock.arrow.circlepath") {
                    OpenRecentMenu()
                }
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

// MARK: - File → Open Recent

struct OpenRecentMenu: View {
    private var store: RecentFilesStore { RecentFilesStore.shared }

    var body: some View {
        if store.items.isEmpty {
            Text("（无最近文件）")
                .disabled(true)
        } else {
            ForEach(store.items) { item in
                Button(item.name) {
                    if let url = store.resolve(item) {
                        OpenRouter.shared.requestOpen(url)
                    }
                }
            }
            Divider()
            Button("清除菜单") {
                store.clear()
            }
        }
    }
}
