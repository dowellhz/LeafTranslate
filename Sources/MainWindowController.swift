import Cocoa
import PDFKit

final class MainWindowController: NSWindowController, NSSplitViewDelegate, NSSearchFieldDelegate {
    private static let defaultStartPage = 10
    private static let defaultEndPage = 19

    private let openButton = NSButton(title: "Open PDF", target: nil, action: nil)
    private let translateButton = NSButton(title: "Translate", target: nil, action: nil)
    private let exportButton = NSButton(title: "Export PDF", target: nil, action: nil)
    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let endpointField = ShortcutTextField(string: AppSettings.endpoint)
    private let modelField = ShortcutTextField(string: AppSettings.model)
    private let tokenField = ShortcutSecureTextField(string: AppSettings.token)
    private let languageField = ShortcutTextField(string: AppSettings.targetLanguage)
    private let startPageField = ShortcutTextField(string: "\(MainWindowController.defaultStartPage)")
    private let endPageField = ShortcutTextField(string: "\(MainWindowController.defaultEndPage)")
    private let statusLabel = NSTextField(labelWithString: "Open a PDF to begin.")
    private let splitView = NSSplitView()
    private let sidebarShell = NSView()
    private let sidebar = NSView()
    private let sidebarToggleButton = NSButton(title: "‹", target: nil, action: nil)
    private let previewContainer = NSView()
    private let previewToolbar = NSView()
    private let bottomBar = NSView()
    private let pdfView = PDFView()
    private let zoomOutButton = NSButton(title: "-", target: nil, action: nil)
    private let zoomInButton = NSButton(title: "+", target: nil, action: nil)
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let pageLabel = NSTextField(labelWithString: "- / -")
    private let searchField = NSSearchField()
    private let previousButton = NSButton(title: "‹  Prev", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next  ›", target: nil, action: nil)

    private var inputPDFURL: URL?
    private var translatedPDFURL: URL?
    private var pageChangeObserver: NSObjectProtocol?
    private var searchSelections: [PDFSelection] = []
    private var searchSelectionIndex = 0
    private var didSetInitialSidebarWidth = false
    private var sidebarCollapsed = false
    private var expandedSidebarWidth: CGFloat = 320

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LeafTranslate"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let pageChangeObserver {
            NotificationCenter.default.removeObserver(pageChangeObserver)
        }
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1).cgColor

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false

        sidebarShell.wantsLayer = true
        sidebarShell.layer?.backgroundColor = NSColor.white.cgColor
        sidebarShell.translatesAutoresizingMaskIntoConstraints = false

        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.white.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.setFrameSize(NSSize(width: 320, height: 760))

        sidebarToggleButton.target = self
        sidebarToggleButton.action = #selector(toggleSidebar)
        sidebarToggleButton.bezelStyle = .regularSquare
        sidebarToggleButton.isBordered = false
        sidebarToggleButton.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        sidebarToggleButton.contentTintColor = .white
        sidebarToggleButton.wantsLayer = true
        sidebarToggleButton.layer?.backgroundColor = NSColor.systemRed.cgColor
        sidebarToggleButton.layer?.cornerRadius = 5
        sidebarToggleButton.translatesAutoresizingMaskIntoConstraints = false

        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1).cgColor
        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "LeafTranslate")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        openButton.target = self
        openButton.action = #selector(openPDF)
        translateButton.target = self
        translateButton.action = #selector(translatePDF)
        exportButton.target = self
        exportButton.action = #selector(exportPDF)
        translateButton.isEnabled = false
        exportButton.isEnabled = false

        for button in [openButton, translateButton, exportButton] {
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.translatesAutoresizingMaskIntoConstraints = false
        }

        let endpointLabel = fieldLabel("LLM / Azure URL")
        let providerLabel = fieldLabel("Provider")
        let modelLabel = fieldLabel("Model / Azure deployment")
        let tokenLabel = fieldLabel("Token")
        let languageLabel = fieldLabel("Target language")
        let pageRangeLabel = fieldLabel("Pages")
        let pageRangeStack = NSStackView()
        let pageRangeSeparator = NSTextField(labelWithString: "to")
        providerPopup.translatesAutoresizingMaskIntoConstraints = false
        providerPopup.controlSize = .large
        for provider in LLMProvider.allCases {
            providerPopup.addItem(withTitle: provider.displayName)
            providerPopup.lastItem?.representedObject = provider.rawValue
        }
        providerPopup.selectItem(withTitle: AppSettings.provider.displayName)
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged(_:))

        for field in [endpointField, modelField, tokenField, languageField, startPageField, endPageField] {
            field.isEditable = true
            field.isSelectable = true
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        startPageField.alignment = .center
        endPageField.alignment = .center

        pageRangeSeparator.textColor = NSColor(red: 0.36, green: 0.41, blue: 0.48, alpha: 1)
        pageRangeSeparator.translatesAutoresizingMaskIntoConstraints = false
        pageRangeStack.orientation = .horizontal
        pageRangeStack.alignment = .centerY
        pageRangeStack.distribution = .fill
        pageRangeStack.spacing = 8
        pageRangeStack.translatesAutoresizingMaskIntoConstraints = false
        pageRangeStack.addArrangedSubview(startPageField)
        pageRangeStack.addArrangedSubview(pageRangeSeparator)
        pageRangeStack.addArrangedSubview(endPageField)

        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.textColor = NSColor(red: 0.36, green: 0.41, blue: 0.48, alpha: 1)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        previewToolbar.wantsLayer = true
        previewToolbar.layer?.backgroundColor = NSColor.white.cgColor
        previewToolbar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = NSColor.white.cgColor
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .twoUpContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor(red: 0.93, green: 0.95, blue: 0.97, alpha: 1)

        configurePreviewControls()

        contentView.addSubview(splitView)
        splitView.addArrangedSubview(sidebarShell)
        splitView.addArrangedSubview(previewContainer)
        sidebarShell.addSubview(sidebar)
        sidebarShell.addSubview(sidebarToggleButton)
        previewContainer.addSubview(previewToolbar)
        previewContainer.addSubview(pdfView)
        previewContainer.addSubview(bottomBar)
        for view in [title, openButton, providerLabel, providerPopup, endpointLabel, endpointField, modelLabel, modelField, tokenLabel, tokenField, languageLabel, languageField, pageRangeLabel, pageRangeStack, translateButton, exportButton, statusLabel] {
            sidebar.addSubview(view)
        }

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            sidebar.leadingAnchor.constraint(equalTo: sidebarShell.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: sidebarShell.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: sidebarShell.bottomAnchor),
            sidebar.trailingAnchor.constraint(equalTo: sidebarShell.trailingAnchor, constant: -18),

            sidebarToggleButton.trailingAnchor.constraint(equalTo: sidebarShell.trailingAnchor),
            sidebarToggleButton.centerYAnchor.constraint(equalTo: sidebarShell.centerYAnchor),
            sidebarToggleButton.widthAnchor.constraint(equalToConstant: 18),
            sidebarToggleButton.heightAnchor.constraint(equalToConstant: 56),

            previewToolbar.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewToolbar.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewToolbar.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewToolbar.heightAnchor.constraint(equalToConstant: 56),

            pdfView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            pdfView.topAnchor.constraint(equalTo: previewToolbar.bottomAnchor),
            pdfView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 52),

            title.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 26),
            title.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22),
            title.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -22),

            openButton.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
            openButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            openButton.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            openButton.heightAnchor.constraint(equalToConstant: 40),

            providerLabel.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 24),
            providerLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            providerPopup.topAnchor.constraint(equalTo: providerLabel.bottomAnchor, constant: 8),
            providerPopup.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            providerPopup.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            providerPopup.heightAnchor.constraint(equalToConstant: 36),

            endpointLabel.topAnchor.constraint(equalTo: providerPopup.bottomAnchor, constant: 18),
            endpointLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            endpointField.topAnchor.constraint(equalTo: endpointLabel.bottomAnchor, constant: 8),
            endpointField.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            endpointField.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            modelLabel.topAnchor.constraint(equalTo: endpointField.bottomAnchor, constant: 18),
            modelLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            modelField.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: 8),
            modelField.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            modelField.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            tokenLabel.topAnchor.constraint(equalTo: modelField.bottomAnchor, constant: 18),
            tokenLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            tokenField.topAnchor.constraint(equalTo: tokenLabel.bottomAnchor, constant: 8),
            tokenField.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            tokenField.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            languageLabel.topAnchor.constraint(equalTo: tokenField.bottomAnchor, constant: 18),
            languageLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            languageField.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 8),
            languageField.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            languageField.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            pageRangeLabel.topAnchor.constraint(equalTo: languageField.bottomAnchor, constant: 18),
            pageRangeLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            pageRangeStack.topAnchor.constraint(equalTo: pageRangeLabel.bottomAnchor, constant: 8),
            pageRangeStack.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            pageRangeStack.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            startPageField.widthAnchor.constraint(equalTo: endPageField.widthAnchor),
            startPageField.heightAnchor.constraint(equalToConstant: 28),
            endPageField.heightAnchor.constraint(equalToConstant: 28),

            translateButton.topAnchor.constraint(equalTo: pageRangeStack.bottomAnchor, constant: 22),
            translateButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            translateButton.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            translateButton.heightAnchor.constraint(equalToConstant: 40),

            exportButton.topAnchor.constraint(equalTo: translateButton.bottomAnchor, constant: 10),
            exportButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            exportButton.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            exportButton.heightAnchor.constraint(equalToConstant: 40),

            statusLabel.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor)
        ])
        installPageObserver()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        setInitialSidebarWidthIfNeeded()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        setInitialSidebarWidthIfNeeded()
    }

    private func setInitialSidebarWidthIfNeeded() {
        guard !didSetInitialSidebarWidth else { return }
        didSetInitialSidebarWidth = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let width = min(max(320, self.splitView.bounds.width * 0.24), 380)
            self.expandedSidebarWidth = width
            self.splitView.setPosition(width, ofDividerAt: 0)
            self.sidebar.isHidden = false
        }
    }

    @objc private func toggleSidebar() {
        sidebarCollapsed.toggle()
        if sidebarCollapsed {
            expandedSidebarWidth = max(sidebarShell.frame.width, expandedSidebarWidth)
            sidebar.isHidden = true
            sidebarToggleButton.title = "›"
            sidebarToggleButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
            splitView.setPosition(18, ofDividerAt: 0)
        } else {
            sidebar.isHidden = false
            sidebarToggleButton.title = "‹"
            sidebarToggleButton.layer?.backgroundColor = NSColor.systemRed.cgColor
            splitView.setPosition(max(260, expandedSidebarWidth), ofDividerAt: 0)
        }
    }

    private func configurePreviewControls() {
        for button in [zoomOutButton, zoomInButton, previousButton, nextButton] {
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        zoomOutButton.target = self
        zoomOutButton.action = #selector(zoomOut)
        zoomInButton.target = self
        zoomInButton.action = #selector(zoomIn)
        previousButton.target = self
        previousButton.action = #selector(previousPage)
        nextButton.target = self
        nextButton.action = #selector(nextPage)

        zoomLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        zoomLabel.alignment = .center
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false

        pageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        pageLabel.alignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        for view in [zoomOutButton, zoomLabel, zoomInButton, pageLabel, searchField] {
            previewToolbar.addSubview(view)
        }
        for view in [previousButton, nextButton] {
            bottomBar.addSubview(view)
        }

        NSLayoutConstraint.activate([
            zoomLabel.centerXAnchor.constraint(equalTo: previewToolbar.centerXAnchor),
            zoomLabel.centerYAnchor.constraint(equalTo: previewToolbar.centerYAnchor),
            zoomLabel.widthAnchor.constraint(equalToConstant: 70),
            zoomLabel.heightAnchor.constraint(equalToConstant: 30),
            zoomOutButton.trailingAnchor.constraint(equalTo: zoomLabel.leadingAnchor, constant: -2),
            zoomOutButton.centerYAnchor.constraint(equalTo: zoomLabel.centerYAnchor),
            zoomOutButton.widthAnchor.constraint(equalToConstant: 44),
            zoomOutButton.heightAnchor.constraint(equalToConstant: 30),
            zoomInButton.leadingAnchor.constraint(equalTo: zoomLabel.trailingAnchor, constant: 2),
            zoomInButton.centerYAnchor.constraint(equalTo: zoomLabel.centerYAnchor),
            zoomInButton.widthAnchor.constraint(equalToConstant: 44),
            zoomInButton.heightAnchor.constraint(equalToConstant: 30),

            pageLabel.leadingAnchor.constraint(equalTo: zoomInButton.trailingAnchor, constant: 120),
            pageLabel.centerYAnchor.constraint(equalTo: previewToolbar.centerYAnchor),
            pageLabel.widthAnchor.constraint(equalToConstant: 120),

            searchField.leadingAnchor.constraint(greaterThanOrEqualTo: pageLabel.trailingAnchor, constant: 40),
            searchField.trailingAnchor.constraint(equalTo: previewToolbar.trailingAnchor, constant: -34),
            searchField.centerYAnchor.constraint(equalTo: previewToolbar.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 180),

            previousButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            nextButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            previousButton.trailingAnchor.constraint(equalTo: bottomBar.centerXAnchor, constant: -8),
            nextButton.leadingAnchor.constraint(equalTo: bottomBar.centerXAnchor, constant: 8),
            previousButton.widthAnchor.constraint(equalToConstant: 92),
            nextButton.widthAnchor.constraint(equalToConstant: 92),
            previousButton.heightAnchor.constraint(equalToConstant: 30),
            nextButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let provider = LLMProvider(rawValue: rawValue) else {
            return
        }
        endpointField.stringValue = provider.defaultEndpoint
        modelField.stringValue = provider.defaultModel
        saveSettings()
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        sidebarCollapsed ? 18 : 260
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(520, splitView.bounds.width - 560)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !sidebarCollapsed else { return }
        let width = sidebarShell.frame.width
        if width > 80 {
            expandedSidebarWidth = width
        }
    }

    private func installPageObserver() {
        pageChangeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            self?.updateReaderStatus()
        }
    }

    @objc private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadPDF(url)
        }
    }

    private func loadPDF(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            statusLabel.stringValue = "Unable to open PDF."
            return
        }
        inputPDFURL = url
        translatedPDFURL = nil
        pdfView.document = document
        pdfView.clearSelection()
        pdfView.autoScales = true
        updateReaderStatus()
        translateButton.isEnabled = true
        exportButton.isEnabled = false
        setPageRangeInputsEnabled(true)

        let range = validatedPageRange(documentPageCount: document.pageCount, showError: false)
        let rangeText = range.map { "\($0.start)-\($0.end)" } ?? "\(Self.defaultStartPage)-\(min(document.pageCount, Self.defaultEndPage))"
        statusLabel.stringValue = "Loaded \(document.pageCount) pages. No parsing yet. Translation will process pages \(rangeText)."
    }

    @objc private func translatePDF() {
        guard let inputPDFURL else { return }
        let pageCount = pdfView.document?.pageCount ?? 0
        guard let pageRange = validatedPageRange(documentPageCount: pageCount, showError: true) else {
            return
        }
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusLabel.stringValue = "Token is empty."
            return
        }

        saveSettings()
        guard let scriptURL = Bundle.main.resourceURL?.appendingPathComponent("translate_pdf.py") else {
            statusLabel.stringValue = "Unable to locate translate_pdf.py."
            return
        }
        let settings: [String: Any] = [
            "provider": selectedProvider.rawValue,
            "endpoint": endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            "model": modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            "token": token,
            "targetLanguage": languageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        translateButton.isEnabled = false
        exportButton.isEnabled = false
        setPageRangeInputsEnabled(false)
        statusLabel.stringValue = "Generating translated PDF for pages \(pageRange.start)-\(pageRange.end)..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let outputURL = try self?.automaticOutputURL() ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("translated")
                    .appendingPathExtension("pdf")
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try PDFTranslationRunner.run(
                    inputURL: inputPDFURL,
                    outputURL: outputURL,
                    scriptURL: scriptURL,
                    settings: settings,
                    startPage: pageRange.start,
                    pageLimit: pageRange.limit,
                    progress: { [weak self] message in
                        DispatchQueue.main.async {
                            self?.statusLabel.stringValue = message
                        }
                    }
                )
                DispatchQueue.main.async {
                    self?.translatedPDFURL = outputURL
                    self?.openPreviewPDF(outputURL)
                    self?.statusLabel.stringValue = "Translation complete. Saved to \(outputURL.path)"
                    self?.translateButton.isEnabled = true
                    self?.exportButton.isEnabled = true
                    self?.setPageRangeInputsEnabled(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = error.localizedDescription
                    self?.translateButton.isEnabled = true
                    self?.setPageRangeInputsEnabled(true)
                }
            }
        }
    }

    private func setPageRangeInputsEnabled(_ enabled: Bool) {
        startPageField.isEnabled = enabled
        endPageField.isEnabled = enabled
        startPageField.isEditable = enabled
        endPageField.isEditable = enabled
        if !enabled, window?.firstResponder === startPageField.currentEditor() || window?.firstResponder === endPageField.currentEditor() {
            window?.makeFirstResponder(nil)
        }
    }

    @objc private func exportPDF() {
        guard let translatedPDFURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "translated.pdf"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let destinationURL = self?.pdfURL(from: url) ?? url
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: translatedPDFURL, to: destinationURL)
                self?.statusLabel.stringValue = "Exported to \(destinationURL.path)"
            } catch {
                self?.statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    private func saveSettings() {
        AppSettings.save(
            provider: selectedProvider,
            endpoint: endpointField.stringValue,
            model: modelField.stringValue,
            token: tokenField.stringValue,
            targetLanguage: languageField.stringValue
        )
    }

    private func pdfURL(from url: URL) -> URL {
        if url.pathExtension.lowercased() == "pdf" {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension("pdf")
    }

    private func automaticOutputURL() throws -> URL {
        let downloads = try FileManager.default.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return downloads.appendingPathComponent("translated").appendingPathExtension("pdf")
    }

    private func openPreviewPDF(_ url: URL) {
        pdfView.document = PDFDocument(url: url)
        pdfView.displayMode = .twoUpContinuous
        pdfView.displayDirection = .vertical
        pdfView.clearSelection()
        pdfView.autoScales = true
        searchSelections.removeAll()
        searchSelectionIndex = 0
        searchField.stringValue = ""
        updateReaderStatus()
    }

    @objc private func zoomOut() {
        pdfView.autoScales = false
        pdfView.scaleFactor = max(pdfView.minScaleFactor, pdfView.scaleFactor * 0.9)
        updateReaderStatus()
    }

    @objc private func zoomIn() {
        pdfView.autoScales = false
        pdfView.scaleFactor = min(pdfView.maxScaleFactor, pdfView.scaleFactor * 1.1)
        updateReaderStatus()
    }

    @objc private func previousPage() {
        pdfView.goToPreviousPage(nil)
        updateReaderStatus()
    }

    @objc private func nextPage() {
        pdfView.goToNextPage(nil)
        updateReaderStatus()
    }

    @objc private func searchChanged() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let document = pdfView.document, !query.isEmpty else {
            searchSelections.removeAll()
            pdfView.clearSelection()
            return
        }
        searchSelections = document.findString(query, withOptions: .caseInsensitive)
        searchSelectionIndex = 0
        showCurrentSearchSelection()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, window?.firstResponder === searchField.currentEditor() {
            advanceSearchSelection()
            return
        }
        super.keyDown(with: event)
    }

    private func advanceSearchSelection() {
        guard !searchSelections.isEmpty else { return }
        searchSelectionIndex = (searchSelectionIndex + 1) % searchSelections.count
        showCurrentSearchSelection()
    }

    private func showCurrentSearchSelection() {
        guard !searchSelections.isEmpty else {
            pdfView.clearSelection()
            return
        }
        let selection = searchSelections[searchSelectionIndex]
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.scrollSelectionToVisible(nil)
    }

    private func updateReaderStatus() {
        if let document = pdfView.document, let page = pdfView.currentPage {
            let index = document.index(for: page) + 1
            pageLabel.stringValue = "\(index) / \(document.pageCount)"
        } else {
            pageLabel.stringValue = "- / -"
        }
        zoomLabel.stringValue = "\(Int(round(pdfView.scaleFactor * 100)))%"
    }

    private func validatedPageRange(documentPageCount: Int, showError: Bool) -> (start: Int, end: Int, limit: Int)? {
        let start = Int(startPageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let end = Int(endPageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        guard start > 0, end > 0 else {
            if showError {
                statusLabel.stringValue = "Page range must use positive numbers."
            }
            return nil
        }
        guard start <= end else {
            if showError {
                statusLabel.stringValue = "Start page must be less than or equal to end page."
            }
            return nil
        }
        guard documentPageCount == 0 || start <= documentPageCount else {
            if showError {
                statusLabel.stringValue = "Start page is outside the PDF."
            }
            return nil
        }

        let clampedEnd = documentPageCount > 0 ? min(end, documentPageCount) : end
        return (start, clampedEnd, clampedEnd - start + 1)
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor(red: 0.30, green: 0.35, blue: 0.42, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private var selectedProvider: LLMProvider {
        guard let rawValue = providerPopup.selectedItem?.representedObject as? String,
              let provider = LLMProvider(rawValue: rawValue) else {
            return .custom
        }
        return provider
    }
}
