//
//  InspectorView.swift
//  CoreDataGraph
//

import SwiftUI

struct InspectorView: View {
    @Bindable var vm: GraphViewModel

    var body: some View {
        Group {
            if let name = vm.selectedEntity, let node = vm.node(named: name) {
                EntityInspector(vm: vm, node: node)
            } else if let diff = vm.diff, vm.isDiffMode {
                DiffInspector(diff: diff, vm: vm)
            } else {
                ModelOverviewInspector(vm: vm)
            }
        }
        .frame(width: 290)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Entity detail

struct EntityInspector: View {
    @Bindable var vm: GraphViewModel
    let node: EntityNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Title
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.system(size: 16, weight: .bold))
                        if let parent = node.parentEntity {
                            Button("继承自 \(parent)") {
                                vm.focusOn(entity: parent)
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 10))
                        }
                    }
                    Spacer()
                    Button {
                        vm.centerOn(entity: node.name)
                    } label: {
                        Image(systemName: "scope")
                    }
                    .help("在画布中定位")
                }

                if node.isAbstract {
                    Label("抽象实体", systemImage: "square.on.square.dashed")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                if let cls = node.representedClassName, cls != node.name {
                    metaRow("类名", cls)
                }
                if let modifier = node.versionHashModifier {
                    metaRow("版本修饰符", modifier)
                }
                if !node.uniquenessConstraints.isEmpty {
                    metaRow("唯一约束", node.uniquenessConstraints.map { $0.joined(separator: "+") }.joined(separator: "; "))
                }

                Divider()

                // Attributes
                SectionHeader(title: "属性", count: node.attributes.count)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(node.attributes) { attr in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(attr.name)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                Spacer()
                                Text(attr.type)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                if attr.isOptional { tag("Optional", .secondary) } else { tag("Required", .blue) }
                                if attr.isTransient { tag("Transient", .purple) }
                                if attr.isIndexed || attr.isSpotlightIndexed { tag("Indexed", .green) }
                                if let def = attr.defaultValue { tag("默认: \(def)", .orange) }
                            }
                            if let cls = attr.customClassName {
                                Text("类: \(cls)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            if let t = attr.valueTransformer {
                                Text("Transformer: \(t)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    }
                }

                // Indices
                if !node.fetchIndices.isEmpty {
                    Divider()
                    SectionHeader(title: "索引", count: node.fetchIndices.count)
                    ForEach(node.fetchIndices) { idx in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idx.name).font(.system(size: 11, weight: .medium))
                            ForEach(Array(idx.elements.enumerated()), id: \.offset) { _, el in
                                Text("· \(el.property) (\(el.order))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    }
                }

                Divider()

                // Relationships
                SectionHeader(title: "关系", count: node.relationships.count)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(node.relationships) { rel in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(rel.name)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                Spacer()
                                Button(rel.destinationEntity) {
                                    vm.focusOn(entity: rel.destinationEntity)
                                }
                                .buttonStyle(.link)
                                .font(.system(size: 10))
                            }
                            HStack(spacing: 5) {
                                tag(rel.isToMany ? "To-Many \(rel.cardinality)" : "To-One \(rel.cardinality)",
                                    rel.isToMany ? .indigo : .blue)
                                tag(rel.deletionRule, deletionColor(rel.deletionRule))
                                if let inv = rel.inverseName { tag("⇄ \(inv)", .secondary) }
                                if rel.isOrdered { tag("Ordered", .teal) }
                                if rel.isTransient { tag("Transient", .purple) }
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            .padding(12)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(value).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func deletionColor(_ rule: String) -> Color {
        switch rule {
        case "Cascade": return .red
        case "Deny": return .orange
        case "Nullify": return .blue
        default: return .secondary
        }
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .background(Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Diff detail

struct DiffInspector: View {
    let diff: ModelDiff
    @Bindable var vm: GraphViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("版本对比")
                    .font(.system(size: 14, weight: .bold))
                Text("\(diff.oldVersionName)  →  \(diff.newVersionName)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(diff.summary)
                    .font(.system(size: 11))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                if !diff.addedEntities.isEmpty {
                    Divider()
                    Text("新增实体").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                    ForEach(diff.addedEntities, id: \.self) { name in
                        entityLink(name, color: .green, symbol: "+")
                    }
                }
                if !diff.removedEntities.isEmpty {
                    Divider()
                    Text("删除实体").font(.system(size: 11, weight: .semibold)).foregroundStyle(.red)
                    ForEach(diff.removedEntities, id: \.self) { name in
                        entityLink(name, color: .red, symbol: "−")
                    }
                }
                if !diff.changedEntities.isEmpty {
                    Divider()
                    Text("修改实体").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                    ForEach(diff.changedEntities) { change in
                        VStack(alignment: .leading, spacing: 3) {
                            entityLink(change.name, color: .orange, symbol: "~")
                            ForEach(change.addedAttributes, id: \.self.name) { a in
                                changeLine("+ 属性 \(a.name): \(a.detail)", .green)
                            }
                            ForEach(change.removedAttributes, id: \.self.name) { a in
                                changeLine("− 属性 \(a.name)", .red)
                            }
                            ForEach(change.changedAttributes, id: \.self.name) { a in
                                changeLine("~ 属性 \(a.name): \(a.detail)", .orange)
                            }
                            ForEach(change.addedRelationships, id: \.self.name) { r in
                                changeLine("+ 关系 \(r.name): \(r.detail)", .green)
                            }
                            ForEach(change.removedRelationships, id: \.self.name) { r in
                                changeLine("− 关系 \(r.name)", .red)
                            }
                            ForEach(change.changedRelationships, id: \.self.name) { r in
                                changeLine("~ 关系 \(r.name): \(r.detail)", .orange)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .padding(12)
        }
    }

    private func entityLink(_ name: String, color: Color, symbol: String) -> some View {
        Button {
            vm.focusOn(entity: name)
        } label: {
            HStack(spacing: 5) {
                Text(symbol).foregroundStyle(color).font(.system(size: 11, weight: .bold, design: .monospaced))
                Text(name).font(.system(size: 11))
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func changeLine(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(color.opacity(0.9))
            .padding(.leading, 18)
            .textSelection(.enabled)
    }
}

// MARK: - Model overview

struct ModelOverviewInspector: View {
    @Bindable var vm: GraphViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("模型概览")
                    .font(.system(size: 14, weight: .bold))
                if let doc = vm.document {
                    metaRow("名称", doc.name)
                    if let v = doc.currentVersion { metaRow("当前版本", v.name) }
                    if let tools = doc.document.lastSavedToolsVersion { metaRow("Xcode 工具版本", tools) }
                    metaRow("实体", "\(doc.document.entities.count)")
                    metaRow("属性", "\(doc.document.entities.reduce(0) { $0 + $1.attributes.count })")
                    metaRow("关系", "\(doc.document.entities.reduce(0) { $0 + $1.relationships.count })")
                    metaRow("路径", doc.rootURL.path)

                    if !doc.document.configurations.isEmpty {
                        Divider()
                        Text("配置").font(.system(size: 11, weight: .semibold))
                        ForEach(doc.document.configurations) { cfg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cfg.name).font(.system(size: 11, weight: .medium))
                                Text(cfg.members.joined(separator: ", "))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if doc.versions.count > 1 {
                        Divider()
                        Text("全部版本 (\(doc.versions.count))")
                            .font(.system(size: 11, weight: .semibold))
                        Text(doc.versions.map { $0.name + ($0.isCurrent ? " ●" : "") }.joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Divider()
                Text("提示")
                    .font(.system(size: 11, weight: .semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        tip("点击实体：高亮直接关联，右侧查看详情")
                        tip("空白处拖动：框选多张卡片，拖动任意一张整组移动")
                        tip("Shift+点击卡片：加入/移出多选组")
                        tip("⌥Option+拖动空白 或 双指滚动：平移画布；捻合缩放；⌘0 适配")
                        tip("双击实体卡片：展开 / 折叠完整属性")
                        tip("拖动卡片后自动记忆排版，下次打开自动恢复")
                        tip("工具栏 Compare：与历史版本 Diff 对比")
                        tip("导出：PNG / Mermaid / Graphviz DOT")
                        tip("在 Xcode 中保存模型后本窗口自动刷新")
                    }
            }
            .padding(12)
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("·").foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }
    }
}
