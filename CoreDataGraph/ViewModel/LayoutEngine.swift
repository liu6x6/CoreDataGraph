//
//  LayoutEngine.swift
//  CoreDataGraph
//
//  Two-phase auto layout (Xcode-like):
//   1. hierarchical BFS seed — related entities start near each other
//   2. force refinement with RECTANGLE collision — cards never overlap,
//      springs pull connected cards together
//

import Foundation
import CoreGraphics

enum LayoutMode: String, CaseIterable, Identifiable {
    case custom = "自定义"
    case saved = "原始排版"
    case force = "力导向"
    case hierarchical = "层级"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .custom: return "hand.draw"
        case .saved: return "square.on.square"
        case .force: return "atom"
        case .hierarchical: return "list.bullet.indent"
        }
    }
}

enum LayoutEngine {

    // MARK: - Saved (from XML <elements>)

    @discardableResult
    static func applySaved(_ nodes: inout [EntityNode]) -> Bool {
        var found = false
        for i in nodes.indices {
            if let saved = nodes[i].savedPosition {
                nodes[i].position = saved
                found = true
            }
            nodes[i].isPinned = false
        }
        if found {
            let missing = nodes.indices.filter { nodes[$0].savedPosition == nil }
            if !missing.isEmpty {
                let maxX = (nodes.compactMap { $0.savedPosition?.x }.max() ?? 0) + 320
                for (k, idx) in missing.enumerated() {
                    nodes[idx].position = CGPoint(x: maxX + CGFloat(k % 3) * 300,
                                                  y: CGFloat(k / 3) * 240)
                }
            }
        }
        return found
    }

    // MARK: - Force directed (seeded by hierarchy + rect collision)

