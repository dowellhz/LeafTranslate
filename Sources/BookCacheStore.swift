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
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return contents.contains { $0.pathExtension.lowercased() == "json" }
    }

    static func clearCache(for bookHash: String) throws {
        let directory = try cacheDirectory(for: bookHash)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
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
