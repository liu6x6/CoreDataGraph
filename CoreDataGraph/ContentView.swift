//
//  ContentView.swift
//  CoreDataGraph
//
//  Self-managed 3-column layout (sidebar | canvas | inspector).
//  Both side panels toggle independently — no NavigationSplitView
//  column coupling.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var vm = GraphViewModel()
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showInspector") private var showInspector = true

    private var allowedTypes: [UTType] {
        // .xcdatamodeld/.xcdatamodel are packages (bundles), not plain folders.
        // Use .item so the panel lets the user pick anything; we validate on open.
        [.item]
    }

    var body: some View {
        @Bindable var vm = vm
        HStack(spacing: 0) {
            // MARK: Left sidebar
            if showSidebar {
                SidebarView(vm: vm)
                    .frame(width: 260)
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .transition(.move(edge: .leading))
                Divider()
            }

            // MARK: Center
            Group {
                if vm.document == nil {
                    WelcomeView(vm: vm)
                } else {
                    GraphCanvasView(vm: vm)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            // MARK: Right inspector
            if showInspector {
                Divider()
                InspectorView(vm: vm)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSidebar)
        .animation(.easeInOut(duration: 0.2), value: showInspector)
        .toolbar { toolbarContent(vm: vm) }
        .navigationTitle(vm.document == nil ? "CoreDataGraph" : vm.modelName)
        .fileImporter(isPresented: $vm.requestFileImport,
                      allowedContentTypes: allowedTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { vm.open(url: url) }
            case .failure(let error):
                vm.loadError = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            if let url = urls.first { vm.open(url: url) }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openModelNotification)) { _ in
            vm.requestFileImport = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarNotification)) { _ in
            withAnimation { showSidebar.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspectorNotification)) { _ in
            withAnimation { showInspector.toggle() }
        }
        .overlay(alignment: .bottom) {
            if let msg = vm.statusMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: msg) {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        if vm.statusMessage == msg { vm.statusMessage = nil }
                    }
            }
        }
        .task {
            // Re-open the last used model on launch
            vm.restoreLastDocument()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(vm: GraphViewModel) -> some ToolbarContent {
        // Left panel toggle — always visible
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help(showSidebar ? "隐藏左侧栏 (⌥⌘1)" : "显示左侧栏 (⌥⌘1)")
        }

        if vm.document != nil {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    vm.requestFileImport = true
                } label: {
                    Label("打开模型", systemImage: "folder.badge.plus")
                }
                .help("打开 .xcdatamodeld (⌘O)")
            }

            ToolbarItemGroup {
                // Layout picker
                Picker("布局", selection: Binding(
                    get: { vm.layoutMode },
                    set: { vm.setLayoutMode($0) })) {
                    ForEach(LayoutMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .help("切换布局算法")

                Button {
                    NotificationCenter.default.post(name: .zoomToFitNotification, object: nil)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("缩放适配 (⌘0)")

                // Compare versions
                if vm.versions.count > 1 {
                    compareMenu(vm: vm)
                }

                // Export
                Menu {
                    Button("导出 PNG…") { Exporter.exportPNG(vm: vm) }
                    Button("导出 Mermaid…") {
                        Exporter.exportText(Exporter.mermaid(vm: vm), vm: vm,
                                            ext: "mmd", type: .plainText, label: "Mermaid")
                    }
                    Button("导出 Graphviz DOT…") {
                        Exporter.exportText(Exporter.dot(vm: vm), vm: vm,
                                            ext: "dot", type: .plainText, label: "DOT")
                    }
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .help("导出图像或图表描述文本")

                // Auto refresh
                Toggle(isOn: Binding(
                    get: { vm.autoRefresh },
                    set: { vm.setAutoRefresh($0) })) {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .toggleStyle(.button)
                .help("文件变化时自动刷新（在 Xcode 保存模型后画布自动更新）")
            }

            // Right panel toggle
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(showInspector ? "隐藏检查器 (⌥⌘2)" : "显示检查器 (⌥⌘2)")
            }
        } else {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(showInspector ? "隐藏检查器 (⌥⌘2)" : "显示检查器 (⌥⌘2)")
            }
        }
    }

    @ViewBuilder
    private func compareMenu(vm: GraphViewModel) -> some View {
        Menu {
            Button {
                vm.setCompareVersion(nil)
            } label: {
                HStack {
                    Text("关闭对比")
                    if !vm.isDiffMode { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(vm.versions) { version in
                if version != vm.currentVersion {
                    Button {
                        vm.setCompareVersion(version)
                    } label: {
                        HStack {
                            Text("\(version.name) → 当前")
                            if vm.compareVersion == version { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            Label("对比", systemImage: vm.isDiffMode ? "rectangle.difference" : "rectangle.on.rectangle.angled")
                .foregroundStyle(vm.isDiffMode ? Color.orange : Color.primary)
        }
        .help("与历史版本对比（绿色=新增，红色=删除，橙色=修改）")
    }
}

extension Notification.Name {
    static let toggleSidebarNotification = Notification.Name("CoreDataGraph.toggleSidebar")
    static let toggleInspectorNotification = Notification.Name("CoreDataGraph.toggleInspector")
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