    static func forceDirected(_ nodes: inout [EntityNode], edges: [RelationshipEdge], iterations: Int? = nil) {
        guard nodes.count > 1 else {
            if nodes.count == 1 { nodes[0].position = .zero }
            return
        }

        // Phase 1: hierarchical seed so connected entities start in the same region
        hierarchical(&nodes, edges: edges)

        let n = nodes.count
        let iters = iterations ?? max(140, min(420, 20000 / n + 100))

        let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.name, $0) })
        let edgePairs: [(Int, Int)] = edges.compactMap { e in
            guard !e.isSelfLoop,
                  let i = index[e.fromEntity], let j = index[e.toEntity], i != j else { return nil }
            return (i, j)
        }

        let gapX: CGFloat = 80          // min horizontal gutter between cards
        let gapY: CGFloat = 70          // min vertical gutter
        var maxStep: CGFloat = 26

        var disp = [CGVector](repeating: .zero, count: n)

        for _ in 0..<iters {
            for i in 0..<n { disp[i] = .zero }

            // Springs: pull related cards together
            for (i, j) in edgePairs {
                let dx = nodes[j].position.x - nodes[i].position.x
                let dy = nodes[j].position.y - nodes[i].position.y
                let d = max(hypot(dx, dy), 0.01)
                let rest: CGFloat = 430
                let f = (d - rest) * 0.3
                let fx = dx / d * f, fy = dy / d * f
                disp[i].dx += fx; disp[i].dy += fy
                disp[j].dx -= fx; disp[j].dy -= fy
            }

            // Pairwise: mild repulsion + hard rectangle separation
            for i in 0..<n {
                let pi = nodes[i].position, si = nodes[i].size
                for j in (i + 1)..<n {
                    let pj = nodes[j].position, sj = nodes[j].size
                    var dx = pi.x - pj.x
                    var dy = pi.y - pj.y
                    var d = hypot(dx, dy)
                    if d < 1 {
                        dx = CGFloat.random(in: -1...1)
                        dy = CGFloat.random(in: -1...1)
                        d = max(hypot(dx, dy), 0.01)
                    }

                    // Mild repulsion (spreads unrelated clusters)
                    if d < 1400 {
                        let f = min(110000 / (d * d), 16)
                        let ux = dx / d, uy = dy / d
                        disp[i].dx += ux * f; disp[i].dy += uy * f
                        disp[j].dx -= ux * f; disp[j].dy -= uy * f
                    }

                    // Rectangle separation (cards must not touch)
                    let minSepX = (si.width + sj.width) / 2 + gapX
                    let minSepY = (si.height + sj.height) / 2 + gapY
                    let adx = abs(dx), ady = abs(dy)
                    if adx < minSepX && ady < minSepY {
                        let px = minSepX - adx
                        let py = minSepY - ady
                        if px < py {
                            let sx: CGFloat = dx >= 0 ? 1 : -1
                            let push = min(px, 70) * 0.55
                            disp[i].dx += sx * push; disp[j].dx -= sx * push
                        } else {
                            let sy: CGFloat = dy >= 0 ? 1 : -1
                            let push = min(py, 70) * 0.55
                            disp[i].dy += sy * push; disp[j].dy -= sy * push
                        }
                    }
                }
            }

            // Weak gravity keeps everything on screen
            for i in 0..<n {
                disp[i].dx -= nodes[i].position.x * 0.0018
                disp[i].dy -= nodes[i].position.y * 0.0018
            }

            // Integrate with cooling
            for i in 0..<n where !nodes[i].isPinned {
                let d = hypot(disp[i].dx, disp[i].dy)
                if d > 0.01 {
                    let lim = min(d, maxStep)
                    nodes[i].position.x += disp[i].dx / d * lim
                    nodes[i].position.y += disp[i].dy / d * lim
                }
            }
            maxStep = max(maxStep * 0.985, 0.8)
        }

        // Phase 3: deterministic overlap sweep (guarantees zero overlaps)
        resolveOverlaps(&nodes, gapX: gapX, gapY: gapY, rounds: 60)

        roundPositions(&nodes)
    }

    /// Pushes any still-overlapping cards apart until none remain.
    static func resolveOverlaps(_ nodes: inout [EntityNode],
                                gapX: CGFloat = 80, gapY: CGFloat = 70,
                                rounds: Int = 60) {
        for _ in 0..<rounds {
            var moved = false
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let a = nodes[i], b = nodes[j]
                    let dx = b.position.x - a.position.x
                    let dy = b.position.y - a.position.y
                    let minSepX = (a.size.width + b.size.width) / 2 + gapX
                    let minSepY = (a.size.height + b.size.height) / 2 + gapY
                    let adx = abs(dx), ady = abs(dy)
                    if adx < minSepX && ady < minSepY {
                        let px = minSepX - adx
                        let py = minSepY - ady
                        if px < py {
                            let sx: CGFloat = dx >= 0 ? 1 : -1
                            if !a.isPinned { nodes[i].position.x -= sx * px / 2 }
                            if !b.isPinned { nodes[j].position.x += sx * px / 2 }
                        } else {
                            let sy: CGFloat = dy >= 0 ? 1 : -1
                            if !a.isPinned { nodes[i].position.y -= sy * py / 2 }
                            if !b.isPinned { nodes[j].position.y += sy * py / 2 }
                        }
                        moved = true
                    }
                }
            }
            if !moved { break }
        }
    }

    // MARK: - Hierarchical (topological layers, height-aware spacing)

    static func hierarchical(_ nodes: inout [EntityNode], edges: [RelationshipEdge]) {
        guard !nodes.isEmpty else { return }
        let names = nodes.map(\.name)
        let nameSet = Set(names)

        var outgoing: [String: [String]] = [:]
        var incoming: [String: [String]] = [:]
        for e in edges where !e.isSelfLoop && nameSet.contains(e.fromEntity) && nameSet.contains(e.toEntity) {
            outgoing[e.fromEntity, default: []].append(e.toEntity)
            incoming[e.toEntity, default: []].append(e.fromEntity)
        }

        var roots = names.filter { name in
            let hasParent = nodes.first(where: { $0.name == name })?.parentEntity != nil
            return !hasParent && (incoming[name] ?? []).isEmpty
        }
        if roots.isEmpty {
            if let best = names.max(by: { (outgoing[$0] ?? []).count < (outgoing[$1] ?? []).count }) {
                roots = [best]
            } else {
                roots = [names[0]]
            }
        }

        // BFS layering (visited-based: safe with cycles)
        var layer: [String: Int] = [:]
        var queue: [(String, Int)] = roots.map { ($0, 0) }
        while let (name, depth) = queue.first {
            queue.removeFirst()
            if layer[name] != nil { continue }
            layer[name] = depth
            for child in outgoing[name] ?? [] {
                queue.append((child, depth + 1))
            }
        }
        let maxLayer = layer.values.max() ?? 0
        for name in names where layer[name] == nil {
            layer[name] = maxLayer + 1
        }

        var layerDict: [Int: [String]] = [:]
        for name in names { layerDict[layer[name] ?? 0, default: []].append(name) }
        let sortedKeys = layerDict.keys.sorted()

        // Barycenter ordering within each layer
        var order: [[String]] = sortedKeys.map { (layerDict[$0] ?? []).sorted() }
        for li in 1..<order.count {
            var prevSlot: [String: Double] = [:]
            for (i, nm) in order[li - 1].enumerated() { prevSlot[nm] = Double(i) }
            order[li].sort { a, b in
                let pa = (incoming[a] ?? []).compactMap { prevSlot[$0] }
                let pb = (incoming[b] ?? []).compactMap { prevSlot[$0] }
                let ba = pa.isEmpty ? Double.greatestFiniteMagnitude : pa.reduce(0, +) / Double(pa.count)
                let bb = pb.isEmpty ? Double.greatestFiniteMagnitude : pb.reduce(0, +) / Double(pb.count)
                if ba != bb { return ba < bb }
                return a < b
            }
        }

        // Positions: wrap each layer into multiple rows so the graph never
        // gets too wide; height-aware vertical spacing.
        let indexByName = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.name, $0) })
        let xGap: CGFloat = NodeMetrics.width + 120
        let maxRowWidth: CGFloat = 2600
        let maxPerRow = max(3, Int(maxRowWidth / xGap))

        var y: CGFloat = 0
        for layerNames in order {
            // split into rows, keeping barycenter order (related nodes stay adjacent)
            var rowStart = 0
            while rowStart < layerNames.count {
                let row = Array(layerNames[rowStart..<min(rowStart + maxPerRow, layerNames.count)])
                let heights = row.compactMap { indexByName[$0] }.map { nodes[$0].size.height }
                let maxH = heights.max() ?? 160
                let totalWidth = CGFloat(row.count) * xGap
                for (ni, name) in row.enumerated() {
                    guard let idx = indexByName[name] else { continue }
                    nodes[idx].position = CGPoint(x: -totalWidth / 2 + CGFloat(ni) * xGap + xGap / 2,
                                                  y: y + maxH / 2)
                    nodes[idx].isPinned = false
                }
                rowStart += maxPerRow
                let isLastRowOfLayer = rowStart >= layerNames.count
                // tighter gap between wrapped rows, larger gap between layers
                y += maxH + (isLastRowOfLayer ? 240 : 160)
            }
        }
        // Center vertically around origin
        let totalH = y
        for i in nodes.indices { nodes[i].position.y -= totalH / 2 }

        roundPositions(&nodes)
    }

    private static func roundPositions(_ nodes: inout [EntityNode]) {
        for i in nodes.indices {
            nodes[i].position.x = (nodes[i].position.x * 2).rounded() / 2
            nodes[i].position.y = (nodes[i].position.y * 2).rounded() / 2
        }
    }
}
