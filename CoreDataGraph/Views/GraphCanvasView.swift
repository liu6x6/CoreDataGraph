//
//  GraphCanvasView.swift
//  CoreDataGraph
//
//  Main canvas: edges drawn with Canvas, entity cards as SwiftUI views.
//  World → screen transform: screen = world * zoom + pan
//

import SwiftUI
import AppKit

struct GraphCanvasView: View {
    @Bindable var vm: GraphViewModel

    @State private var dragOriginals: [String: CGPoint] = [:]
    @State private var dragGroupOriginals: [String: CGPoint]?
    @State private var magnifyStartZoom: CGFloat?
    @State private var magnifyStartPan: CGSize?
    @State private var panStart: CGSize?
    @State private var bgDragMode: BackgroundDragMode?
    @State private var marqueeStart: CGPoint?
    @State private var isHoveringCanvas = false
    @State private var scrollMonitor: Any?

    private enum BackgroundDragMode { case marquee, pan }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let zoom = vm.zoom
            let pan = vm.pan
            // Read settings during body evaluation so changes trigger a redraw
            let settings = AppSettings.shared
            let lw = CGFloat(settings.edgeLineWidth)
            let arrow = settings.arrowStyle
            let edgeHiColor = settings.selectedEdgeColor
            let showEdgeLabels = settings.showEdgeLabels

