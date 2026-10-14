//
//  ContentsXMLParser.swift
//  CoreDataGraph
//
//  Parses the `contents` XML file of a .xcdatamodel directly.
//  This gives us everything: entities, attributes, relationships,
//  fetch indices, uniqueness constraints AND the <elements> section
//  which stores the graph editor positions saved by old Xcode versions.
//

import Foundation
import CoreGraphics

final class ContentsXMLParser: NSObject, XMLParserDelegate {

    struct Result {
        var entities: [EntityNode]
        var configurations: [ModelConfiguration]
        var elements: [String: CGRect]      // saved editor frames by entity name
        var lastSavedToolsVersion: String?
        var documentVersion: String?
    }

    private var entities: [EntityNode] = []
    private var configurations: [ModelConfiguration] = []
    private var elements: [String: CGRect] = [:]
    private var lastSavedToolsVersion: String?
    private var documentVersion: String?

    // Parsing state
    private var currentEntity: EntityNode?
    private var currentFetchIndex: FetchIndexInfo?
    private var currentConfig: ModelConfiguration?
    private var currentConstraint: [String]?
    private var capturingCharacters = false
    private var capturedCharacters = ""
    private var userInfoDepth = 0
    private var inElements = false

    static func parse(data: Data) -> Result? {
        let parser = ContentsXMLParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse(), !parser.entities.isEmpty || !parser.configurations.isEmpty else {
            return nil
        }
        // Apply saved positions
        for i in parser.entities.indices {
            if let rect = parser.elements[parser.entities[i].name] {
                let center = CGPoint(x: rect.midX, y: rect.midY)
                parser.entities[i].savedPosition = center
                parser.entities[i].position = center
                parser.entities[i].size = rect.size
            }
        }
        return Result(
            entities: parser.entities,
            configurations: parser.configurations,
            elements: parser.elements,
            lastSavedToolsVersion: parser.lastSavedToolsVersion,
            documentVersion: parser.documentVersion
        )
    }

    static func parse(contentsOf url: URL) -> Result? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attrs: [String: String] = [:]) {

        if userInfoDepth > 0 {
            userInfoDepth += 1
            return
        }

        switch elementName {
        case "model":
            documentVersion = attrs["documentVersion"]
            lastSavedToolsVersion = attrs["lastSavedToolsVersion"]

        case "entity":
            guard let name = attrs["name"] else { return }
            var node = EntityNode(
                name: name,
                representedClassName: attrs["representedClassName"],
                codeGenerationType: attrs["codeGenerationType"],
                isAbstract: attrs["isAbstract"] == "YES",
                parentEntity: attrs["parentEntity"],
                isSyncable: attrs["syncable"] == "YES",
                versionHashModifier: attrs["versionHashModifier"],
                attributes: [],
                relationships: [],
                uniquenessConstraints: [],
                fetchIndices: [])
            node.size = CGSize(width: NodeMetrics.width, height: 60)
            currentEntity = node

        case "attribute":
            guard var entity = currentEntity, let name = attrs["name"] else { return }
            let info = AttributeInfo(
                name: name,
                type: attrs["attributeType"] ?? "Undefined",
                isOptional: attrs["optional"] == "YES",
                isTransient: attrs["transient"] == "YES",
                defaultValue: attrs["defaultValueString"],
                customClassName: attrs["customClassName"],
                valueTransformer: attrs["valueTransformerName"],
                usesScalarValueType: attrs["usesScalarValueType"] == "YES",
                versionHashModifier: attrs["versionHashModifier"],
                isIndexed: attrs["indexed"] == "YES",
                isSpotlightIndexed: attrs["spotlightIndexingEnabled"] == "YES")
            entity.attributes.append(info)
            currentEntity = entity

        case "relationship":
            guard var entity = currentEntity, let name = attrs["name"] else { return }
            let isToMany = attrs["toMany"] == "YES"
            let info = RelationshipInfo(
                name: name,
                destinationEntity: attrs["destinationEntity"] ?? "",
                inverseName: attrs["inverseName"],
                inverseEntity: attrs["inverseEntity"],
                isToMany: isToMany,
                isOrdered: attrs["isOrdered"] == "YES",
                isOptional: attrs["optional"] == "YES",
                isTransient: attrs["transient"] == "YES",
                minCount: Int(attrs["minCount"] ?? "0") ?? 0,
                maxCount: attrs["maxCount"].flatMap(Int.init),
                deletionRule: attrs["deletionRule"] ?? "Nullify")
            entity.relationships.append(info)
            currentEntity = entity

        case "fetchIndex":
            currentFetchIndex = FetchIndexInfo(name: attrs["name"] ?? "index", elements: [])

        case "fetchIndexElement":
            guard var idx = currentFetchIndex else { return }
            idx.elements.append(FetchIndexElementInfo(
                property: attrs["property"] ?? "",
                order: attrs["order"] ?? "ascending",
                type: attrs["type"] ?? "Binary"))
            currentFetchIndex = idx

        case "uniquenessConstraints":
            break

        case "constraint":
            currentConstraint = []

        case "value":
            if currentConstraint != nil {
                capturingCharacters = true
                capturedCharacters = ""
            }

        case "configuration":
            currentConfig = ModelConfiguration(name: attrs["name"] ?? "Default", members: [])

        case "memberEntity":
            if var cfg = currentConfig, let name = attrs["name"] {
                cfg.members.append(name)
                currentConfig = cfg
            }

        case "elements":
            inElements = true

        case "element":
            guard inElements, let name = attrs["name"] else { return }
            let x = CGFloat(Double(attrs["positionX"] ?? "0") ?? 0)
            let y = CGFloat(Double(attrs["positionY"] ?? "0") ?? 0)
            let w = CGFloat(Double(attrs["width"] ?? "128") ?? 128)
            let h = CGFloat(Double(attrs["height"] ?? "60") ?? 60)
            elements[name] = CGRect(x: x, y: y, width: w, height: h)

        case "userInfo":
            userInfoDepth = 1

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingCharacters { capturedCharacters += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {

        if userInfoDepth > 0 {
            userInfoDepth -= 1
            return
        }

        switch elementName {
        case "entity":
            if let entity = currentEntity { entities.append(entity) }
            currentEntity = nil

        case "fetchIndex":
            if let idx = currentFetchIndex, var entity = currentEntity {
                entity.fetchIndices.append(idx)
                idx.elements.forEach { el in
                    for i in entity.attributes.indices where entity.attributes[i].name == el.property {
                        entity.attributes[i].isIndexed = true
                    }
                }
                currentEntity = entity
            }
            currentFetchIndex = nil

        case "constraint":
            if let constraint = currentConstraint, var entity = currentEntity {
                entity.uniquenessConstraints.append(constraint)
                currentEntity = entity
            }
            currentConstraint = nil

        case "value":
            if capturingCharacters {
                currentConstraint?.append(capturedCharacters.trimmingCharacters(in: .whitespacesAndNewlines))
                capturingCharacters = false
            }

        case "configuration":
            if let cfg = currentConfig { configurations.append(cfg) }
            currentConfig = nil

        case "elements":
            inElements = false

        default:
            break
        }
    }
}
