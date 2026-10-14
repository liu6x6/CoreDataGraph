//
//  SVGExporter.swift
//  CoreDataGraph
//
//  Vector export: reproduces the canvas (cards, orthogonal edges, arrows,
//  labels, inheritance triangles) as a standalone SVG document.
//

import Foundation
import CoreGraphics
import SwiftUI

enum SVGExporter {

    // MARK: - Helpers

    private static func f(_ v: CGFloat) -> String {
        String(format: "%.1f", v)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func pt(_ p: CGPoint) -> String {
        "\(f(p.x)),\(f(p.y))"
    }

    /// Orthogonal polyline with rounded corners as an SVG path
    private static func roundedPath(_ pts: [CGPoint], radius: CGFloat) -> String {
        guard pts.count >= 2 else { return "" }
        var d = "M \(pt(pts[0]))"
        if pts.count == 2 {
            d += " L \(pt(pts[1]))"
            return d
        }
        for i in 1..<(pts.count - 1) {
            let prev = pts[i - 1], corner = pts[i], next = pts[i + 1]
            let r = min(radius,
                        hypot(corner.x - prev.x, corner.y - prev.y) / 2,
                        hypot(next.x - corner.x, next.y - corner.y) / 2)
            let inD = unit(from: corner, to: prev)
            let outD = unit(from: corner, to: next)
            let inPt = CGPoint(x: corner.x + inD.dx * r, y: corner.y + inD.dy * r)
            let outPt = CGPoint(x: corner.x + outD.dx * r, y: corner.y + outD.dy * r)
            d += " L \(pt(inPt)) Q \(pt(corner)) \(pt(outPt))"
        }
        d += " L \(pt(pts[pts.count - 1]))"
        return d
    }

    private static func unit(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = max(hypot(dx, dy), 0.0001)
        return CGVector(dx: dx / d, dy: dy / d)
    }

    private static func diffColorHex(_ s: DiffStatus) -> String? {
        switch s {
        case .added: return "#34A853"
        case .removed: return "#D93025"
        case .changed: return "#F29900"
        case .none: return nil
        }
    }

    // MARK: - Main

    static func string(vm: GraphViewModel) -> String {
        let settings = AppSettings.shared
        let bounds = vm.worldBounds(inset: 40)
        let w = Int(bounds.width.rounded(.up))
        let h = Int(bounds.height.rounded(.up))
        let ox = bounds.minX
        let oy = bounds.minY
        func T(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - ox, y: p.y - oy) }

        let lw = CGFloat(settings.edgeLineWidth)
        let lineHex = "#5A5A5E"
        let font = "Helvetica, Arial, sans-serif"

        var out: [String] = []
        out.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        out.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">")
        out.append("<rect x=\"0\" y=\"0\" width=\"\(w)\" height=\"\(h)\" fill=\"#FFFFFF\"/>")

        let nodesByName = Dictionary(uniqueKeysWithValues: vm.nodes.map { ($0.name, $0) })

        // MARK: Edges
        out.append("<g fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\">")
        for e in vm.edges {
            guard let a = nodesByName[e.fromEntity], let b = nodesByName[e.toEntity],
                  !e.isSelfLoop else { continue }
            let routed = GraphDrawing.route(edge: e, from: a, to: b,
                                            collapsed: vm.collapsedEntities,
                                            transform: T)
            let pts = routed.points
            let start = pts[0]
            let end = pts[pts.count - 1]

            let stroke = diffColorHex(e.diffStatus) ?? lineHex
            let width = diffColorHex(e.diffStatus) != nil ? max(lw, 2.0) : lw
            out.append("<path d=\"\(roundedPath(pts, radius: 7))\" stroke=\"\(stroke)\" stroke-width=\"\(f(width))\"/>")

            // Arrow head(s)
            let lastFrom = pts[pts.count - 2]
            let angle = atan2(end.y - lastFrom.y, end.x - lastFrom.x)
            out.append(arrowSVG(tip: end, angle: angle, isToMany: e.info.isToMany,
                                stroke: stroke, width: max(width, 1.2),
                                style: settings.arrowStyle))
            if let inv = e.info.inverseName,
               let tw = vm.edges.first(where: { $0.fromEntity == e.toEntity && $0.name == inv }) {
                let firstTo = pts[1]
                let aStart = atan2(start.y - firstTo.y, start.x - firstTo.x)
                out.append(arrowSVG(tip: start, angle: aStart, isToMany: tw.info.isToMany,
                                    stroke: stroke, width: max(width, 1.2),
                                    style: settings.arrowStyle))
            }

            // Labels
            if settings.showEdgeLabels {
                let dir: CGFloat = routed.toRight ? 1 : -1
                let tw = vm.edges.first(where: { $0.fromEntity == e.toEntity && $0.name == (e.info.inverseName ?? "") })
                let srcExt = GraphDrawing.arrowExtent(isToMany: tw?.info.isToMany ?? false, arrowStyle: settings.arrowStyle)
                let dstExt = GraphDrawing.arrowExtent(isToMany: e.info.isToMany, arrowStyle: settings.arrowStyle)
                out.append(labelSVG(text: e.name,
                                    at: CGPoint(x: start.x + dir * (srcExt + 20), y: start.y - 10),
                                    color: lineHex))
                if let inv = e.info.inverseName, !inv.isEmpty {
                    out.append(labelSVG(text: inv,
                                        at: CGPoint(x: end.x - dir * (dstExt + 20), y: end.y - 10),
                                        color: "#8E8E93"))
                }
            }
        }

