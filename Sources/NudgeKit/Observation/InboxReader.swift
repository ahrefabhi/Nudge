import Foundation
import NudgeHookSchema

/// Drains committed collector records from the inbox, oldest first, deleting each one it reads.
/// Files that are not plain, owned, small JSON records are removed unread.
public struct InboxReader: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func prepare() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    public func drain() -> [HookRecord] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        var records: [HookRecord] = []
        // Names start with a millisecond timestamp, so name order is arrival order.
        for name in names.sorted() where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = directory.appending(path: name)
            defer { try? FileManager.default.removeItem(at: url) }
            guard SafeFile.isOwnedRegularFile(url, maximumBytes: HookRecord.maximumBytes),
                  let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(HookRecord.self, from: data),
                  record.schema == HookRecord.currentSchema else { continue }
            records.append(record)
        }
        return records
    }
}

/// Calls `onChange` on `queue` whenever entries in `directory` change, or, given a file, whenever
/// the file is written. File events are only a wake-up hint; readers always rescan.
final class DirectoryWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject?

    init?(directory: URL, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete], queue: queue)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    deinit { source?.cancel() }
}
