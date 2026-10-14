//
//  ModelLoader.swift
//  CoreDataGraph
//
//  Resolves whatever URL the user opens:
//   - .xcdatamodeld bundle (reads .xccurrentversion, enumerates versions)
//   - .xcdatamodel directory
//   - raw `contents` XML file
//   - compiled .mom / .momd (fallback via NSManagedObjectModel)
//

import Foundation
import CoreData
import UniformTypeIdentifiers

enum ModelLoadError: LocalizedError {
    case unreadable(String)
    case noEntities(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "无法读取模型文件:\n\(path)"
        case .noEntities(let path):
            return "未在以下位置找到 Core Data 模型内容:\n\(path)"
        }
    }
}

enum ModelLoader {

    /// Open any supported URL and build the full document (all versions + current parsed doc)
    static func load(url: URL) throws -> GraphDocument {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ModelLoadError.unreadable(url.path)
        }

        let ext = url.pathExtension.lowercased()

        // 1. .xcdatamodeld bundle
        if isDir.boolValue && ext == "xcdatamodeld" {
            let versions = try enumerateVersions(in: url)
            guard let current = versions.first(where: { $0.isCurrent }) ?? versions.last else {
                throw ModelLoadError.noEntities(url.path)
            }
            let doc = try parseVersion(current)
            return GraphDocument(name: url.deletingPathExtension().lastPathComponent,
                                 rootURL: url,
                                 versions: versions,
                                 currentVersion: current,
                                 document: doc)
        }

        // 2. .xcdatamodel directory
        if isDir.boolValue && ext == "xcdatamodel" {
            let version = ModelVersion(name: url.deletingPathExtension().lastPathComponent,
                                       url: url, isCurrent: true)
            let doc = try parseVersion(version)
            return GraphDocument(name: url.deletingPathExtension().lastPathComponent,
                                 rootURL: url,
                                 versions: [version],
                                 currentVersion: version,
                                 document: doc)
        }

        // 3. Plain directory that contains .xcdatamodel children
        if isDir.boolValue {
            let versions = try enumerateVersions(in: url)
            if !versions.isEmpty {
                let current = versions.first(where: { $0.isCurrent }) ?? versions[versions.count - 1]
                let doc = try parseVersion(current)
                return GraphDocument(name: url.lastPathComponent,
                                     rootURL: url,
                                     versions: versions,
                                     currentVersion: current,
                                     document: doc)
            }
        }

        // 4. File: `contents` XML
        if !isDir.boolValue && (ext.isEmpty || ext == "xml" || url.lastPathComponent == "contents") {
            guard let result = ContentsXMLParser.parse(contentsOf: url) else {
                throw ModelLoadError.unreadable(url.path)
            }
            let doc = ParsedModelDocument(entities: result.entities,
                                          configurations: result.configurations,
                                          lastSavedToolsVersion: result.lastSavedToolsVersion,
                                          documentVersion: result.documentVersion)
            let version = ModelVersion(name: url.lastPathComponent, url: url, isCurrent: true)
            return GraphDocument(name: url.deletingLastPathComponent().deletingPathExtension().lastPathComponent,
                                 rootURL: url,
                                 versions: [version],
                                 currentVersion: version,
                                 document: doc)
        }

        // 5. Compiled .mom / .momd
        if ext == "mom" || ext == "momd" {
            guard let mom = NSManagedObjectModel(contentsOf: url) else {
                throw ModelLoadError.unreadable(url.path)
            }
            let doc = ParsedModelDocument(entities: convert(mom),
                                          configurations: [],
                                          lastSavedToolsVersion: nil,
                                          documentVersion: nil)
            let version = ModelVersion(name: url.lastPathComponent, url: url, isCurrent: true)
            return GraphDocument(name: url.deletingPathExtension().lastPathComponent,
                                 rootURL: url,
                                 versions: [version],
                                 currentVersion: version,
                                 document: doc)
        }