        // MARK: Inheritance
        for link in vm.inheritanceLinks {
            guard let child = nodesByName[link.child], let parent = nodesByName[link.parent] else { continue }
            let pc = T(parent.position), cc = T(child.position)
            let pSize = NodeMetrics.size(for: parent, collapsed: vm.collapsedEntities.contains(parent.name))
            let cSize = NodeMetrics.size(for: child, collapsed: vm.collapsedEntities.contains(child.name))
            let start = GraphDrawing.borderPoint(center: cc, size: cSize, toward: pc)
            let end = GraphDrawing.borderPoint(center: pc, size: pSize, toward: cc)
            out.append("<path d=\"M \(pt(start)) L \(pt(end))\" stroke=\"\(lineHex)\" stroke-width=\"\(f(max(lw * 0.85, 0.8)))\"/>")
            let angle = atan2(end.y - start.y, end.x - start.x)
            let half: CGFloat = 0.30
            let size: CGFloat = 16
            let p1 = CGPoint(x: end.x - size * cos(angle - half), y: end.y - size * sin(angle - half))
            let p2 = CGPoint(x: end.x - size * cos(angle + half), y: end.y - size * sin(angle + half))
            out.append("<path d=\"M \(pt(end)) L \(pt(p1)) L \(pt(p2)) Z\" fill=\"#FFFFFF\" stroke=\"\(lineHex)\" stroke-width=\"\(f(max(lw * 0.85, 1.0)))\"/>")
        }
        out.append("</g>")

