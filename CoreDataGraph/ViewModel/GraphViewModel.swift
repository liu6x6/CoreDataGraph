//
//  GraphViewModel.swift
//  CoreDataGraph
//

import Foundation
import SwiftUI
import Observation
import AppKit

@Observable
final class GraphViewModel {

    // MARK: Document state

    var document: GraphDocument?
    var loadError: String?
    var statusMessage: String?

    var modelName: String { document?.name ?? "CoreDataGraph" }
    var versions: [ModelVersion] { document?.versions ?? [] }
    var currentVersion: ModelVersion? { document?.currentVersion }

    // MARK: Graph state

    var nodes: [EntityNode] = []
    var edges: [RelationshipEdge] = []
    var inheritanceLinks: [InheritanceLink] = []

    // MARK: UI state

    var selectedEntity: String?
    var groupSelection: Set<String> = []     // marquee / shift-click multi selection
    var marqueeRect: CGRect?                 // screen space, while dragging
    var searchText = ""
    var layoutMode: LayoutMode = .saved
    var collapsedEntities: Set<String> = []
    var requestFileImport = false
    var needsZoomToFit = false
    var canvasSize: CGSize = .zero

    // Zoom / pan: screen = world * zoom + pan
    var zoom: CGFloat = 1.0
    var pan: CGSize = .zero

    // MARK: Diff state

    var compareOld: ModelVersion?
    var compareNew: ModelVersion?
    var diff: ModelDiff?
    /// Row-level status: entity → attribute name → status
    var diffAttrStatus: [String: [String: DiffStatus]] = [:]
    /// Row-level status: entity → relationship name → status
    var diffRelStatus: [String: [String: DiffStatus]] = [:]

    var isDiffMode: Bool {
        compareOld != nil && compareNew != nil && compareOld != compareNew
    }

    // MARK: Auto refresh

    var autoRefresh = true
    private var watchers: [DirectoryWatcher] = []
    private var reloadTask: Task<Void, Never>?
    private var scopedURLs: [URL] = []

    private var nodeIndex: [String: Int] = [:]

    // MARK: - Open

    func open(url: URL) {
        // Take security scope (needed for sandbox + file watching)
        if url.startAccessingSecurityScopedResource() {
            scopedURLs.append(url)
        }

        do {
            let doc = try ModelLoader.load(url: url)
            // Release old scopes
            for old in scopedURLs where old != url { old.stopAccessingSecurityScopedResource() }
            scopedURLs.removeAll { $0 != url }

            document = doc
            loadError = nil
            compareOld = nil
            compareNew = nil
            diff = nil
            diffAttrStatus = [:]
            diffRelStatus = [:]
            RecentFilesStore.shared.add(url)
            RecentFilesStore.shared.markLastOpened(url)
            selectedEntity = nil
            searchText = ""
            rebuildGraph()
            startWatching()
            statusMessage = "已加载 \(doc.name)（\(doc.document.entities.count) 个实体）"
        } catch {
            loadError = error.localizedDescription
            document = nil
            nodes = []
            edges = []
            stopWatching()
        }
    }

