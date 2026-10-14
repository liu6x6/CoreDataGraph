//
//  Exporter.swift
//  CoreDataGraph
//
//  Exports: PNG snapshot / Mermaid ER / Graphviz DOT
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
enum Exporter {

    // MARK: - Save panel

    static func askSaveURL(name: String, types: [UTType]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = types
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - PNG

    static func exportPNG(vm: GraphViewModel) {
        guard !vm.nodes.isEmpty else { return }
        guard let url = askSaveURL(name: "\(vm.modelName).png", types: [.png]) else { return }

        let bounds = vm.worldBounds(inset: 40)
        let snapshot = SnapshotView(vm: vm, bounds: bounds)
            .frame(width: bounds.width, height: bounds.height)

        let renderer = ImageRenderer(content: snapshot)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            vm.statusMessage = "已导出 PNG: \(url.lastPathComponent)"
        } catch {
            vm.statusMessage = "PNG 导出失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Mermaid

    static func mermaid(vm: GraphViewModel) -> String {
        var lines = ["erDiagram"]
        // Entities (so isolated entities appear too)
        for node in vm.nodes.sorted(by: { $0.name < $1.name }) {
            lines.append("    \(sanitize(node.name)) {")
            for attr in node.attributes.prefix(30) {
                let type = sanitize(attr.type.replacing(" ", with: "_"))
                lines.append("        \(type) \(sanitize(attr.name))")
            }
            lines.append("    }")
        }
        for edge in vm.edges {
            let left = edge.info.isToMany ? "||" : (edge.info.isOptional ? "|o" : "||")
            let right = edge.info.isToMany ? "o{" : (edge.info.isOptional ? "o|" : "||")
            let label = "\(edge.name) [\(edge.info.deletionRule)]"
            lines.append("    \(sanitize(edge.fromEntity)) \(left)--\(right) \(sanitize(edge.toEntity)) : \"\(label)\"")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Graphviz DOT

    static func dot(vm: GraphViewModel) -> String {
        var lines = [
            "digraph CoreDataModel {",
            "    graph [rankdir=TB, fontname=\"Helvetica\", label=\"\(vm.modelName)\", labelloc=t];",
            "    node [shape=record, fontname=\"Helvetica\", fontsize=10, style=filled, fillcolor=\"#FDFDFD\"];",
            "    edge [fontname=\"Helvetica\", fontsize=8];",
        ]
        for node in vm.nodes.sorted(by: { $0.name < $1.name }) {
            var rows = ["{\(node.name)}"]
            for attr in node.attributes {
                let opt = attr.isOptional ? "?" : ""
                rows.append("\(attr.name) : \(attr.type)\(opt)")
            }
            let label = rows.joined(separator: "\\l") + "\\l"
            let color: String
            switch node.diffStatus {
            case .added: color = ", fillcolor=\"#DDF5DD\""
            case .removed: color = ", fillcolor=\"#F8DDDD\""
            case .changed: color = ", fillcolor=\"#FDF0DD\""
            case .none: color = ""
            }
            lines.append("    \"\(node.name)\" [label=\"\(label.replacing("\"", with: "\\\""))\"\(color)];")
        }
        for edge in vm.edges {
            let many = edge.info.isToMany ? ", arrowhead=crow" : ""
            let style = edge.info.deletionRule == "Cascade" ? ", color=\"#C0392B\"" : ""
            let label = "\(edge.name) (\\(edge.info.deletionRule))"
            lines.append("    \"\(edge.fromEntity)\" -> \"\(edge.toEntity)\" [label=\"\(label)\"\(many)\(style)];")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func exportText(_ text: String, vm: GraphViewModel, ext: String, type: UTType, label: String) {
        guard let url = askSaveURL(name: "\(vm.modelName).\(ext)", types: [type, .plainText]) else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            vm.statusMessage = "已导出 \(label): \(url.lastPathComponent)"
        } catch {
            vm.statusMessage = "\(label) 导出失败: \(error.localizedDescription)"
        }
    }

    // MARK: - SVG

    static func exportSVG(vm: GraphViewModel) {
        guard !vm.nodes.isEmpty else { return }
        guard let url = askSaveURL(name: "\(vm.modelName).svg", types: [.svg, .plainText]) else { return }
        do {
            try SVGExporter.string(vm: vm).write(to: url, atomically: true, encoding: .utf8)
            vm.statusMessage = "已导出 SVG: \(url.lastPathComponent)"
        } catch {
            vm.statusMessage = "SVG 导出失败: \(error.localizedDescription)"
        }
    }

    private static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "_")
         .replacingOccurrences(of: "-", with: "_")
    }
}

// MARK: - Snapshot view for PNG export

struct SnapshotView: View {
    @Bindable var vm: GraphViewModel
    let bounds: CGRect

    var body: some View {
        let shift = CGPoint(x: -bounds.minX, y: -bounds.minY)
        let settings = AppSettings.shared
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Canvas { ctx, _ in
                GraphDrawing.draw(
                    ctx: ctx,
                    nodes: vm.nodes,
                    edges: vm.edges,
                    selectedEntity: nil,
                    matchesSearch: { _ in true },
                    collapsed: vm.collapsedEntities,
                    lineWidth: CGFloat(settings.edgeLineWidth),
                    arrowStyle: settings.arrowStyle,
                    highlightColor: settings.selectedEdgeColor,
                    inheritance: vm.inheritanceLinks,
                    transform: { p in CGPoint(x: p.x + shift.x, y: p.y + shift.y) },
                    style: .init(showLabels: settings.showEdgeLabels, dimUnrelated: false))
            }
            ForEach(vm.nodes) { node in
                EntityNodeView(vm: vm, node: node, interactive: false)
                    .position(x: node.position.x + shift.x, y: node.position.y + shift.y)
            }
        }
        .allowsHitTesting(false)
    }
}
