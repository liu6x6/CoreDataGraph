//
//  OpenRouter.swift
//  CoreDataGraph
//
//  Routes file-open requests (Finder double-click / `open -a` / AppleEvents)
//  to the currently active window's view model, or queues them until a
//  window appears.
//

import Foundation

final class OpenRouter {

    static let shared = OpenRouter()

    /// The view model of the frontmost window (registered on appear/focus).
    weak var activeViewModel: GraphViewModel?

    /// URL waiting for the first window to appear.
    var pendingURL: URL?

    private init() {}

    func requestOpen(_ url: URL) {
        if let vm = activeViewModel {
            vm.open(url: url)
        } else {
            pendingURL = url
        }
    }
}