    func selectVersion(_ version: ModelVersion) {
        guard var doc = document else { return }
        do {
            let parsed = try ModelLoader.parseVersion(version)
            doc.document = parsed
            doc.currentVersion = version
            document = doc
            compareOld = nil
            compareNew = nil
            diff = nil
            diffAttrStatus = [:]
            diffRelStatus = [:]
            rebuildGraph()
            statusMessage = "已切换到 \(version.name)"
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Diff (any two versions)

    func setCompare(old: ModelVersion?, new: ModelVersion?) {
        compareOld = old
        compareNew = new
        if isDiffMode, let o = compareOld, let n = compareNew {
            do {
                let oldDoc = try ModelLoader.parseVersion(o)
                let newDoc = try ModelLoader.parseVersion(n)
                diff = ModelDiffer.diff(old: oldDoc, oldName: o.name,
                                        new: newDoc, newName: n.name)
                buildDiffLookups()
                statusMessage = "对比 \(o.name) → \(n.name): \(diff?.summary ?? "")"
            } catch {
                loadError = error.localizedDescription
                diff = nil
                diffAttrStatus = [:]
                diffRelStatus = [:]
            }
        } else {
            diff = nil
            diffAttrStatus = [:]
            diffRelStatus = [:]
        }
        rebuildGraph()
    }

    func clearCompare() {
        setCompare(old: nil, new: nil)
    }

    private func buildDiffLookups() {
        var a: [String: [String: DiffStatus]] = [:]
        var r: [String: [String: DiffStatus]] = [:]
        for c in diff?.changedEntities ?? [] {
            for x in c.addedAttributes { a[c.name, default: [:]][x.name] = .added }
            for x in c.removedAttributes { a[c.name, default: [:]][x.name] = .removed }
            for x in c.changedAttributes { a[c.name, default: [:]][x.name] = .changed }
            for x in c.addedRelationships { r[c.name, default: [:]][x.name] = .added }
            for x in c.removedRelationships { r[c.name, default: [:]][x.name] = .removed }
            for x in c.changedRelationships { r[c.name, default: [:]][x.name] = .changed }
        }
        diffAttrStatus = a
        diffRelStatus = r
    }

    /// Relationships deleted in the new version — shown as red strikethrough rows
    func removedRelationshipNames(of entityName: String) -> [String] {
        guard isDiffMode else { return [] }
        return (diffRelStatus[entityName] ?? [:])
            .filter { $0.value == .removed }
            .keys.sorted()
    }

    // MARK: - Graph building

    func rebuildGraph() {
        guard let doc = document else { nodes = []; edges = []; return }

        var built: [EntityNode]
        var builtEdges: [RelationshipEdge] = []

        if isDiffMode, let oldV = compareOld, let newV = compareNew,
           let diff,
           let oldDoc = try? ModelLoader.parseVersion(oldV),
           let newDoc = try? ModelLoader.parseVersion(newV) {

            // Display the NEW version, colored against the OLD one
            built = newDoc.entities
            for i in built.indices {
                built[i].diffStatus = ModelDiffer.entityStatus(built[i].name, in: diff)
            }
            // Ghost cards for removed entities
            let removedSet = Set(diff.removedEntities)
            for old in oldDoc.entities where removedSet.contains(old.name) {
                var ghost = old
                ghost.diffStatus = .removed
                built.append(ghost)
            }

            let nameSet = Set(built.map(\.name))
            // Edges of surviving entities, with row-level diff status
            for node in built where node.diffStatus != .removed {
                for rel in node.relationships {
                    guard nameSet.contains(rel.destinationEntity) else { continue }
                    let status = diffRelStatus[node.name]?[rel.name] ?? .none
                    builtEdges.append(RelationshipEdge(name: rel.name,
                                                       fromEntity: node.name,
                                                       toEntity: rel.destinationEntity,
                                                       info: rel,
                                                       diffStatus: status))
                }
            }
            // Ghost edges: relationships owned by removed entities
            for node in built where node.diffStatus == .removed {
                for rel in node.relationships {
                    guard nameSet.contains(rel.destinationEntity) else { continue }
                    builtEdges.append(RelationshipEdge(name: rel.name,
                                                       fromEntity: node.name,
                                                       toEntity: rel.destinationEntity,
                                                       info: rel,
                                                       diffStatus: .removed))
                }
            }
            // Ghost edges: relationships deleted from surviving entities
            for (entityName, rels) in diffRelStatus {
                for (relName, status) in rels where status == .removed {
                    guard nameSet.contains(entityName),
                          let oldRel = oldDoc.entities
                              .first(where: { $0.name == entityName })?
                              .relationships.first(where: { $0.name == relName }),
                          nameSet.contains(oldRel.destinationEntity) else { continue }
                    builtEdges.append(RelationshipEdge(name: relName,
                                                       fromEntity: entityName,
                                                       toEntity: oldRel.destinationEntity,
                                                       info: oldRel,
                                                       diffStatus: .removed))
                }
            }
        } else {
            built = doc.document.entities
            for i in built.indices { built[i].diffStatus = .none }
            let nameSet = Set(built.map(\.name))
            for node in built {
                for rel in node.relationships {
                    guard nameSet.contains(rel.destinationEntity) else { continue }
                    builtEdges.append(RelationshipEdge(name: rel.name,
                                                       fromEntity: node.name,
                                                       toEntity: rel.destinationEntity,
                                                       info: rel))
                }
            }
        }

        // Compute card sizes (extra red rows for deleted relationships in diff mode)
        for i in built.indices {
            let extra = removedRelationshipNames(of: built[i].name).count
            built[i].size = NodeMetrics.size(for: built[i],
                                             collapsed: collapsedEntities.contains(built[i].name),
                                             extraRelRows: extra)
        }

        nodes = built
        edges = builtEdges
        // Inheritance (parentEntity) links, drawn separately with UML hollow triangles
        let nameSet = Set(built.map(\.name))
        var links: [InheritanceLink] = []
        for n in built {
            if let p = n.parentEntity, nameSet.contains(p) {
                links.append(InheritanceLink(child: n.name, parent: p))
            }
        }
        inheritanceLinks = links
        reindex()
        applyLayout(initial: true)
        needsZoomToFit = true
    }

    private func reindex() {
        nodeIndex = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.name, $0) })
    }

    func node(named name: String) -> EntityNode? {
        guard let i = nodeIndex[name] else { return nil }
        return nodes[i]
    }

    // MARK: - Layout

    func applyLayout(initial: Bool = false) {
        // Highest priority: user's manually saved custom layout
        if let doc = document,
           let custom = PositionStore.load(root: doc.rootURL, version: doc.currentVersion?.name) {
            if initial || layoutMode == .custom {
                applyCustomPositions(custom)
                reindex()
                if initial {
                    statusMessage = "已恢复上次的自定义排版（拖动卡片可调整，切换其它布局可清除）"
                }
                return
            }
        }

        var mode = layoutMode
        if initial {
            // Auto pick: prefer saved positions if the model has them
            let hasSaved = nodes.contains { $0.savedPosition != nil }
            mode = hasSaved ? .saved : .force
            layoutMode = mode
        }
        if mode == .custom {
            // No stored layout yet — behave like force
            mode = .force
            layoutMode = .force
        }
        switch mode {
        case .saved:
            if !LayoutEngine.applySaved(&nodes) {
                LayoutEngine.forceDirected(&nodes, edges: edges)
            }
        case .force:
            for i in nodes.indices { nodes[i].isPinned = false }
            LayoutEngine.forceDirected(&nodes, edges: edges)
        case .hierarchical:
            for i in nodes.indices { nodes[i].isPinned = false }
            LayoutEngine.hierarchical(&nodes, edges: edges)
        case .custom:
            break
        }
        reindex()
    }

    /// Restore saved positions; unknown/new entities get parked in a grid,
    /// then overlaps are resolved deterministically.
    @discardableResult
    private func applyCustomPositions(_ saved: [String: CGPoint]) -> Bool {
        var applied = false
        var missing: [Int] = []
        for i in nodes.indices {
            if let p = saved[nodes[i].name] {
                nodes[i].position = p
                nodes[i].isPinned = true
                applied = true
            } else {
                missing.append(i)
            }
        }
        guard applied else { return false }
        if !missing.isEmpty {
            let maxX = nodes.compactMap { saved[$0.name]?.x }.max() ?? 0
            for (k, i) in missing.enumerated() {
                nodes[i].position = CGPoint(x: maxX + 340 + CGFloat(k % 2) * 320,
                                            y: CGFloat(k / 2) * 300)
                nodes[i].isPinned = false
            }
            LayoutEngine.resolveOverlaps(&nodes)
        }
        return true
    }

    /// Persist current positions as the custom layout for this model+version.
    func savePositions() {
        guard let doc = document else { return }
        var dict: [String: CGPoint] = [:]
        for n in nodes { dict[n.name] = n.position }
        PositionStore.save(dict, root: doc.rootURL, version: doc.currentVersion?.name)
        layoutMode = .custom
    }

    func clearSavedPositions() {
        guard let doc = document else { return }
        PositionStore.clear(root: doc.rootURL, version: doc.currentVersion?.name)
        statusMessage = "已清除自定义排版记忆"
    }

    func setLayoutMode(_ mode: LayoutMode) {
        captureForUndo()
        layoutMode = mode
        if mode != .custom, let doc = document {
            // Explicit re-layout replaces the remembered custom arrangement
            PositionStore.clear(root: doc.rootURL, version: doc.currentVersion?.name)
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            applyLayout()
        }
        if mode != .custom {
            needsZoomToFit = true
        }
    }

    func unpinAll() {
        for i in nodes.indices { nodes[i].isPinned = false }
        statusMessage = "已解除全部固定"
    }

    // MARK: - Selection & filtering

    func selectEntity(_ name: String?) {
        selectedEntity = name
    }

    // MARK: - Group selection (marquee)

    func cardTapped(_ name: String) {
        let shift = NSEvent.modifierFlags.contains(.shift)
        if shift {
            if groupSelection.contains(name) {
                groupSelection.remove(name)
            } else {
                groupSelection.insert(name)
            }
            selectedEntity = name
        } else if groupSelection.contains(name) && groupSelection.count > 1 {
            // keep the group, just move the inspector focus
            selectedEntity = name
        } else {
            groupSelection = []
            selectedEntity = name
        }
    }

    func backgroundTapped() {
        selectedEntity = nil
        groupSelection = []
    }

    func updateMarquee(from start: CGPoint, to current: CGPoint) {
        marqueeRect = CGRect(x: min(start.x, current.x),
                             y: min(start.y, current.y),
                             width: abs(current.x - start.x),
                             height: abs(current.y - start.y))
    }

    func endMarquee() {
        guard let r = marqueeRect else { return }
        marqueeRect = nil
        guard r.width > 4 || r.height > 4 else { return }   // treat as click
        let tl = toWorld(r.origin)
        let br = toWorld(CGPoint(x: r.maxX, y: r.maxY))
        let world = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)

        var sel: Set<String> = []
        for n in nodes {
            let size = NodeMetrics.size(for: n, collapsed: collapsedEntities.contains(n.name))
            let card = CGRect(x: n.position.x - size.width / 2,
                              y: n.position.y - size.height / 2,
                              width: size.width, height: size.height)
            if world.intersects(card) { sel.insert(n.name) }
        }
        guard !sel.isEmpty else { groupSelection = []; return }
        groupSelection = sel
        selectedEntity = sel.count == 1 ? sel.first : nil
        statusMessage = sel.count > 1 ? "已框选 \(sel.count) 张卡片，拖动任意一张整组移动" : nil
    }

    func neighborNames(of name: String) -> Set<String> {
        var result: Set<String> = [name]
        for e in edges where e.fromEntity == name || e.toEntity == name {
            result.insert(e.fromEntity)
            result.insert(e.toEntity)
        }
        return result
    }

    func matchesSearch(_ node: EntityNode) -> Bool {
        guard !searchText.isEmpty else { return true }
        let q = searchText.lowercased()
        if node.name.lowercased().contains(q) { return true }
        if node.attributes.contains(where: { $0.name.lowercased().contains(q) }) { return true }
        if node.relationships.contains(where: { $0.name.lowercased().contains(q) }) { return true }
        return false
    }

    var highlightedEntities: Set<String> {
        guard let sel = selectedEntity else { return [] }
        return neighborNames(of: sel)
    }

    func isNodeDimmed(_ node: EntityNode) -> Bool {
        if !matchesSearch(node) { return true }
        if groupSelection.count > 1 {
            return !groupSelection.contains(node.name)
        }
        if let sel = selectedEntity {
            return !neighborNames(of: sel).contains(node.name)
        }
        return false
    }

    func isEdgeDimmed(_ edge: RelationshipEdge) -> Bool {
        if !searchText.isEmpty {
            guard let a = node(named: edge.fromEntity), let b = node(named: edge.toEntity) else { return true }
            return !matchesSearch(a) && !matchesSearch(b)
        }
        if let sel = selectedEntity {
            return edge.fromEntity != sel && edge.toEntity != sel
        }
        return false
    }

    func isEdgeHighlighted(_ edge: RelationshipEdge) -> Bool {
        guard let sel = selectedEntity else { return false }
        return edge.fromEntity == sel || edge.toEntity == sel
    }

    var filteredSidebarEntities: [EntityNode] {
        nodes
            .filter { matchesSearch($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Drag / zoom / pan

    func setNodePosition(_ name: String, _ position: CGPoint) {
        guard let i = nodeIndex[name] else { return }
        nodes[i].position = position
        nodes[i].isPinned = true
    }

    func togglePin(_ name: String) {
        guard let i = nodeIndex[name] else { return }
        nodes[i].isPinned.toggle()
    }

    /// Recompute card sizes after a settings change (font scale) and
    /// push apart any newly overlapping cards.
    func refreshNodeSizes() {
        for i in nodes.indices {
            nodes[i].size = NodeMetrics.size(for: nodes[i], collapsed: collapsedEntities.contains(nodes[i].name))
        }
        LayoutEngine.resolveOverlaps(&nodes)
    }

    func toggleExpanded(_ name: String) {
        if collapsedEntities.contains(name) {
            collapsedEntities.remove(name)
        } else {
            collapsedEntities.insert(name)
        }
        guard let i = nodeIndex[name] else { return }
        nodes[i].size = NodeMetrics.size(for: nodes[i], collapsed: collapsedEntities.contains(name))
    }

    func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * zoom + pan.width, y: p.y * zoom + pan.height)
    }

    /// Two-finger scroll pans the canvas (trackpad style).
    func panBy(dx: CGFloat, dy: CGFloat) {
        pan = CGSize(width: pan.width + dx, height: pan.height + dy)
    }

    func toWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - pan.width) / zoom, y: (p.y - pan.height) / zoom)
    }

    func zoomToFit(size: CGSize) {
        guard !nodes.isEmpty, size.width > 0, size.height > 0 else { return }
        let bounds = worldBounds(inset: 0)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let z = min((size.width - 100) / bounds.width, (size.height - 100) / bounds.height)
        zoom = min(max(z, 0.08), 1.5)
        pan = CGSize(width: size.width / 2 - bounds.midX * zoom,
                     height: size.height / 2 - bounds.midY * zoom)
        needsZoomToFit = false
    }

    func centerOn(entity name: String) {
        guard let node = node(named: name), canvasSize.width > 0 else { return }
        selectedEntity = name
        pan = CGSize(width: canvasSize.width / 2 - node.position.x * zoom,
                     height: canvasSize.height / 2 - node.position.y * zoom)
    }

    // MARK: - Fly-to focus (map style)

    private var focusTask: Task<Void, Never>?

    /// Double-click in sidebar: smoothly pan + zoom the canvas onto the card.
    func focusOn(entity name: String) {
        focusTask?.cancel()
        selectedEntity = name
        guard let node = node(named: name), canvasSize.width > 0 else { return }

        // Comfortable reading zoom: bump small views up to ~1.0, never shrink big ones
        let targetZoom = min(max(zoom, 1.0), 2.0)
        let targetPan = CGSize(width: canvasSize.width / 2 - node.position.x * targetZoom,
                               height: canvasSize.height / 2 - node.position.y * targetZoom)

        let startZoom = zoom
        let startPan = pan
        let steps = 32

        focusTask = Task { [weak self] in
            for s in 1...steps {
                guard let self, !Task.isCancelled else { return }
                let x = Double(s) / Double(steps)
                let t = x * x * (3 - 2 * x)   // smoothstep easing
                self.zoom = startZoom + (targetZoom - startZoom) * t
                self.pan = CGSize(width: startPan.width + (targetPan.width - startPan.width) * t,
                                  height: startPan.height + (targetPan.height - startPan.height) * t)
                try? await Task.sleep(nanoseconds: 16_000_000)  // ~60fps
            }
        }
    }

    func worldBounds(inset: CGFloat) -> CGRect {
        guard !nodes.isEmpty else { return .zero }
        var rect = CGRect(x: nodes[0].position.x - nodes[0].size.width / 2,
                          y: nodes[0].position.y - nodes[0].size.height / 2,
                          width: nodes[0].size.width,
                          height: nodes[0].size.height)
        for n in nodes.dropFirst() {
            rect = rect.union(CGRect(x: n.position.x - n.size.width / 2,
                                     y: n.position.y - n.size.height / 2,
                                     width: n.size.width,
                                     height: n.size.height))
        }
        return rect.insetBy(dx: -inset, dy: -inset)
    }

    // MARK: - Stats

    var statsLine: String {
        guard let doc = document else { return "" }
        let entityCount = doc.document.entities.count
        let relCount = doc.document.entities.reduce(0) { $0 + $1.relationships.count }
        let attrCount = doc.document.entities.reduce(0) { $0 + $1.attributes.count }
        var s = "\(entityCount) 实体 · \(attrCount) 属性 · \(relCount) 关系"
        if let v = doc.currentVersion { s += " · \(v.name)" }
        return s
    }

    // MARK: - File watching (auto refresh)

    private func startWatching() {
        stopWatching()
        guard autoRefresh, let doc = document else { return }
        let handler: () -> Void = { [weak self] in
            self?.scheduleReload()
        }
        var targets = [doc.rootURL]
        if doc.rootURL.pathExtension == "xcdatamodeld" {
            targets.append(contentsOf: doc.versions.map(\.url))
        }
        for url in targets {
            if let w = DirectoryWatcher(url: url, handler: handler) {
                watchers.append(w)
            }
        }
    }

    private func stopWatching() {
        watchers.removeAll()
        reloadTask?.cancel()
        reloadTask = nil
    }

    func setAutoRefresh(_ enabled: Bool) {
        autoRefresh = enabled
        if enabled { startWatching() } else { stopWatching() }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.reloadPreservingLayout()
        }
    }

    private func reloadPreservingLayout() {
        guard let doc = document else { return }
        let oldPositions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, $0.position) })
        let oldPins = Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, $0.isPinned) })
        do {
            var updated = doc
            if let version = doc.currentVersion {
                updated.document = try ModelLoader.parseVersion(version)
            }
            document = updated
            rebuildGraph()
            // Restore user-adjusted positions
            for i in nodes.indices {
                if let pos = oldPositions[nodes[i].name] {
                    nodes[i].position = pos
                    nodes[i].isPinned = oldPins[nodes[i].name] ?? false
                }
            }
            needsZoomToFit = false
            statusMessage = "模型已自动刷新 (\(Date().formatted(date: .omitted, time: .standard)))"
        } catch {
            // File may be mid-write; ignore and wait for next event
        }
        startWatching()
    }

    func reload() {
        guard let doc = document else { return }
        open(url: doc.rootURL)
    }

    // MARK: - Undo / Redo (position snapshots)

    private var undoStack: [[String: CGPoint]] = []
    private var redoStack: [[String: CGPoint]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func snapshotPositions() -> [String: CGPoint] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, $0.position) })
    }

    /// Call BEFORE a position-changing operation (drag start / re-layout).
    func captureForUndo() {
        undoStack.append(snapshotPositions())
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let snap = undoStack.popLast() else {
            statusMessage = "没有可撤销的操作"
            return
        }
        redoStack.append(snapshotPositions())
        applySnapshot(snap, message: "已撤销位置调整 (⌘Z)")
    }

    func redo() {
        guard let snap = redoStack.popLast() else {
            statusMessage = "没有可重做的操作"
            return
        }
        undoStack.append(snapshotPositions())
        applySnapshot(snap, message: "已重做 (⇧⌘Z)")
    }

    private func applySnapshot(_ snap: [String: CGPoint], message: String) {
        for i in nodes.indices {
            if let p = snap[nodes[i].name] {
                nodes[i].position = p
            }
        }
        savePositions()
        statusMessage = message
    }

    // MARK: - Restore on launch

    /// Auto-open the last used model on app start (issue: blank window after relaunch)
    func restoreLastDocument() {
        guard document == nil else { return }
        let store = RecentFilesStore.shared
        if let last = store.lastOpenedItem, let url = store.resolve(last) {
            open(url: url)
            return
        }
        if let first = store.items.first, let url = store.resolve(first) {
            open(url: url)
        }
    }
}