            ZStack {
                // Background: marquee select (drag) / pan (⌥drag) / deselect (click)
                Color(nsColor: .textBackgroundColor)
                    .opacity(0.35)
                    .contentShape(Rectangle())
                    .gesture(backgroundGesture)
                    .onTapGesture { vm.backgroundTapped() }

                // Edges — drawn in WORLD coordinates; the context itself is
                // translated/scaled so lines, arrows and labels zoom together
                // with the cards (Xcode behaviour).
                Canvas { ctx, _ in
                    var ctx = ctx
                    ctx.translateBy(x: pan.width, y: pan.height)
                    ctx.scaleBy(x: zoom, y: zoom)
                    let nodes = vm.nodes
                    let edges = vm.edges
                    let selected = vm.selectedEntity
                    let search = vm.searchText
                    let collapsed = vm.collapsedEntities
                    let group = vm.groupSelection
                    GraphDrawing.draw(
                        ctx: ctx,
                        nodes: nodes,
                        edges: edges,
                        selectedEntity: selected,
                        matchesSearch: { node in
                            guard !search.isEmpty else { return true }
                            let q = search.lowercased()
                            return node.name.lowercased().contains(q) ||
                                   node.attributes.contains { $0.name.lowercased().contains(q) } ||
                                   node.relationships.contains { $0.name.lowercased().contains(q) }
                        },
                        collapsed: collapsed,
                        groupSelection: group,
                        lineWidth: lw,
                        arrowStyle: arrow,
                        highlightColor: edgeHiColor,
                        style: .init(showLabels: showEdgeLabels))
                }
                .allowsHitTesting(false)

                // Nodes — scaled with the same zoom so cards never overlap
                ForEach(vm.nodes) { node in
                    EntityNodeView(vm: vm, node: node)
                        .scaleEffect(zoom)
                        .position(vm.toScreen(node.position))
                        .gesture(nodeDragGesture(for: node))
                        .onTapGesture(count: 2) { vm.toggleExpanded(node.name) }
                }

                // Marquee rubber band
                if let r = vm.marqueeRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                vm.canvasSize = size
                if vm.needsZoomToFit { vm.zoomToFit(size: size) }
            }
            .onChange(of: size) { _, newSize in
                vm.canvasSize = newSize
            }
            .onChange(of: vm.needsZoomToFit) { _, newValue in
                if newValue { vm.zoomToFit(size: size) }
            }
            .gesture(magnificationGesture(size: size))
            .onReceive(NotificationCenter.default.publisher(for: .zoomToFitNotification)) { _ in
                vm.zoomToFit(size: size)
            }
            .onReceive(NotificationCenter.default.publisher(for: .relayoutNotification)) { _ in
                vm.applyLayout()
                vm.needsZoomToFit = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsChangedNotification)) { _ in
                AppSettings.shared.applyMetrics()
                vm.refreshNodeSizes()
            }
            .background(DotGridBackground())
            .clipShape(Rectangle())   // cards must not overflow onto the sidebar/inspector
            .onContinuousHover { phase in
                switch phase {
                case .active: isHoveringCanvas = true
                case .ended: isHoveringCanvas = false
                }
            }
            .onAppear {
                // Trackpad two-finger scroll = pan the canvas (Figma style)
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard isHoveringCanvas else { return event }
                    let sign: CGFloat = AppSettings.shared.scrollPanReversed ? -1 : 1
                    vm.panBy(dx: event.scrollingDeltaX * sign, dy: event.scrollingDeltaY * sign)
                    return nil   // consumed
                }
            }
            .onDisappear {
                if let m = scrollMonitor {
                    NSEvent.removeMonitor(m)
                    scrollMonitor = nil
                }
            }
        }
    }

    // MARK: - Gestures

    /// Drag on empty space: default = marquee select; hold ⌥ = pan.
    private var backgroundGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { g in
                if bgDragMode == nil {
                    if NSEvent.modifierFlags.contains(.option) {
                        bgDragMode = .pan
                        panStart = vm.pan
                    } else {
                        bgDragMode = .marquee
                        marqueeStart = g.startLocation
                    }
                }
                switch bgDragMode {
                case .pan:
                    guard let start = panStart else { return }
                    vm.pan = CGSize(width: start.width + g.translation.width,
                                    height: start.height + g.translation.height)
                case .marquee:
                    guard let start = marqueeStart else { return }
                    vm.updateMarquee(from: start, to: g.location)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                if bgDragMode == .marquee { vm.endMarquee() }
                bgDragMode = nil
                panStart = nil
                marqueeStart = nil
            }
    }

    private func magnificationGesture(size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if magnifyStartZoom == nil {
                    magnifyStartZoom = vm.zoom
                    magnifyStartPan = vm.pan
                }
                guard let startZoom = magnifyStartZoom, let startPan = magnifyStartPan else { return }
                let newZoom = min(max(startZoom * value, 0.08), 3.0)
                // Keep canvas center stable
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let world = CGPoint(x: (c.x - startPan.width) / startZoom,
                                    y: (c.y - startPan.height) / startZoom)
                vm.zoom = newZoom
                vm.pan = CGSize(width: c.x - world.x * newZoom,
                                height: c.y - world.y * newZoom)
            }
            .onEnded { _ in
                magnifyStartZoom = nil
                magnifyStartPan = nil
            }
    }

    private func nodeDragGesture(for node: EntityNode) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { g in
                if dragOriginals[node.name] == nil {
                    dragOriginals[node.name] = node.position
                    // If this card belongs to a multi-selection, move the whole group
                    if vm.groupSelection.contains(node.name) && vm.groupSelection.count > 1 {
                        var originals: [String: CGPoint] = [:]
                        for name in vm.groupSelection {
                            if let n = vm.node(named: name) { originals[name] = n.position }
                        }
                        dragGroupOriginals = originals
                    } else {
                        dragGroupOriginals = nil
                    }
                }
                let dx = g.translation.width / vm.zoom
                let dy = g.translation.height / vm.zoom
                if let group = dragGroupOriginals {
                    for (name, orig) in group {
                        vm.setNodePosition(name, CGPoint(x: orig.x + dx, y: orig.y + dy))
                    }
                } else if let orig = dragOriginals[node.name] {
                    vm.setNodePosition(node.name, CGPoint(x: orig.x + dx, y: orig.y + dy))
                }
            }
            .onEnded { _ in
                dragOriginals[node.name] = nil
                dragGroupOriginals = nil
                vm.savePositions()   // remember custom layout
            }
    }
}

// MARK: - Dot grid

struct DotGridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 24
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.4, height: 1.4))
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(dot.applying(CGAffineTransform(translationX: x, y: y)),
                             with: .color(.secondary.opacity(0.12)))
                    y += spacing
                }
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

extension Notification.Name {
    static let zoomToFitNotification = Notification.Name("CoreDataGraph.zoomToFit")
    static let relayoutNotification = Notification.Name("CoreDataGraph.relayout")
}