        // MARK: Nodes
        for node in vm.nodes {
            let collapsed = vm.collapsedEntities.contains(node.name)
            let extra = vm.removedRelationshipNames(of: node.name).count
            let size = NodeMetrics.size(for: node, collapsed: collapsed, extraRelRows: extra)
            let c = T(node.position)
            let x = c.x - size.width / 2
            let y = c.y - size.height / 2
            let border = diffColorHex(node.diffStatus) ?? "#B9B9BE"

            out.append("<g>")
            out.append("<rect x=\"\(f(x))\" y=\"\(f(y))\" width=\"\(f(size.width))\" height=\"\(f(size.height))\" rx=\"5\" fill=\"#FFFFFF\" stroke=\"\(border)\" stroke-width=\"1\"/>")
            // Header
            let negW = -size.width
            out.append("<path d=\"M \(f(x)) \(f(y + 5)) a 5 5 0 0 1 5 -5 h \(f(size.width - 10)) a 5 5 0 0 1 5 5 v \(f(NodeMetrics.headerHeight - 5)) h \(f(negW)) Z\" fill=\"#E9EAEC\"/>")
            out.append("<text x=\"\(f(c.x))\" y=\"\(f(y + NodeMetrics.headerHeight / 2 + 4))\" font-family=\"\(font)\" font-size=\"\(f(NodeMetrics.font(12.5)))\" font-weight=\"600\" text-anchor=\"middle\" fill=\"#1D1D1F\">\(esc(node.name))</text>")

            var cursor = y + NodeMetrics.headerHeight
            // Attributes
            if !node.attributes.isEmpty {
                cursor += NodeMetrics.sectionPad
                let shown = collapsed ? Array(node.attributes.prefix(NodeMetrics.collapsedAttrRows)) : node.attributes
                for attr in shown {
                    let ry = cursor + NodeMetrics.rowHeight / 2 + 3.5
                    if let st = vm.diffAttrStatus[node.name]?[attr.name], st != .none {
                        let col = st == .added ? "#34A853" : "#F29900"
                        out.append("<circle cx=\"\(f(x + 10))\" cy=\"\(f(ry - 3.5))\" r=\"2.5\" fill=\"\(col)\"/>")
                    }
                    out.append("<text x=\"\(f(x + 16))\" y=\"\(f(ry))\" font-family=\"\(font)\" font-size=\"\(f(NodeMetrics.font(12)))\" fill=\"#1D1D1F\">\(esc(attr.name))</text>")
                    if settings.showAttributeTypes {
                        let typeText = attr.customClassName?.isEmpty == false ? attr.customClassName! : attr.type
                        out.append("<text x=\"\(f(x + size.width - 7))\" y=\"\(f(ry))\" font-family=\"\(font)\" font-size=\"\(f(NodeMetrics.font(10)))\" fill=\"#8E8E93\" text-anchor=\"end\">\(esc(typeText))</text>")
                    }
                    cursor += NodeMetrics.rowHeight
                }
                if collapsed && node.attributes.count > NodeMetrics.collapsedAttrRows {
                    out.append("<text x=\"\(f(c.x))\" y=\"\(f(cursor + NodeMetrics.moreRowHeight / 2 + 3))\" font-family=\"\(font)\" font-size=\"\(f(NodeMetrics.font(10)))\" fill=\"#AEAEB2\" text-anchor=\"middle\">+\(node.attributes.count - NodeMetrics.collapsedAttrRows)</text>")
                    cursor += NodeMetrics.moreRowHeight
                }
                cursor += NodeMetrics.sectionPad
            }
            // Relationships
            if !node.relationships.isEmpty || extra > 0 {
                if !node.attributes.isEmpty {
                    out.append("<line x1=\"\(f(x))\" y1=\"\(f(cursor))\" x2=\"\(f(x + size.width))\" y2=\"\(f(cursor))\" stroke=\"#D1D1D6\" stroke-width=\"1\"/>")
                    cursor += 1
                }
                cursor += NodeMetrics.sectionPad
                let shown = collapsed ? Array(node.relationships.prefix(NodeMetrics.collapsedRelRows)) : node.relationships
                for rel in shown {
                    let ry = cursor + NodeMetrics.rowHeight / 2 + 3.5
                    let st = vm.diffRelStatus[node.name]?[rel.name]
                    let fill = st == .added ? "#34A853" : (st == .changed ? "#F29900" : "#1D1D1F")
                    out.append("<text x=\"\(f(x + 16))\" y=\"\(f(ry))\" font-family=\"\(font)\" font-size=\"\(f(NodeMetrics.font(12)))\" font-style=\"italic\" fill=\"\(fill)\">\(esc(rel.name))</text>")
                    out.append("<text x=\"\(f(x + size.width - 7))\" y=\"\(f(ry))\" font-family=\"\(font)\" font-size=\"\(f(NodeMetrics.font(10)))\" fill=\"#8E8E93\" text-anchor=\"end\">\(esc(rel.destinationEntity))</text>")
                    cursor += NodeMetrics.rowHeight
                }
                if collapsed && node.relationships.count > NodeMetrics.collapsedRelRows {
                    cursor += NodeMetrics.moreRowHeight
                }
                // Deleted relationships (diff mode)
                if !collapsed {
                    for name in vm.removedRelationshipNames(of: node.name) {
                        let ry = cursor + NodeMetrics.rowHeight / 2 + 3.5
                        out.append("<text x=\"\(f(x + 16))\" y=\"\(f(ry))\" font-family=\"\(font)\" font-size=\"\(f(NodeMetrics.font(12)))\" fill=\"#D93025\" text-decoration=\"line-through\">\(esc(name))</text>")
                        cursor += NodeMetrics.rowHeight
                    }
                }
            }
            out.append("</g>")
        }

