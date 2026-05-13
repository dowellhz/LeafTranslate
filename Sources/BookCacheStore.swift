import CryptoKit
import Foundation

enum BookCacheStore {
    static func bookHash(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = Insecure.MD5()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func cacheDirectory(for bookHash: String) throws -> URL {
        let root = try cacheRootDirectory()
        return root.appendingPathComponent(bookHash, isDirectory: true)
    }

    static func hasCache(at directory: URL) -> Bool {
        cacheFileCount(at: directory) > 0
    }

    static func cacheFileCount(at directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        return enumerator.reduce(0) { count, item in
            guard let url = item as? URL else { return count }
            return count + (url.pathExtension.lowercased() == "json" ? 1 : 0)
        }
    }

    @discardableResult
    static func clearCache(for bookHash: String) throws -> Int {
        let directory = try cacheDirectory(for: bookHash)
        let removedCount = cacheFileCount(at: directory)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        return removedCount
    }

    private static func cacheRootDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("LeafTranslate", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
