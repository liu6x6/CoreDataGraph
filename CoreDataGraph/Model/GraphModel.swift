//
//  GraphModel.swift
//  CoreDataGraph
//

import Foundation
import CoreGraphics

// MARK: - Diff status

enum DiffStatus: String, Hashable {
    case none
    case added
    case removed
    case changed
}

// MARK: - Attribute

struct AttributeInfo: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var type: String
    var isOptional: Bool
    var isTransient: Bool
    var defaultValue: String?
    var customClassName: String?
    var valueTransformer: String?
    var usesScalarValueType: Bool
    var versionHashModifier: String?
    var isIndexed: Bool
    var isSpotlightIndexed: Bool
}

// MARK: - Relationship

struct RelationshipInfo: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var destinationEntity: String
    var inverseName: String?
    var inverseEntity: String?
    var isToMany: Bool
    var isOrdered: Bool
    var isOptional: Bool
    var isTransient: Bool
    var minCount: Int
    var maxCount: Int?          // nil = unbounded (to-many without max)
    var deletionRule: String    // Nullify / Cascade / Deny / No Action

    var cardinality: String {
        if isToMany {
            let upper = maxCount.map(String.init) ?? "∞"
            return "\(minCount)...\(upper)"
        } else {
            return isOptional ? "0...1" : "1...1"
        }
    }
}

// MARK: - Fetch index / constraints

struct FetchIndexElementInfo: Hashable {
    var property: String
    var order: String       // ascending / descending
    var type: String        // Binary / String ...
}

struct FetchIndexInfo: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var elements: [FetchIndexElementInfo]
}

// MARK: - Entity

struct EntityNode: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var representedClassName: String?
    var codeGenerationType: String?   // class / manual / category
    var isAbstract: Bool
    var parentEntity: String?
    var isSyncable: Bool
    var versionHashModifier: String?
    var attributes: [AttributeInfo]
    var relationships: [RelationshipInfo]
    var uniquenessConstraints: [[String]]
    var fetchIndices: [FetchIndexInfo]

    // Layout state
    var position: CGPoint = .zero
    var savedPosition: CGPoint?       // position stored in the xcdatamodel XML <elements>
    var size: CGSize = .zero
    var isPinned: Bool = false

    var diffStatus: DiffStatus = .none
}

// MARK: - Edge (derived)

struct RelationshipEdge: Identifiable, Hashable {
    var id: String { "\(fromEntity).\(name)" }
    var name: String
    var fromEntity: String
    var toEntity: String
    var info: RelationshipInfo
    var diffStatus: DiffStatus = .none

    var isSelfLoop: Bool { fromEntity == toEntity }
}

// MARK: - Configuration

struct ModelConfiguration: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var members: [String]
}

// MARK: - Version

struct ModelVersion: Identifiable, Hashable {
    var id: URL { url }
    var name: String            // "Cookidoo v27" etc
    var url: URL                // .xcdatamodel dir (or contents file / .mom)
    var isCurrent: Bool

    /// Natural sort key: trailing integer if present
    var sortIndex: Int {
        let digits = name.reversed().prefix(while: \.isNumber).reversed()
        return Int(String(digits)) ?? -1
    }
}

// MARK: - Parsed document

struct ParsedModelDocument: Hashable {
    var entities: [EntityNode]
    var configurations: [ModelConfiguration]
    var lastSavedToolsVersion: String?
    var documentVersion: String?
}

// MARK: - Whole model (document + versions)

struct GraphDocument: Hashable {
    var name: String
    var rootURL: URL                    // what the user opened
    var versions: [ModelVersion]        // empty for single-file models
    var currentVersion: ModelVersion?
    var document: ParsedModelDocument
}

// MARK: - Node metrics (shared by layout + rendering so anchors line up)

enum NodeMetrics {
    /// Global UI scale from AppSettings (Settings window). Applied at launch.
    static var scale: CGFloat = 1.0

    static var width: CGFloat { 218 * scale }
    static var headerHeight: CGFloat { 26 * scale }
    static var rowHeight: CGFloat { 16 * scale }
    static var sectionPad: CGFloat { 4 * scale }
    static var bottomPad: CGFloat { 5 * scale }
    static var moreRowHeight: CGFloat { 13 * scale }
    static let collapsedAttrRows = 8
    static let collapsedRelRows = 6

    /// Scaled font size helper
    static func font(_ base: CGFloat) -> CGFloat {
        (base * scale * 10).rounded() / 10
    }

    /// Xcode-style: everything expanded by default; `collapsed` set limits rows.
    static func size(for node: EntityNode, collapsed: Bool) -> CGSize {
        let attrTotal = node.attributes.count
        let relTotal = node.relationships.count
        let attrRows = collapsed ? min(attrTotal, collapsedAttrRows) : attrTotal
        let relRows = collapsed ? min(relTotal, collapsedRelRows) : relTotal

        var h: CGFloat = headerHeight
        if attrRows > 0 {
            h += sectionPad + CGFloat(attrRows) * rowHeight + sectionPad
            if collapsed && attrTotal > collapsedAttrRows { h += moreRowHeight }
        }
        if relRows > 0 {
            if attrRows > 0 { h += 1 } // divider
            h += sectionPad + CGFloat(relRows) * rowHeight + sectionPad
            if collapsed && relTotal > collapsedRelRows { h += moreRowHeight }
        }
        h += bottomPad
        return CGSize(width: width, height: h)
    }

    /// Y offset (relative to card CENTER) of the row for `relName` in the
    /// relationships section. Lines attach to the exact row, like Xcode.
    static func relRowOffset(in node: EntityNode, relName: String, collapsed: Bool) -> CGFloat {
        guard !relName.isEmpty else { return 0 }
        let size = size(for: node, collapsed: collapsed)
        var y: CGFloat = -size.height / 2 + headerHeight
        if !node.attributes.isEmpty {
            let attrTotal = node.attributes.count
            let attrRows = collapsed ? min(attrTotal, collapsedAttrRows) : attrTotal
            y += sectionPad + CGFloat(attrRows) * rowHeight + sectionPad
            if collapsed && attrTotal > collapsedAttrRows { y += moreRowHeight }
            y += 1 // divider
        }
        y += sectionPad
        guard let idx = node.relationships.firstIndex(where: { $0.name == relName }) else {
            return 0
        }
        if collapsed && idx >= collapsedRelRows {
            // hidden behind "+N" row → attach there
            return y + CGFloat(collapsedRelRows) * rowHeight + moreRowHeight / 2
        }
        return y + CGFloat(idx) * rowHeight + rowHeight / 2
    }
}