        out.append("</svg>")
        return out.joined(separator: "\n")
    }

    // MARK: - Arrow fragments

    private static func arrowSVG(tip: CGPoint, angle: CGFloat, isToMany: Bool,
                                 stroke: String, width: CGFloat,
                                 style: ArrowStyle) -> String {
        var parts: [String] = []
        switch style {
        case .none:
            break
        case .hollow:
            parts.append(hollowTriangle(tip: tip, angle: angle, size: 11, stroke: stroke, width: width))
            if isToMany {
                let back = CGPoint(x: tip.x - cos(angle) * 10, y: tip.y - sin(angle) * 10)
                parts.append(hollowTriangle(tip: back, angle: angle, size: 11, stroke: stroke, width: width))
            }
        case .filled:
            parts.append(filledTriangle(tip: tip, angle: angle, size: 11, fill: stroke))
            if isToMany {
                let back = CGPoint(x: tip.x - cos(angle) * 10, y: tip.y - sin(angle) * 10)
                parts.append(filledTriangle(tip: back, angle: angle, size: 11, fill: stroke))
            }
        case .lineChevron:
            parts.append(chevron(tip: tip, angle: angle, stroke: stroke, width: max(width, 1.2)))
            if isToMany {
                let back = CGPoint(x: tip.x - cos(angle) * 8, y: tip.y - sin(angle) * 8)
                parts.append(chevron(tip: back, angle: angle, stroke: stroke, width: max(width, 1.2)))
            }
        case .crowFoot:
            if isToMany {
                parts.append(crowFoot(tip: tip, angle: angle, stroke: stroke, width: width))
            } else {
                parts.append(tick(tip: tip, angle: angle, stroke: stroke, width: width))
            }
        }
        return parts.joined()
    }

    private static func hollowTriangle(tip: CGPoint, angle: CGFloat, size: CGFloat,
                                       stroke: String, width: CGFloat) -> String {
        let p1 = CGPoint(x: tip.x - size * cos(angle - 0.42), y: tip.y - size * sin(angle - 0.42))
        let p2 = CGPoint(x: tip.x - size * cos(angle + 0.42), y: tip.y - size * sin(angle + 0.42))
        return "<path d=\"M \(pt(tip)) L \(pt(p1)) L \(pt(p2)) Z\" fill=\"#FFFFFF\" stroke=\"\(stroke)\" stroke-width=\"\(f(width))\"/>"
    }

    private static func filledTriangle(tip: CGPoint, angle: CGFloat, size: CGFloat, fill: String) -> String {
        let p1 = CGPoint(x: tip.x - size * cos(angle - 0.42), y: tip.y - size * sin(angle - 0.42))
        let p2 = CGPoint(x: tip.x - size * cos(angle + 0.42), y: tip.y - size * sin(angle + 0.42))
        return "<path d=\"M \(pt(tip)) L \(pt(p1)) L \(pt(p2)) Z\" fill=\"\(fill)\"/>"
    }

    private static func chevron(tip: CGPoint, angle: CGFloat, stroke: String, width: CGFloat) -> String {
        let len: CGFloat = 10, spread: CGFloat = 5
        let bx = tip.x - cos(angle) * len
        let by = tip.y - sin(angle) * len
        let px = -sin(angle) * spread
        let py = cos(angle) * spread
        let p1 = CGPoint(x: bx + px, y: by + py)
        let p2 = CGPoint(x: bx - px, y: by - py)
        return "<path d=\"M \(pt(p1)) L \(pt(tip)) L \(pt(p2))\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(f(width))\"/>"
    }

    private static func crowFoot(tip: CGPoint, angle: CGFloat, stroke: String, width: CGFloat) -> String {
        let back = CGPoint(x: tip.x - cos(angle) * 11, y: tip.y - sin(angle) * 11)
        let px = -sin(angle) * 5, py = cos(angle) * 5
        return "<path d=\"M \(pt(back)) L \(pt(tip)) M \(pt(back)) L \(f(tip.x + px)),\(f(tip.y + py)) M \(pt(back)) L \(f(tip.x - px)),\(f(tip.y - py))\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(f(width))\"/>"
    }

    private static func tick(tip: CGPoint, angle: CGFloat, stroke: String, width: CGFloat) -> String {
        let p = CGPoint(x: tip.x - cos(angle) * 5, y: tip.y - sin(angle) * 5)
        let px = -sin(angle) * 5, py = cos(angle) * 5
        return "<path d=\"M \(f(p.x + px)),\(f(p.y + py)) L \(f(p.x - px)),\(f(p.y - py))\" stroke=\"\(stroke)\" stroke-width=\"\(f(width))\"/>"
    }

    private static func labelSVG(text: String, at p: CGPoint, color: String) -> String {
        let size = NodeMetrics.font(10)
        let estWidth = CGFloat(text.count) * size * 0.58
        let chip = "<rect x=\"\(f(p.x - estWidth / 2 - 3))\" y=\"\(f(p.y - size / 2 - 2))\" width=\"\(f(estWidth + 6))\" height=\"\(f(size + 4))\" rx=\"3\" fill=\"#FFFFFF\" fill-opacity=\"0.88\"/>"
        let label = "<text x=\"\(f(p.x))\" y=\"\(f(p.y + size * 0.35))\" font-family=\"Helvetica, Arial, sans-serif\" font-size=\"\(f(size))\" fill=\"\(color)\" text-anchor=\"middle\">\(esc(text))</text>"
        return chip + label
    }
}
