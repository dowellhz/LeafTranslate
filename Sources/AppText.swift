import Foundation

enum AppText {
    static var usesChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    static var openPDF: String { usesChinese ? "打开 PDF" : "Open PDF" }
    static var translate: String { usesChinese ? "翻译" : "Translate" }
    static var cancel: String { usesChinese ? "取消" : "Cancel" }
    static var clearCache: String { usesChinese ? "清除缓存" : "Clear Cache" }
    static var exportBilingual: String { usesChinese ? "导出双语" : "Export Bilingual" }
    static var exportTranslationOnly: String { usesChinese ? "导出仅翻译" : "Translation Only" }
    static var previousPage: String { usesChinese ? "‹  上一页" : "‹  Prev" }
    static var nextPage: String { usesChinese ? "下一页  ›" : "Next  ›" }
    static var search: String { usesChinese ? "搜索" : "Search" }

    static var provider: String { usesChinese ? "模型" : "Provider" }
    static var endpoint: String { usesChinese ? "LLM / Azure 地址" : "LLM / Azure URL" }
    static var model: String { usesChinese ? "模型 / Azure 部署名" : "Model / Azure deployment" }
    static var token: String { usesChinese ? "Token" : "Token" }
    static var targetLanguage: String { usesChinese ? "目标语言" : "Target language" }
    static var pages: String { usesChinese ? "页码" : "Pages" }
    static var to: String { usesChinese ? "到" : "to" }
    static var initialStatus: String { usesChinese ? "打开 PDF 后开始。" : "Open a PDF to begin." }
    static var translatedFileName: String { usesChinese ? "翻译.pdf" : "translated.pdf" }

    static func unableToPrepareCache(_ message: String) -> String {
        usesChinese ? "无法准备缓存：\(message)" : "Unable to prepare cache: \(message)"
    }

    static func loadedPages(_ pageCount: Int) -> String {
        usesChinese
            ? "已加载 \(pageCount) 页。尚未解析。将翻译第 1-\(pageCount) 页。"
            : "Loaded \(pageCount) pages. No parsing yet. Translation will process pages 1-\(pageCount)."
    }

    static func generatingPages(start: Int, end: Int) -> String {
        usesChinese
            ? "正在生成第 \(start)-\(end) 页的翻译 PDF..."
            : "Generating translated PDF for pages \(start)-\(end)..."
    }

    static func translationComplete(_ path: String) -> String {
        usesChinese ? "翻译完成，已保存到 \(path)" : "Translation complete. Saved to \(path)"
    }

    static func exported(_ path: String) -> String {
        usesChinese ? "已导出到 \(path)" : "Exported to \(path)"
    }

    static var unableToExportPDF: String {
        usesChinese ? "无法导出 PDF。" : "Unable to export PDF."
    }

    static var noTranslationPages: String {
        usesChinese ? "没有找到可导出的翻译页。" : "No translated pages found to export."
    }

    static var unableToOpenPDF: String { usesChinese ? "无法打开 PDF。" : "Unable to open PDF." }
    static var tokenEmpty: String { usesChinese ? "Token 为空。" : "Token is empty." }
    static var missingTranslatorScript: String { usesChinese ? "找不到 translate_pdf.py。" : "Unable to locate translate_pdf.py." }
    static var cancellingTranslation: String { usesChinese ? "正在取消翻译..." : "Cancelling translation..." }
    static func cacheCleared(_ count: Int) -> String {
        usesChinese ? "已清除这本书的 \(count) 个缓存文件。" : "Cleared \(count) cache files for this book."
    }
    static var positivePageRange: String { usesChinese ? "页码必须使用正数。" : "Page range must use positive numbers." }
    static var startBeforeEnd: String { usesChinese ? "起始页必须小于或等于结束页。" : "Start page must be less than or equal to end page." }
    static var startOutsidePDF: String { usesChinese ? "起始页超出 PDF 范围。" : "Start page is outside the PDF." }

    static func translatedPage(_ page: Int) -> String {
        usesChinese ? "已翻译第 \(page) 页。" : "Translated page \(page)."
    }

    static func pageTranslationReceived(_ page: Int) -> String {
        usesChinese ? "第 \(page) 页翻译已返回，正在按页序写入 PDF..." : "Page \(page) translation received; writing PDF in page order..."
    }

    static func pageLoadedFromCache(_ page: Int) -> String {
        usesChinese ? "第 \(page) 页已从缓存读取。" : "Page \(page) loaded from cache."
    }

    static func warningPage(_ page: Int, message: String) -> String {
        usesChinese ? "第 \(page) 页警告：\(message)" : "Warning page \(page): \(message)"
    }

    static func pageFallback(_ page: Int) -> String {
        usesChinese ? "第 \(page) 页需要拆成更小片段，正在自动重试..." : "Page \(page) needs smaller chunks; retrying automatically..."
    }
}
