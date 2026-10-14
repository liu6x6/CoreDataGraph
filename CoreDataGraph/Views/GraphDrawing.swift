//
//  GraphDrawing.swift
//  CoreDataGraph
//
//  Faithful old-Xcode graph-editor style:
//   - ONE line per relationship pair (relationship + inverse merged)
//   - lines attach to the exact relationship ROW on each card's left/right side
//   - orthogonal (横平竖直) rounded routing
//   - arrow at destination end = relationship cardinality (to-many → double)
//   - arrow at source end = inverse relationship cardinality (to-many → double)
//   - relationship name label near source, inverse name near destination
//

import SwiftUI

enum GraphDrawing {

    struct Style {
        var showLabels: Bool = true
        var dimUnrelated: Bool = true
    }

    static func draw(ctx: GraphicsContext,
                     nodes: [EntityNode],
                     edges: [RelationshipEdge],
                     selectedEntity: String?,
                     matchesSearch: (EntityNode) -> Bool,
                     collapsed: Set<String>,
                     groupSelection: Set<String> = [],
                     lineWidth: CGFloat = 1.6,
                     arrowStyle: ArrowStyle = .hollow,
                     highlightColor: Color = .accentColor,
                     transform: (CGPoint) -> CGPoint = { $0 },
                     style: Style = Style()) {

        let nodesByName = Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, $0) })

        // MARK: 1. Deduplicate inverse pairs — Xcode draws ONE line per pair
        let idSet = Set(edges.map(\.id))
        var deduped: [RelationshipEdge] = []
        for e in edges {
            if let inv = e.info.inverseName,
               idSet.contains("\(e.toEntity).\(inv)"),
               e.id > "\(e.toEntity).\(inv)" {
                continue
            }
            deduped.append(e)
        }

        // Highlight: an edge pair lights up when either twin touches the selection
        func isEdgeHighlighted(_ e: RelationshipEdge) -> Bool {
            guard let sel = selectedEntity else { return false }
            if e.fromEntity == sel || e.toEntity == sel { return true }
            if let inv = e.info.inverseName, idSet.contains("\(e.toEntity).\(inv)") {
                return e.toEntity == sel || e.fromEntity == sel
            }
            return false
        }

        func dimmed(_ node: EntityNode) -> Bool {
            if !matchesSearch(node) { return true }
            if groupSelection.count > 1 {
                return !groupSelection.contains(node.name)
            }
            if let sel = selectedEntity {
                if node.name == sel { return false }
                return !edges.contains(where: {
                    ($0.fromEntity == sel && $0.toEntity == node.name) ||
                    ($0.toEntity == sel && $0.fromEntity == node.name)
                })
            }
            return false
        }

        let edgesBySource: [String: [RelationshipEdge]] =
            Dictionary(grouping: edges, by: { "\($0.fromEntity)" })

        func twin(of e: RelationshipEdge) -> RelationshipEdge? {
            guard let inv = e.info.inverseName else { return nil }
            return edgesBySource[e.toEntity]?.first { $0.name == inv }
        }

        // MARK: 2. Draw merged edges (row-anchored, orthogonal)
        for e in deduped {
            guard let a = nodesByName[e.fromEntity], let b = nodesByName[e.toEntity] else { continue }
            let colA = collapsed.contains(a.name)
            let colB = collapsed.contains(b.name)
            let sizeA = NodeMetrics.size(for: a, collapsed: colA)
            let sizeB = NodeMetrics.size(for: b, collapsed: colB)

            let isHi = isEdgeHighlighted(e)
            let isDim = style.dimUnrelated && (dimmed(a) || dimmed(b)) && !isHi

            var color = Color(nsColor: .secondaryLabelColor)
            var width: CGFloat = lineWidth
            if isHi {
                color = highlightColor
                width = lineWidth + 1.0
            } else if isDim {
                color = color.opacity(0.18)
                width = max(lineWidth * 0.55, 0.6)
            }
            switch e.diffStatus {
            case .added: color = .green; width = max(width, 2.2)
            case .removed: color = .red; width = max(width, 2.2)
            case .changed: color = .orange; width = max(width, 2.2)
            case .none: break
            }

            let c1 = transform(a.position)
            let c2 = transform(b.position)

            if e.isSelfLoop {
                drawSelfLoop(ctx: ctx, at: c1, size: sizeA, color: color, width: width,
                             arrowStyle: arrowStyle,
                             label: style.showLabels && !isDim ? e.name : nil)
                continue
            }

            // Ports: attach at the exact relationship row, exit left/right side
            let toRight = c2.x >= c1.x
            let offA = NodeMetrics.relRowOffset(in: a, relName: e.name, collapsed: colA)
            let offB = NodeMetrics.relRowOffset(in: b, relName: e.info.inverseName ?? "", collapsed: colB)

            let start = CGPoint(x: c1.x + (toRight ? sizeA.width / 2 + 1 : -(sizeA.width / 2 + 1)),
                                y: c1.y + offA)
            let end = CGPoint(x: c2.x + (toRight ? -(sizeB.width / 2 + 1) : sizeB.width / 2 + 1),
                              y: c2.y + offB)

            // Z route with rounded corners
            let points: [CGPoint]
            if abs(start.y - end.y) < 1 {
                points = [start, end]
            } else {
                let midX = (start.x + end.x) / 2
                points = [start,
                          CGPoint(x: midX, y: start.y),
                          CGPoint(x: midX, y: end.y),
                          end]
            }

            let path = roundedPolyline(points, radius: 7)
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

            // Destination arrow(s): cardinality of e (to-many → double)
            let lastFrom = points[points.count - 2]
            let angleEnd = atan2(end.y - lastFrom.y, end.x - lastFrom.x)
            drawArrowHead(ctx: ctx, tip: end, angle: angleEnd,
                          isToMany: e.info.isToMany, color: color,
                          width: max(width, 1.3), style: arrowStyle)

            // Source arrow(s): cardinality of the inverse (twin) relationship
            if let tw = twin(of: e) {
                let firstTo = points[1]
                let angleStart = atan2(start.y - firstTo.y, start.x - firstTo.x)
                drawArrowHead(ctx: ctx, tip: start, angle: angleStart,
                              isToMany: tw.info.isToMany, color: color,
                              width: max(width, 1.3), style: arrowStyle)
            }

            // Labels: name near source row, inverse near destination row.
            // Offset adapts to the arrow style/extent so the text chip never
            // covers the arrow heads.
            if style.showLabels && !isDim {
                let dir: CGFloat = toRight ? 1 : -1
                let tw = twin(of: e)
                let srcExtent = arrowExtent(isToMany: tw?.info.isToMany ?? false, arrowStyle: arrowStyle)
                let dstExtent = arrowExtent(isToMany: e.info.isToMany, arrowStyle: arrowStyle)

                let namePos = CGPoint(x: start.x + dir * (srcExtent + 20), y: start.y - 10)
                drawText(ctx: ctx, text: e.name, at: namePos,
                         color: isHi ? color : Color(nsColor: .secondaryLabelColor),
                         size: isHi ? 11 : 10, bold: isHi)
                if let inv = e.info.inverseName, !inv.isEmpty {
                    let invPos = CGPoint(x: end.x - dir * (dstExtent + 20), y: end.y - 10)
                    drawText(ctx: ctx, text: inv, at: invPos,
                             color: isHi ? color.opacity(0.85) : Color(nsColor: .tertiaryLabelColor),
                             size: isHi ? 11 : 10, bold: false)
                }
            }
        }
    }

    // MARK: - Arrows

    /// How far the arrow head(s) extend back from the line tip.
    static func arrowExtent(isToMany: Bool, arrowStyle: ArrowStyle) -> CGFloat {
        switch arrowStyle {
        case .none: return 2
        case .hollow, .filled: return isToMany ? 22 : 12
        case .lineChevron: return isToMany ? 20 : 11
        case .crowFoot: return isToMany ? 12 : 7
        }
    }

    /// Draws the arrow head(s) for one end of a relationship line.
    static func drawArrowHead(ctx: GraphicsContext, tip: CGPoint, angle: CGFloat,
                              isToMany: Bool, color: Color, width: CGFloat,
                              style: ArrowStyle) {
        switch style {
        case .none:
            break
        case .hollow:
            drawHollowArrow(ctx: ctx, tip: tip, angle: angle, size: 11, color: color, width: width)
            if isToMany {
                let back = CGPoint(x: tip.x - cos(angle) * 10, y: tip.y - sin(angle) * 10)
                drawHollowArrow(ctx: ctx, tip: back, angle: angle, size: 11, color: color, width: width)
            }
        case .filled:
            drawFilledArrow(ctx: ctx, tip: tip, angle: angle, size: 11, color: color)
            if isToMany {
                let back = CGPoint(x: tip.x - cos(angle) * 10, y: tip.y - sin(angle) * 10)
                drawFilledArrow(ctx: ctx, tip: back, angle: angle, size: 11, color: color)
            }
        case .crowFoot:
            if isToMany {
                drawCrowFoot(ctx: ctx, tip: tip, angle: angle, color: color, width: width)
            } else {
                drawTick(ctx: ctx, tip: tip, angle: angle, color: color, width: width)
            }
        case .lineChevron:
            drawChevron(ctx: ctx, tip: tip, angle: angle, color: color, width: width)
            if isToMany {
                let back = CGPoint(x: tip.x - cos(angle) * 8, y: tip.y - sin(angle) * 8)
                drawChevron(ctx: ctx, tip: back, angle: angle, color: color, width: width)
            }
        }
    }

    /// Open "→" style chevron: two strokes meeting at the tip
    private static func drawChevron(ctx: GraphicsContext, tip: CGPoint,
                                    angle: CGFloat, color: Color, width: CGFloat) {
        let len: CGFloat = 10
        let spread: CGFloat = 5
        let bx = tip.x - cos(angle) * len
        let by = tip.y - sin(angle) * len
        let px = -sin(angle) * spread
        let py = cos(angle) * spread
        var path = Path()
        path.move(to: CGPoint(x: bx + px, y: by + py))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: bx - px, y: by - py))
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: max(width, 1.2), lineCap: .round, lineJoin: .round))
    }

    private static func drawFilledArrow(ctx: GraphicsContext, tip: CGPoint,
                                        angle: CGFloat, size: CGFloat, color: Color) {
        let p1 = CGPoint(x: tip.x - size * cos(angle - 0.42), y: tip.y - size * sin(angle - 0.42))
        let p2 = CGPoint(x: tip.x - size * cos(angle + 0.42), y: tip.y - size * sin(angle + 0.42))
        var path = Path()
        path.move(to: tip)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    private static func drawCrowFoot(ctx: GraphicsContext, tip: CGPoint,
                                     angle: CGFloat, color: Color, width: CGFloat) {
        let back = CGPoint(x: tip.x - cos(angle) * 11, y: tip.y - sin(angle) * 11)
        let px = -sin(angle) * 5, py = cos(angle) * 5
        var path = Path()
        path.move(to: back); path.addLine(to: tip)
        path.move(to: back); path.addLine(to: CGPoint(x: tip.x + px, y: tip.y + py))
        path.move(to: back); path.addLine(to: CGPoint(x: tip.x - px, y: tip.y - py))
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func drawTick(ctx: GraphicsContext, tip: CGPoint,
                                 angle: CGFloat, color: Color, width: CGFloat) {
        let p = CGPoint(x: tip.x - cos(angle) * 5, y: tip.y - sin(angle) * 5)
        let px = -sin(angle) * 5, py = cos(angle) * 5
        var path = Path()
        path.move(to: CGPoint(x: p.x + px, y: p.y + py))
        path.addLine(to: CGPoint(x: p.x - px, y: p.y - py))
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func drawHollowArrow(ctx: GraphicsContext, tip: CGPoint,
                                        angle: CGFloat, size: CGFloat,
                                        color: Color, width: CGFloat) {
        let p1 = CGPoint(x: tip.x - size * cos(angle - 0.42), y: tip.y - size * sin(angle - 0.42))
        let p2 = CGPoint(x: tip.x - size * cos(angle + 0.42), y: tip.y - size * sin(angle + 0.42))
        var path = Path()
        path.move(to: tip)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.closeSubpath()
        ctx.fill(path, with: .color(Color(nsColor: .textBackgroundColor)))
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineJoin: .round))
    }

    // MARK: - Self loop

    private static func drawSelfLoop(ctx: GraphicsContext, at center: CGPoint,
                                     size: CGSize, color: Color, width: CGFloat,
                                     arrowStyle: ArrowStyle,
                                     label: String?) {
        let r: CGFloat = 12
        let c = CGPoint(x: center.x + size.width / 2 - 4, y: center.y - size.height / 2 - r)
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        var path = Path()
        path.addEllipse(in: rect)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
        drawArrowHead(ctx: ctx, tip: CGPoint(x: c.x, y: c.y + r), angle: .pi / 2,
                      isToMany: false, color: color, width: max(width, 1.3), style: arrowStyle)
        if let label {
            drawText(ctx: ctx, text: label, at: CGPoint(x: c.x + r + 6, y: c.y - r),
                     color: Color(nsColor: .secondaryLabelColor), size: 10, bold: false,
                     anchor: .leading)
        }
    }

    // MARK: - Text with background chip

    private static func drawText(ctx: GraphicsContext, text: String, at point: CGPoint,
                                 color: Color, size: CGFloat, bold: Bool,
                                 anchor: UnitPoint = .center) {
        let scaledSize = size * NodeMetrics.scale
        let resolved = ctx.resolve(
            Text(text)
                .font(.system(size: scaledSize, weight: bold ? .semibold : .regular))
                .foregroundColor(color))
        let textSize = resolved.measure(in: CGSize(width: 400, height: 40))
        let chipX = anchor == .leading ? point.x - 3 : point.x - textSize.width / 2 - 3
        let chip = Path(roundedRect: CGRect(x: chipX,
                                            y: point.y - textSize.height / 2 - 1,
                                            width: textSize.width + 6,
                                            height: textSize.height + 2),
                        cornerRadius: 3)
        ctx.fill(chip, with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.88)))
        ctx.draw(resolved, at: point, anchor: anchor)
    }

    // MARK: - Rounded orthogonal polyline

    static func roundedPolyline(_ pts: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        guard pts.count >= 2 else { return path }
        path.move(to: pts[0])
        if pts.count == 2 {
            path.addLine(to: pts[1])
            return path
        }
        for i in 1..<(pts.count - 1) {
            let prev = pts[i - 1], corner = pts[i], next = pts[i + 1]
            let r = min(radius,
                        hypot(corner.x - prev.x, corner.y - prev.y) / 2,
                        hypot(next.x - corner.x, next.y - corner.y) / 2)
            let inDir = unit(from: corner, to: prev)
            let outDir = unit(from: corner, to: next)
            let inPt = CGPoint(x: corner.x + inDir.dx * r, y: corner.y + inDir.dy * r)
            let outPt = CGPoint(x: corner.x + outDir.dx * r, y: corner.y + outDir.dy * r)
            path.addLine(to: inPt)
            path.addQuadCurve(to: outPt, control: corner)
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    private static func unit(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = max(hypot(dx, dy), 0.0001)
        return CGVector(dx: dx / d, dy: dy / d)
    }

    // MARK: - Geometry helpers (kept for exports / hit testing)

    static func borderPoint(center: CGPoint, size: CGSize, toward: CGPoint) -> CGPoint {
        let dx = toward.x - center.x
        let dy = toward.y - center.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return center }
        let hw = size.width / 2 + 2
        let hh = size.height / 2 + 2
        let t = min(hw / max(abs(dx), 0.0001), hh / max(abs(dy), 0.0001))
        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }
}
