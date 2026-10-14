//
//  RecentFilesStore.swift
//  CoreDataGraph
//
//  Recent models persisted as security-scoped bookmarks (sandbox friendly).
//

import Foundation
import Observation
import AppKit

struct RecentItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let bookmark: Data

    /// Resolve without entering the scope (for display)
    var displayURL: URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}

@Observable
final class RecentFilesStore {

    static let shared = RecentFilesStore()

    private let key = "recentModelBookmarks"
    private let lastKey = "lastOpenedBookmarkID"
    private let maxItems = 10
    private(set) var items: [RecentItem] = []

    private init() {
        load()
    }

    func add(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { return }
        let name: String
        if url.pathExtension == "xcdatamodeld" {
            name = url.deletingPathExtension().lastPathComponent
        } else {
            name = url.lastPathComponent
        }
        items.removeAll { $0.name == name }
        items.insert(RecentItem(id: UUID(), name: name, bookmark: bookmark), at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        save()
    }

    func remove(_ item: RecentItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    // MARK: Last opened (auto restore on launch)

    func markLastOpened(_ url: URL) {
        if let match = items.first(where: { resolveSilently($0)?.path == url.path }) {
            UserDefaults.standard.set(match.id.uuidString, forKey: lastKey)
        }
    }

    var lastOpenedItem: RecentItem? {
        guard let idString = UserDefaults.standard.string(forKey: lastKey),
              let id = UUID(uuidString: idString) else { return nil }
        return items.first { $0.id == id }
    }

    private func resolveSilently(_ item: RecentItem) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: item.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Resolve bookmark and enter security scope. Caller must keep URL while in use.
    func resolve(_ item: RecentItem) -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else { return nil }
        if isStale {
            // Refresh bookmark
            if let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                 includingResourceValuesForKeys: nil,
                                                 relativeTo: nil) {
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx] = RecentItem(id: item.id, name: item.name, bookmark: fresh)
                    save()
                }
            }
        }
        return url
    }

    // MARK: Persistence

    private func save() {
        let encoded = items.map { ["id": $0.id.uuidString, "name": $0.name] }
        // Store bookmarks separately (Data not plist-friendly inline in mixed dict)
        let bookmarkData = items.map { $0.bookmark }
        UserDefaults.standard.set(encoded, forKey: key)
        UserDefaults.standard.set(bookmarkData, forKey: key + ".bookmarks")
    }

    private func load() {
        guard let encoded = UserDefaults.standard.array(forKey: key) as? [[String: String]],
              let bookmarks = UserDefaults.standard.array(forKey: key + ".bookmarks") as? [Data] else { return }
        items = zip(encoded, bookmarks).compactMap { dict, data in
            guard let idString = dict["id"], let id = UUID(uuidString: idString),
                  let name = dict["name"] else { return nil }
            return RecentItem(id: id, name: name, bookmark: data)
        }
    }
}
