//
//  EntityNodeView.swift
//  CoreDataGraph
//
//  Xcode graph-editor style entity box:
//   ┌─────────────────────┐
//   │       Recipe        │  ← gray gradient header, centered name
//   ├─────────────────────┤
//   │ id          String  │  ← attributes (name + faint type)
//   │ title       String  │
//   ├─────────────────────┤
//   │ tagsUnordered  →    │  ← relationships (click = jump to destination)
//   └─────────────────────┘
//

import SwiftUI
import AppKit

struct EntityNodeView: View {
    @Bindable var vm: GraphViewModel
    let node: EntityNode
    var interactive: Bool = true

    private var collapsed: Bool { vm.collapsedEntities.contains(node.name) }
    private var isSelected: Bool {
        vm.selectedEntity == node.name || vm.groupSelection.contains(node.name)
    }
    private var isDimmed: Bool { vm.isNodeDimmed(node) }
    private var size: CGSize { NodeMetrics.size(for: node, collapsed: collapsed) }
    private var settings: AppSettings { AppSettings.shared }
    @State private var isHovering = false

    private var borderColor: Color {
        switch node.diffStatus {
        case .added: return .green
        case .removed: return .red
        case .changed: return .orange
        case .none: return isSelected ? settings.selectedNodeColor : Color(nsColor: .separatorColor)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !node.attributes.isEmpty {
                attributeRows
            }
            if !node.relationships.isEmpty {
                divider
                relationshipRows
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(borderColor,
                              lineWidth: isSelected || node.diffStatus != .none ? 2 : 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.28 : 0.15),
                radius: isSelected ? 7 : 2.5, y: isSelected ? 2 : 1)
        .opacity(isDimmed ? 0.22 : 1)
        .animation(.easeOut(duration: 0.15), value: isDimmed)
        .allowsHitTesting(interactive)
        .onTapGesture { vm.cardTapped(node.name) }
        .onHover { isHovering = $0 }
        .contextMenu { contextMenuItems }
        .help(node.name)
    }

    // MARK: - Header (Xcode style: gray bar, centered bold name)

    private var header: some View {
        ZStack {
            LinearGradient(
                colors: isSelected
                    ? [settings.selectedNodeColor.opacity(0.9), settings.selectedNodeColor.opacity(0.72)]
                    : [Color(nsColor: .controlBackgroundColor),
                       Color(nsColor: .controlBackgroundColor).opacity(0.82)],
                startPoint: .top, endPoint: .bottom)

            HStack(spacing: 3) {
                if node.isAbstract {
                    Image(systemName: "square.on.square.dashed")
                        .font(.system(size: NodeMetrics.font(9)))
                        .foregroundStyle(.secondary)
                }
                Text(node.name)
                    .font(.system(size: NodeMetrics.font(12.5), weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if node.diffStatus != .none {
                    Text(diffBadge)
                        .font(.system(size: NodeMetrics.font(9), weight: .bold))
                        .padding(.horizontal, 3)
                        .background(borderColor.opacity(0.25), in: Capsule())
                        .foregroundStyle(isSelected ? .white : borderColor)
                }
                if node.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: NodeMetrics.font(9)))
                        .foregroundStyle(isSelected ? .white : .orange)
                }
            }
            .padding(.horizontal, 16)

            // Collapse toggle (Xcode has none; shown on hover)
            if interactive && isHovering {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { vm.toggleExpanded(node.name) }
                    } label: {
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: NodeMetrics.font(10), weight: .bold))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 2)
            }
        }
        .frame(height: NodeMetrics.headerHeight)
    }

    private var diffBadge: String {
        switch node.diffStatus {
        case .added: return "新增"
        case .removed: return "删除"
        case .changed: return "修改"
        case .none: return ""
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
    }

    // MARK: - Attribute rows

    private var attributeRows: some View {
        let shown = collapsed
            ? Array(node.attributes.prefix(NodeMetrics.collapsedAttrRows))
            : node.attributes
        return VStack(spacing: 0) {
            ForEach(shown) { attr in
                HStack(spacing: 4) {
                    Text(attr.name)
                        .font(.system(size: NodeMetrics.font(12)))
                        .foregroundStyle(.primary.opacity(attr.isOptional ? 0.85 : 1.0))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    if attr.isIndexed {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: NodeMetrics.font(8)))
                            .foregroundStyle(.blue.opacity(0.7))
                    }
                    if settings.showAttributeTypes {
                        Text(shortType(attr))
                            .font(.system(size: NodeMetrics.font(10)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(height: NodeMetrics.rowHeight)
            }
            if collapsed && node.attributes.count > NodeMetrics.collapsedAttrRows {
                moreLabel("+\(node.attributes.count - NodeMetrics.collapsedAttrRows)")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, NodeMetrics.sectionPad)
    }

    // MARK: - Relationship rows

    private var relationshipRows: some View {
        let shown = collapsed
            ? Array(node.relationships.prefix(NodeMetrics.collapsedRelRows))
            : node.relationships
        return VStack(spacing: 0) {
            ForEach(shown) { rel in
                Button {
                    vm.focusOn(entity: rel.destinationEntity)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: rel.isToMany ? "arrow.triangle.branch" : "arrow.turn.down.right")
                            .font(.system(size: NodeMetrics.font(8)))
                            .foregroundStyle(deletionColor(rel.deletionRule))
                        Text(rel.name)
                            .font(.system(size: NodeMetrics.font(12)))
                            .italic()
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 1)
                        Text(rel.destinationEntity)
                            .font(.system(size: NodeMetrics.font(10)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .frame(height: NodeMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if collapsed && node.relationships.count > NodeMetrics.collapsedRelRows {
                moreLabel("+\(node.relationships.count - NodeMetrics.collapsedRelRows)")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, NodeMetrics.sectionPad)
    }

    private func moreLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: NodeMetrics.font(10)))
            .foregroundStyle(.tertiary)
            .frame(height: NodeMetrics.moreRowHeight)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func shortType(_ attr: AttributeInfo) -> String {
        if let cls = attr.customClassName, !cls.isEmpty {
            return cls.count > 14 ? String(cls.prefix(13)) + "…" : cls
        }
        return attr.type
    }

    private func deletionColor(_ rule: String) -> Color {
        switch rule {
        case "Cascade": return .red.opacity(0.8)
        case "Deny": return .orange
        case "Nullify": return .blue.opacity(0.7)
        default: return .secondary
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .textBackgroundColor))
            switch node.diffStatus {
            case .added: RoundedRectangle(cornerRadius: 5).fill(Color.green.opacity(0.08))
            case .removed: RoundedRectangle(cornerRadius: 5).fill(Color.red.opacity(0.08))
            case .changed: RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.08))
            case .none: EmptyView()
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(collapsed ? "展开全部" : "折叠") { vm.toggleExpanded(node.name) }
        Button(node.isPinned ? "取消固定" : "固定位置") { vm.togglePin(node.name) }
        Divider()
        Button("复制名称") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.name, forType: .string)
        }
        Menu("高亮关联") {
            ForEach(Array(vm.neighborNames(of: node.name).subtracting([node.name])).sorted(), id: \.self) { name in
                Button(name) {
                    vm.focusOn(entity: name)
                }
            }
        }
    }
}
