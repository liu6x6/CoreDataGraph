//
//  PositionStore.swift
//  CoreDataGraph
//
//  Persists user-adjusted card positions per (model root URL, version),
//  so a manually arranged graph is restored exactly on next launch.
//

import Foundation
import CoreGraphics

enum PositionStore {

    private static let defaultsKey = "customLayoutPositions.v1"

    private static func storeKey(root: URL, version: String?) -> String {
        root.path + "#" + (version ?? "-")
    }

    private static func readAll() -> [String: [String: [Double]]] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String: [Double]]] ?? [:]
    }

    static func save(_ positions: [String: CGPoint], root: URL, version: String?) {
        guard !positions.isEmpty else { return }
        var all = readAll()
        var entry: [String: [Double]] = [:]
        for (name, p) in positions {
            entry[name] = [Double(p.x), Double(p.y)]
        }
        all[storeKey(root: root, version: version)] = entry
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }

    static func load(root: URL, version: String?) -> [String: CGPoint]? {
        guard let entry = readAll()[storeKey(root: root, version: version)], !entry.isEmpty else {
            return nil
        }
        var result: [String: CGPoint] = [:]
        for (name, xy) in entry where xy.count == 2 {
            result[name] = CGPoint(x: xy[0], y: xy[1])
        }
        return result.isEmpty ? nil : result
    }

    static func clear(root: URL, version: String?) {
        var all = readAll()
        all.removeValue(forKey: storeKey(root: root, version: version))
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }

    static func hasCustomLayout(root: URL, version: String?) -> Bool {
        load(root: root, version: version) != nil
    }
}
