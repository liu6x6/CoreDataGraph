//
//  SidebarView.swift
//  CoreDataGraph
//

import SwiftUI

struct SidebarView: View {
    @Bindable var vm: GraphViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Version picker
            if vm.versions.count > 1 {
                versionSection
                Divider()
            }

            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField("搜索实体 / 属性 / 关系", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)

            Divider()

            // Entity list
            List(selection: $vm.selectedEntity) {
                if vm.isDiffMode, let diff = vm.diff {
                    Section("对比结果 (\(diff.summary))") {
                        diffSummaryRows(diff)
                    }
                }
                Section("实体 (\(vm.filteredSidebarEntities.count))") {
                    ForEach(vm.filteredSidebarEntities) { node in
                        entityRow(node)
                            .tag(node.name)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Footer stats
            Text(vm.statsLine)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        }
        .frame(minWidth: 200)
    }

    private var versionSection: some View {
        HStack {
            Text("版本")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: Binding(
                get: { vm.currentVersion?.id ?? vm.versions.first?.id },
                set: { url in
                    if let v = vm.versions.first(where: { $0.id == url }) {
                        vm.selectVersion(v)
                    }
                })) {
                ForEach(vm.versions.reversed()) { v in
                    Text(v.name + (v.isCurrent ? " ●" : "")).tag(v.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func entityRow(_ node: EntityNode) -> some View {
        HStack(spacing: 6) {
            if node.diffStatus != .none {
                Circle()
                    .fill(statusColor(node.diffStatus))
                    .frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.system(size: 12, weight: node.isAbstract ? .regular : .medium))
                    .strikethrough(node.diffStatus == .removed)
                Text("\(node.attributes.count) 属性 · \(node.relationships.count) 关系")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let parent = node.parentEntity {
                Text("⊂ \(parent)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            vm.focusOn(entity: node.name)   // fly-to: center + zoom in
        }
        .onTapGesture(count: 1) {
            vm.selectEntity(node.name)      // single click: select + highlight neighbors
        }
    }

    @ViewBuilder
    private func diffSummaryRows(_ diff: ModelDiff) -> some View {
        ForEach(diff.addedEntities, id: \.self) { name in
            diffRow(name: name, symbol: "+", color: .green)
        }
        ForEach(diff.removedEntities, id: \.self) { name in
            diffRow(name: name, symbol: "−", color: .red)
        }
        ForEach(diff.changedEntities) { change in
            diffRow(name: change.name, symbol: "~", color: .orange,
                    detail: changeDetail(change))
        }
    }

    private func diffRow(name: String, symbol: String, color: Color, detail: String? = nil) -> some View {
        Button {
            vm.focusOn(entity: name)
        } label: {
            HStack(spacing: 6) {
                Text(symbol)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 12))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .tag(name)
    }

    private func changeDetail(_ c: EntityChange) -> String {
        var parts: [String] = []
        if !c.addedAttributes.isEmpty { parts.append("+\(c.addedAttributes.count)属性") }
        if !c.removedAttributes.isEmpty { parts.append("-\(c.removedAttributes.count)属性") }
        if !c.changedAttributes.isEmpty { parts.append("~\(c.changedAttributes.count)属性") }
        if !c.addedRelationships.isEmpty { parts.append("+\(c.addedRelationships.count)关系") }
        if !c.removedRelationships.isEmpty { parts.append("-\(c.removedRelationships.count)关系") }
        if !c.changedRelationships.isEmpty { parts.append("~\(c.changedRelationships.count)关系") }
        return parts.joined(separator: " ")
    }

    private func statusColor(_ s: DiffStatus) -> Color {
        switch s {
        case .added: return .green
        case .removed: return .red
        case .changed: return .orange
        case .none: return .clear
        }
    }
}
