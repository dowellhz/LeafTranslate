import Foundation

enum PDFTranslationRunner {
    static func run(
        inputURL: URL,
        outputURL: URL,
        scriptURL: URL,
        settings: [String: Any],
        startPage: Int,
        pageLimit: Int,
        progress: @escaping (String) -> Void
    ) throws {
        let settingsURL = try writeTemporarySettings(settings)
        defer { try? FileManager.default.removeItem(at: settingsURL) }
        let logURL = try logFileURL()
        appendLog("=== Translation started \(Date()) ===\nInput: \(inputURL.path)\nOutput: \(outputURL.path)\n", to: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            scriptURL.path,
            inputURL.path,
            outputURL.path,
            settingsURL.path,
            "\(startPage)",
            "\(pageLimit)"
        ]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputBuffer = ProcessOutputBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            let chunk = String(data: data, encoding: .utf8) ?? ""
            appendLog(chunk, to: logURL)
            for line in outputBuffer.appendAndExtractLines(chunk) {
                if let message = progressMessage(from: line) {
                    progress(message)
                }
            }
        }

        try process.run()
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil

        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !stderr.isEmpty {
            appendLog("\n[stderr]\n\(stderr)\n", to: logURL)
        }
        appendLog("=== Translation finished status \(process.terminationStatus) ===\n\n", to: logURL)
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "LeafTranslate",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? outputBuffer.text : stderr]
            )
        }
    }

    private static func writeTemporarySettings(_ settings: [String: Any]) throws -> URL {
        let settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("leaftranslate-settings-\(UUID().uuidString)")
            .appendingPathExtension("json")
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        try data.write(to: settingsURL, options: .atomic)
        return settingsURL
    }

    static func logFileURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("LeafTranslate", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("translation.log")
    }

    private static func appendLog(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func progressMessage(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let page = payload["page"] as? Int,
              let status = payload["status"] as? String else {
            return nil
        }
        if status == "done" {
            return "Translated page \(page)."
        }
        if status == "warning" {
            let message = payload["message"] as? String ?? "Translation warning."
            return "Warning page \(page): \(message)"
        }
        if status == "fallback" {
            return "Page \(page) needs smaller chunks; retrying automatically..."
        }
        return nil
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var fullText = ""
    private var pendingLine = ""

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return fullText
    }

    func appendAndExtractLines(_ chunk: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        fullText += chunk
        pendingLine += chunk
        var lines = pendingLine.components(separatedBy: .newlines)
        pendingLine = lines.popLast() ?? ""
        return lines
    }
}
