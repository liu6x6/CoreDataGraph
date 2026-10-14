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
            OpenRouter.shared.activeViewModel = vm
            // Consume a URL queued by the Finder before this window existed
            if let pending = OpenRouter.shared.pendingURL {
                OpenRouter.shared.pendingURL = nil
                vm.open(url: pending)
            } else {
                // Re-open the last used model on launch
                vm.restoreLastDocument()
            }
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

                Button {
                    vm.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!vm.canUndo)
                .help("撤销位置调整 (⌘Z)")

                Button {
                    vm.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!vm.canRedo)
                .help("重做 (⇧⌘Z)")
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

                // Compare any two versions
                if vm.versions.count > 1 {
                    CompareButton(vm: vm)
                }

                // Export
                Menu {
                    Button("导出 PNG…") { Exporter.exportPNG(vm: vm) }
                    Button("导出 SVG…") { Exporter.exportSVG(vm: vm) }
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

}

// MARK: - Compare popover (pick any two versions)

struct CompareButton: View {
    @Bindable var vm: GraphViewModel
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Label("对比", systemImage: vm.isDiffMode ? "rectangle.difference" : "rectangle.on.rectangle.angled")
                .foregroundStyle(vm.isDiffMode ? Color.orange : Color.primary)
        }
        .help("任意两个版本 Diff 对比（绿=新增，红=删除，橙=修改）")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ComparePanel(vm: vm)
        }
    }
}

struct ComparePanel: View {
    @Bindable var vm: GraphViewModel
    @State private var oldSel: ModelVersion?
    @State private var newSel: ModelVersion?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("版本对比")
                .font(.system(size: 13, weight: .semibold))

            Picker("旧版本", selection: $oldSel) {
                Text("—").tag(ModelVersion?.none)
                ForEach(vm.versions) { v in
                    Text(v.name).tag(ModelVersion?.some(v))
                }
            }
            .pickerStyle(.menu)

            Picker("新版本", selection: $newSel) {
                Text("—").tag(ModelVersion?.none)
                ForEach(vm.versions) { v in
                    Text(v.name).tag(ModelVersion?.some(v))
                }
            }
            .pickerStyle(.menu)

            if let d = vm.diff {
                Text("\(d.oldVersionName) → \(d.newVersionName)：\(d.summary)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button("应用对比") {
                    vm.setCompare(old: oldSel, new: newSel)
                }
                .buttonStyle(.borderedProminent)
                .disabled(oldSel == nil || newSel == nil || oldSel == newSel)

                Button("关闭对比") {
                    vm.clearCompare()
                }
                .disabled(!vm.isDiffMode)

                Spacer()
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            oldSel = vm.compareOld
            newSel = vm.compareNew ?? vm.currentVersion
        }
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
