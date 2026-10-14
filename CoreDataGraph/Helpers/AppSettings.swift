//
//  AppSettings.swift
//  CoreDataGraph
//
//  User preferences persisted in UserDefaults; changes apply live.
//

import SwiftUI
import Observation
import AppKit

// MARK: - Color hex helpers (for UserDefaults persistence)

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return "#007AFF" }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Arrow style

enum ArrowStyle: String, CaseIterable, Identifiable {
    case hollow = "空心箭头 (Xcode)"
    case filled = "实心箭头"
    case crowFoot = "鸦爪 (Crow's foot)"
    case lineChevron = "线条箭头 (→ / ⇒)"
    case none = "无箭头"
    var id: String { rawValue }

    /// Short label for segmented controls
    var shortName: String {
        switch self {
        case .hollow: return "空心"
        case .filled: return "实心"
        case .crowFoot: return "鸦爪"
        case .lineChevron: return "线条"
        case .none: return "无"
        }
    }
}

// MARK: - Settings

@Observable
final class AppSettings {

    static let shared = AppSettings()

    /// Card font scale (0.8 – 1.6). Node card sizes scale with it.
    var cardFontScale: Double {
        didSet {
            defaults.set(cardFontScale, forKey: Keys.fontScale)
            applyMetrics()
            postChanged()
        }
    }

    /// Card width in points (min 150).
    var cardWidth: Double {
        didSet {
            let clamped = max(150, cardWidth)
            if clamped != cardWidth { cardWidth = clamped; return }
            defaults.set(cardWidth, forKey: Keys.cardWidth)
            applyMetrics()
            postChanged()
        }
    }

    /// Relationship line width in points.
    var edgeLineWidth: Double {
        didSet { defaults.set(edgeLineWidth, forKey: Keys.lineWidth) }
    }

    /// Arrow head style for relationship lines.
    var arrowStyle: ArrowStyle {
        didSet { defaults.set(arrowStyle.rawValue, forKey: Keys.arrowStyle) }
    }

    /// Show attribute types on entity cards.
    var showAttributeTypes: Bool {
        didSet { defaults.set(showAttributeTypes, forKey: Keys.showTypes) }
    }

    /// Reverse trackpad scroll panning direction.
    var scrollPanReversed: Bool {
        didSet { defaults.set(scrollPanReversed, forKey: Keys.scrollReversed) }
    }

    /// Show relationship-name labels on the lines.
    var showEdgeLabels: Bool {
        didSet { defaults.set(showEdgeLabels, forKey: Keys.showEdgeLabels) }
    }

    /// Selection colors (persisted as hex strings)
    var selectedNodeColorHex: String {
        didSet { defaults.set(selectedNodeColorHex, forKey: Keys.nodeColor) }
    }
    var selectedEdgeColorHex: String {
        didSet { defaults.set(selectedEdgeColorHex, forKey: Keys.edgeColor) }
    }

    var selectedNodeColor: Color { Color(hex: selectedNodeColorHex) }
    var selectedEdgeColor: Color { Color(hex: selectedEdgeColorHex) }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let fontScale = "settings.cardFontScale"
        static let cardWidth = "settings.cardWidth"
        static let lineWidth = "settings.edgeLineWidth"
        static let arrowStyle = "settings.arrowStyle"
        static let showTypes = "settings.showAttributeTypes"
        static let scrollReversed = "settings.scrollPanReversed"
        static let showEdgeLabels = "settings.showEdgeLabels"
        static let nodeColor = "settings.selectedNodeColor"
        static let edgeColor = "settings.selectedEdgeColor"
    }

    private init() {
        defaults.register(defaults: [
            Keys.fontScale: 1.0,
            Keys.cardWidth: 218.0,
            Keys.lineWidth: 1.6,
            Keys.arrowStyle: ArrowStyle.hollow.rawValue,
            Keys.showTypes: true,
            Keys.scrollReversed: false,
            Keys.showEdgeLabels: true,
            Keys.nodeColor: "#007AFF",
            Keys.edgeColor: "#007AFF",
        ])
        cardFontScale = defaults.double(forKey: Keys.fontScale)
        cardWidth = max(150, defaults.double(forKey: Keys.cardWidth))
        edgeLineWidth = defaults.double(forKey: Keys.lineWidth)
        let arrowRaw = defaults.string(forKey: Keys.arrowStyle) ?? ArrowStyle.hollow.rawValue
        arrowStyle = ArrowStyle(rawValue: arrowRaw) ?? .hollow
        showAttributeTypes = defaults.bool(forKey: Keys.showTypes)
        scrollPanReversed = defaults.bool(forKey: Keys.scrollReversed)
        showEdgeLabels = defaults.bool(forKey: Keys.showEdgeLabels)
        selectedNodeColorHex = defaults.string(forKey: Keys.nodeColor) ?? "#007AFF"
        selectedEdgeColorHex = defaults.string(forKey: Keys.edgeColor) ?? "#007AFF"
        applyMetrics()
    }

    /// Push font scale into NodeMetrics so all sizing/layout picks it up.
    func applyMetrics() {
        NodeMetrics.scale = CGFloat(cardFontScale)
        NodeMetrics.baseWidth = CGFloat(cardWidth)
    }

    func resetToDefaults() {
        cardFontScale = 1.0
        cardWidth = 218
        edgeLineWidth = 1.6
        arrowStyle = .hollow
        showAttributeTypes = true
        scrollPanReversed = false
        showEdgeLabels = true
        selectedNodeColorHex = "#007AFF"
        selectedEdgeColorHex = "#007AFF"
    }

    private func postChanged() {
        NotificationCenter.default.post(name: .settingsChangedNotification, object: nil)
    }
}

extension Notification.Name {
    static let settingsChangedNotification = Notification.Name("CoreDataGraph.settingsChanged")
}