        throw ModelLoadError.noEntities(url.path)
    }

    // MARK: - Versions

    static func enumerateVersions(in modeldURL: URL) throws -> [ModelVersion] {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(at: modeldURL,
                                                    includingPropertiesForKeys: nil)) ?? []
        let modelDirs = children.filter { $0.pathExtension == "xcdatamodel" }

        var currentName: String?
        let currentVersionURL = modeldURL.appendingPathComponent(".xccurrentversion")
        if let plist = NSDictionary(contentsOf: currentVersionURL) {
            currentName = plist["_XCCurrentVersionName"] as? String
        }

        var versions: [ModelVersion] = modelDirs.map { dir in
            ModelVersion(name: dir.deletingPathExtension().lastPathComponent,
                         url: dir,
                         isCurrent: dir.lastPathComponent == currentName)
        }
        versions.sort { lhs, rhs in
            let li = lhs.sortIndex, ri = rhs.sortIndex
            if li != ri && li >= 0 && ri >= 0 { return li < ri }
            return lhs.name < rhs.name
        }
        return versions
    }

    static func parseVersion(_ version: ModelVersion) throws -> ParsedModelDocument {
        let contentsURL: URL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: version.url.path, isDirectory: &isDir), isDir.boolValue {
            contentsURL = version.url.appendingPathComponent("contents")
        } else {
            contentsURL = version.url
        }

        if let result = ContentsXMLParser.parse(contentsOf: contentsURL) {
            return ParsedModelDocument(entities: result.entities,
                                       configurations: result.configurations,
                                       lastSavedToolsVersion: result.lastSavedToolsVersion,
                                       documentVersion: result.documentVersion)
        }

        // Fallback: compiled model or NSManagedObjectModel parsing
        if let mom = NSManagedObjectModel(contentsOf: contentsURL) {
            return ParsedModelDocument(entities: convert(mom),
                                       configurations: [],
                                       lastSavedToolsVersion: nil,
                                       documentVersion: nil)
        }
        throw ModelLoadError.unreadable(contentsURL.path)
    }

    // MARK: - NSManagedObjectModel → EntityNode (fallback path)

    static func convert(_ mom: NSManagedObjectModel) -> [EntityNode] {
        let allEntities: [NSEntityDescription] = mom.entitiesByName.values.sorted { ($0.name ?? "") < ($1.name ?? "") }
        return allEntities.map { entity in
            let attrs: [AttributeInfo] = entity.attributesByName.map { name, desc in
                AttributeInfo(name: name,
                              type: attributeName(for: desc.attributeType),
                              isOptional: desc.isOptional,
                              isTransient: desc.isTransient,
                              defaultValue: desc.defaultValue.map { "\($0)" },
                              customClassName: nil,
                              valueTransformer: desc.valueTransformerName,
                              usesScalarValueType: false,
                              versionHashModifier: desc.versionHashModifier,
                              isIndexed: false,
                              isSpotlightIndexed: false)
            }.sorted { $0.name < $1.name }

            let rels: [RelationshipInfo] = entity.relationshipsByName.map { name, rel in
                let maxC = rel.maxCount == 0 ? nil : Int(rel.maxCount)
                let inv: NSRelationshipDescription? = rel.inverseRelationship
                let invEntity: NSEntityDescription? = inv?.entity
                return RelationshipInfo(name: name,
                                        destinationEntity: rel.destinationEntity?.name ?? "",
                                        inverseName: inv?.name,
                                        inverseEntity: invEntity?.name,
                                        isToMany: rel.isToMany,
                                        isOrdered: rel.isOrdered,
                                        isOptional: rel.isOptional,
                                        isTransient: rel.isTransient,
                                        minCount: Int(rel.minCount),
                                        maxCount: maxC,
                                        deletionRule: deleteRuleName(rel.deleteRule))
            }.sorted { $0.name < $1.name }

            let constraints: [[String]] = entity.uniquenessConstraints.map { group in
                group.compactMap { ($0 as? NSAttributeDescription)?.name }
            }

            var node = EntityNode(
                name: entity.name ?? "Unknown",
                representedClassName: entity.managedObjectClassName,
                codeGenerationType: nil,
                isAbstract: entity.isAbstract,
                parentEntity: entity.superentity?.name,
                isSyncable: true,
                versionHashModifier: entity.versionHashModifier,
                attributes: attrs,
                relationships: rels,
                uniquenessConstraints: constraints,
                fetchIndices: [])
            node.size = CGSize(width: NodeMetrics.width, height: 60)
            return node
        }
    }

    private static func attributeName(for type: NSAttributeType) -> String {
        switch type {
        case .undefinedAttributeType: return "Undefined"
        case .integer16AttributeType: return "Integer 16"
        case .integer32AttributeType: return "Integer 32"
        case .integer64AttributeType: return "Integer 64"
        case .decimalAttributeType: return "Decimal"
        case .doubleAttributeType: return "Double"
        case .floatAttributeType: return "Float"
        case .stringAttributeType: return "String"
        case .booleanAttributeType: return "Boolean"
        case .dateAttributeType: return "Date"
        case .binaryDataAttributeType: return "Binary"
        case .UUIDAttributeType: return "UUID"
        case .URIAttributeType: return "URI"
        case .transformableAttributeType: return "Transformable"
        default: return "Unknown"
        }
    }

    private static func deleteRuleName(_ rule: NSDeleteRule) -> String {
        switch rule {
        case .noActionDeleteRule: return "No Action"
        case .nullifyDeleteRule: return "Nullify"
        case .cascadeDeleteRule: return "Cascade"
        case .denyDeleteRule: return "Deny"
        @unknown default: return "Unknown"
        }
    }
}
