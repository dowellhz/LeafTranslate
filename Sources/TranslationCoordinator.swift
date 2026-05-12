import Foundation

final class TranslationCoordinator {
    private var currentTask: TranslationTask?

    var isRunning: Bool {
        currentTask != nil
    }

    func cancel() {
        currentTask?.cancel()
    }

    func translate(
        inputURL: URL,
        scriptURL: URL,
        settings: TranslationSettings,
        pageRange: (start: Int, end: Int, limit: Int),
        progress: @escaping (String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let task = TranslationTask()
        currentTask = task

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let outputURL = try LeafTranslatePaths.temporaryTranslatedPDFURL()
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try PDFTranslationRunner.run(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    scriptURL: scriptURL,
                    settings: settings.asDictionary,
                    startPage: pageRange.start,
                    pageLimit: pageRange.limit,
                    task: task,
                    progress: progress
                )
                self?.finish(task: task) {
                    completion(.success(outputURL))
                }
            } catch {
                self?.finish(task: task) {
                    completion(.failure(error))
                }
            }
        }
    }

    private func finish(task: TranslationTask, completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard self?.currentTask === task else { return }
            self?.currentTask = nil
            completion()
        }
    }
}
