//
//  ModelDiffer.swift
//  CoreDataGraph
//
//  Compares two versions of a model (old → new).
//

import Foundation

struct AttributeChange: Hashable {
    var name: String
    var old: AttributeInfo?
    var new: AttributeInfo?
    var detail: String
}

struct RelationshipChange: Hashable {
    var name: String
    var old: RelationshipInfo?
    var new: RelationshipInfo?
    var detail: String
}

struct EntityChange: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var addedAttributes: [AttributeChange]
    var removedAttributes: [AttributeChange]
    var changedAttributes: [AttributeChange]
    var addedRelationships: [RelationshipChange]
    var removedRelationships: [RelationshipChange]
    var changedRelationships: [RelationshipChange]

    var isEmpty: Bool {
        addedAttributes.isEmpty && removedAttributes.isEmpty && changedAttributes.isEmpty &&
        addedRelationships.isEmpty && removedRelationships.isEmpty && changedRelationships.isEmpty
    }
}

struct ModelDiff: Hashable {
    var oldVersionName: String
    var newVersionName: String
    var addedEntities: [String]
    var removedEntities: [String]
    var changedEntities: [EntityChange]

    var totalChanges: Int {
        addedEntities.count + removedEntities.count + changedEntities.reduce(0) { sum, c in
            sum + c.addedAttributes.count + c.removedAttributes.count + c.changedAttributes.count +
                  c.addedRelationships.count + c.removedRelationships.count + c.changedRelationships.count
        }
    }

    var summary: String {
        var parts: [String] = []
        if !addedEntities.isEmpty { parts.append("+\(addedEntities.count) 实体") }
        if !removedEntities.isEmpty { parts.append("-\(removedEntities.count) 实体") }
        if !changedEntities.isEmpty { parts.append("~\(changedEntities.count) 实体") }
        return parts.isEmpty ? "无变化" : parts.joined(separator: ", ")
    }
}

enum ModelDiffer {

    /// old → new
    static func diff(old: ParsedModelDocument, oldName: String,
                     new: ParsedModelDocument, newName: String) -> ModelDiff {

        let oldByName = Dictionary(uniqueKeysWithValues: old.entities.map { ($0.name, $0) })
        let newByName = Dictionary(uniqueKeysWithValues: new.entities.map { ($0.name, $0) })

        let added = newByName.keys.filter { oldByName[$0] == nil }.sorted()
        let removed = oldByName.keys.filter { newByName[$0] == nil }.sorted()

        var changed: [EntityChange] = []
        for name in oldByName.keys.sorted() where newByName[name] != nil {
            if let change = diffEntity(old: oldByName[name]!, new: newByName[name]!) {
                changed.append(change)
            }
        }

        return ModelDiff(oldVersionName: oldName, newVersionName: newName,
                         addedEntities: added, removedEntities: removed, changedEntities: changed)
    }

    private static func diffEntity(old: EntityNode, new: EntityNode) -> EntityChange? {
        let oldAttrs = Dictionary(uniqueKeysWithValues: old.attributes.map { ($0.name, $0) })
        let newAttrs = Dictionary(uniqueKeysWithValues: new.attributes.map { ($0.name, $0) })

        var addedAttrs: [AttributeChange] = []
        var removedAttrs: [AttributeChange] = []
        var changedAttrs: [AttributeChange] = []

        for name in newAttrs.keys.sorted() {
            guard let o = oldAttrs[name] else {
                addedAttrs.append(AttributeChange(name: name, old: nil, new: newAttrs[name], detail: "新增 \(newAttrs[name]!.type)"))
                continue
            }
            let n = newAttrs[name]!
            var details: [String] = []
            if o.type != n.type { details.append("类型 \(o.type)→\(n.type)") }
            if o.isOptional != n.isOptional { details.append(n.isOptional ? "变为 Optional" : "变为 Required") }
            if o.defaultValue != n.defaultValue { details.append("默认值 \(o.defaultValue ?? "nil")→\(n.defaultValue ?? "nil")") }
            if o.valueTransformer != n.valueTransformer { details.append("Transformer 变化") }
            if o.customClassName != n.customClassName { details.append("类 \(o.customClassName ?? "nil")→\(n.customClassName ?? "nil")") }
            if !details.isEmpty {
                changedAttrs.append(AttributeChange(name: name, old: o, new: n, detail: details.joined(separator: ", ")))
            }
        }
        for name in oldAttrs.keys.sorted() where newAttrs[name] == nil {
            removedAttrs.append(AttributeChange(name: name, old: oldAttrs[name], new: nil, detail: "删除"))
        }

        let oldRels = Dictionary(uniqueKeysWithValues: old.relationships.map { ($0.name, $0) })
        let newRels = Dictionary(uniqueKeysWithValues: new.relationships.map { ($0.name, $0) })

        var addedRels: [RelationshipChange] = []
        var removedRels: [RelationshipChange] = []
        var changedRels: [RelationshipChange] = []

        for name in newRels.keys.sorted() {
            guard let o = oldRels[name] else {
                addedRels.append(RelationshipChange(name: name, old: nil, new: newRels[name],
                                                    detail: "新增 → \(newRels[name]!.destinationEntity)"))
                continue
            }
            let n = newRels[name]!
            var details: [String] = []
            if o.destinationEntity != n.destinationEntity { details.append("目标 \(o.destinationEntity)→\(n.destinationEntity)") }
            if o.deletionRule != n.deletionRule { details.append("规则 \(o.deletionRule)→\(n.deletionRule)") }
            if o.isToMany != n.isToMany { details.append(n.isToMany ? "变为 To-Many" : "变为 To-One") }
            if o.isOptional != n.isOptional { details.append(n.isOptional ? "变为 Optional" : "变为 Required") }
            if o.inverseName != n.inverseName { details.append("Inverse \(o.inverseName ?? "nil")→\(n.inverseName ?? "nil")") }
            if !details.isEmpty {
                changedRels.append(RelationshipChange(name: name, old: o, new: n, detail: details.joined(separator: ", ")))
            }
        }
        for name in oldRels.keys.sorted() where newRels[name] == nil {
            removedRels.append(RelationshipChange(name: name, old: oldRels[name], new: nil, detail: "删除"))
        }

        let change = EntityChange(name: new.name,
                                  addedAttributes: addedAttrs,
                                  removedAttributes: removedAttrs,
                                  changedAttributes: changedAttrs,
                                  addedRelationships: addedRels,
                                  removedRelationships: removedRels,
                                  changedRelationships: changedRels)
        return change.isEmpty ? nil : change
    }

    /// Per-entity diff status for graph coloring (relative to `diff`)
    static func entityStatus(_ name: String, in diff: ModelDiff) -> DiffStatus {
        if diff.addedEntities.contains(name) { return .added }
        if diff.removedEntities.contains(name) { return .removed }
        if diff.changedEntities.contains(where: { $0.name == name }) { return .changed }
        return .none
    }
}
