import Foundation

enum LeafTranslatePaths {
    static func temporaryTranslatedPDFURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafTranslate", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
            .appendingPathComponent("translated-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
    }
}
