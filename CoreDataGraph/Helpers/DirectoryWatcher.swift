//
//  DirectoryWatcher.swift
//  CoreDataGraph
//
//  Watches a directory/file for changes using a GCD file-system source.
//  Used to auto-refresh when Xcode saves the model.
//

import Foundation

final class DirectoryWatcher {

    private var source: DispatchSourceFileSystemObject?
    private let fd: Int32
    private let url: URL

    init?(url: URL, handler: @escaping @Sendable () -> Void) {
        fd = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.url = url

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: DispatchQueue.global(qos: .utility))
        src.setEventHandler {
            handler()
        }
        let fdCopy = fd
        src.setCancelHandler {
            close(fdCopy)
        }
        src.resume()
        source = src
    }

    deinit {
        source?.cancel()
    }
}
