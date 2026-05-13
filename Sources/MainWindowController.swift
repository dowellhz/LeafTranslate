import Cocoa
import PDFKit

final class MainWindowController: NSWindowController, NSSplitViewDelegate, NSSearchFieldDelegate {
    private static let defaultStartPage = 1

    private let openButton = NSButton(title: AppText.openPDF, target: nil, action: nil)
    private let translateButton = NSButton(title: AppText.translate, target: nil, action: nil)
    private let cancelButton = NSButton(title: AppText.cancel, target: nil, action: nil)
    private let clearCacheButton = NSButton(title: AppText.clearCache, target: nil, action: nil)
    private let exportButton = NSButton(title: AppText.exportBilingual, target: nil, action: nil)
    private let exportTranslationOnlyButton = NSButton(title: AppText.exportTranslationOnly, target: nil, action: nil)
    private let exportButtonStack = NSStackView()
    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let endpointLabel = NSTextField(labelWithString: AppText.endpoint)
    private let endpointField = ShortcutTextField(string: AppSettings.endpoint)
    private let modelLabel = NSTextField(labelWithString: AppText.model)
    private let modelField = ShortcutTextField(string: AppSettings.model)
    private let tokenLabel = NSTextField(labelWithString: AppText.token)
    private let tokenField = ShortcutSecureTextField(string: AppSettings.token)
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let startPageField = ShortcutTextField(string: "\(MainWindowController.defaultStartPage)")
    private let endPageField = ShortcutTextField(string: "\(MainWindowController.defaultStartPage)")
    private let currentFileView = NSView()
    private let currentFileThumbnail = NSImageView()
    private let currentFileNameLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: AppText.initialStatus)
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
    private let previousButton = NSButton(title: AppText.previousPage, target: nil, action: nil)
    private let nextButton = NSButton(title: AppText.nextPage, target: nil, action: nil)

    private var inputPDFURL: URL?
    private var inputPDFPageCount = 0
    private var translatedPDFURL: URL?
    private var currentBookHash: String?
    private var currentCacheDirectory: URL?
    private var pageChangeObserver: NSObjectProtocol?
    private var scrollObserver: NSObjectProtocol?
    private var searchSelections: [PDFSelection] = []
    private var searchSelectionIndex = 0
    private let translationCoordinator = TranslationCoordinator()
    private var didSetInitialSidebarWidth = false
    private var sidebarCollapsed = false
    private var expandedSidebarWidth: CGFloat = 320
    private var tokenAfterModelConstraint: NSLayoutConstraint?
    private var tokenAfterProviderConstraint: NSLayoutConstraint?
    private var currentFileHeightConstraint: NSLayoutConstraint?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LeafTranslate"
        window.appearance = NSAppearance(named: .aqua)
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
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
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
        cancelButton.target = self
        cancelButton.action = #selector(cancelTranslation)
        clearCacheButton.target = self
        clearCacheButton.action = #selector(clearCurrentBookCache)
        exportButton.target = self
        exportButton.action = #selector(exportPDF)
        exportTranslationOnlyButton.target = self
        exportTranslationOnlyButton.action = #selector(exportTranslationOnlyPDF)
        translateButton.isEnabled = false
        cancelButton.isEnabled = false
        clearCacheButton.isEnabled = false
        exportButton.isEnabled = false
        exportTranslationOnlyButton.isEnabled = false

        for button in [openButton, translateButton, cancelButton, clearCacheButton] {
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        for button in [exportButton, exportTranslationOnlyButton] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        exportButtonStack.orientation = .horizontal
        exportButtonStack.alignment = .centerY
        exportButtonStack.distribution = .fillEqually
        exportButtonStack.spacing = 8
        exportButtonStack.translatesAutoresizingMaskIntoConstraints = false
        exportButtonStack.addArrangedSubview(exportButton)
        exportButtonStack.addArrangedSubview(exportTranslationOnlyButton)
        configureCurrentFileView()

        configureFieldLabel(endpointLabel)
        let providerLabel = fieldLabel(AppText.provider)
        configureFieldLabel(modelLabel)
        configureFieldLabel(tokenLabel)
        let languageLabel = fieldLabel(AppText.targetLanguage)
        let pageRangeLabel = fieldLabel(AppText.pages)
        let pageRangeStack = NSStackView()
        let pageRangeSeparator = NSTextField(labelWithString: AppText.to)
        providerPopup.translatesAutoresizingMaskIntoConstraints = false
        providerPopup.controlSize = .large
        for provider in LLMProvider.allCases {
            providerPopup.addItem(withTitle: provider.displayName)
            providerPopup.lastItem?.representedObject = provider.rawValue
        }
        providerPopup.selectItem(withTitle: AppSettings.provider.displayName)
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged(_:))

        for field in [endpointField, modelField, tokenField, startPageField, endPageField] {
            field.isEditable = true
            field.isSelectable = true
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        startPageField.delegate = self
        endPageField.delegate = self
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        languagePopup.controlSize = .large
        for language in TargetLanguage.allCases {
            languagePopup.addItem(withTitle: language.displayName)
            languagePopup.lastItem?.representedObject = language.rawValue
        }
        languagePopup.selectItem(withTitle: TargetLanguage.normalized(AppSettings.targetLanguage).displayName)
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
        for view in [title, openButton, currentFileView, providerLabel, providerPopup, endpointLabel, endpointField, modelLabel, modelField, tokenLabel, tokenField, languageLabel, languagePopup, pageRangeLabel, pageRangeStack, translateButton, cancelButton, clearCacheButton, exportButtonStack, statusLabel] {
            sidebar.addSubview(view)
        }

        tokenAfterModelConstraint = tokenLabel.topAnchor.constraint(equalTo: modelField.bottomAnchor, constant: 18)
        tokenAfterProviderConstraint = tokenLabel.topAnchor.constraint(equalTo: providerPopup.bottomAnchor, constant: 18)
        tokenAfterProviderConstraint?.isActive = false
        currentFileHeightConstraint = currentFileView.heightAnchor.constraint(equalToConstant: 0)

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

            currentFileView.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 10),
            currentFileView.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            currentFileView.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            currentFileHeightConstraint!,

            currentFileThumbnail.leadingAnchor.constraint(equalTo: currentFileView.leadingAnchor),
            currentFileThumbnail.centerYAnchor.constraint(equalTo: currentFileView.centerYAnchor),
            currentFileThumbnail.widthAnchor.constraint(equalToConstant: 38),
            currentFileThumbnail.heightAnchor.constraint(equalToConstant: 52),

            currentFileNameLabel.leadingAnchor.constraint(equalTo: currentFileThumbnail.trailingAnchor, constant: 10),
            currentFileNameLabel.trailingAnchor.constraint(equalTo: currentFileView.trailingAnchor),
            currentFileNameLabel.centerYAnchor.constraint(equalTo: currentFileView.centerYAnchor),

            providerLabel.topAnchor.constraint(equalTo: currentFileView.bottomAnchor, constant: 18),
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

            tokenAfterModelConstraint!,
            tokenLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            tokenField.topAnchor.constraint(equalTo: tokenLabel.bottomAnchor, constant: 8),
            tokenField.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            tokenField.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            languageLabel.topAnchor.constraint(equalTo: tokenField.bottomAnchor, constant: 18),
            languageLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            languagePopup.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 8),
            languagePopup.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            languagePopup.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            languagePopup.heightAnchor.constraint(equalToConstant: 36),

            pageRangeLabel.topAnchor.constraint(equalTo: languagePopup.bottomAnchor, constant: 18),
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

            cancelButton.topAnchor.constraint(equalTo: translateButton.bottomAnchor, constant: 10),
            cancelButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),

            clearCacheButton.topAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 10),
            clearCacheButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            clearCacheButton.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            clearCacheButton.heightAnchor.constraint(equalToConstant: 40),

            exportButtonStack.topAnchor.constraint(equalTo: clearCacheButton.bottomAnchor, constant: 10),
            exportButtonStack.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            exportButtonStack.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            exportButtonStack.heightAnchor.constraint(equalToConstant: 32),
            exportButton.heightAnchor.constraint(equalToConstant: 32),
            exportTranslationOnlyButton.heightAnchor.constraint(equalToConstant: 32),

            statusLabel.topAnchor.constraint(equalTo: exportButtonStack.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor)
        ])
        updateProviderFieldsVisibility()
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

        searchField.placeholderString = AppText.search
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

    private func configureCurrentFileView() {
        currentFileView.translatesAutoresizingMaskIntoConstraints = false
        currentFileView.isHidden = true

        currentFileThumbnail.translatesAutoresizingMaskIntoConstraints = false
        currentFileThumbnail.imageScaling = .scaleProportionallyUpOrDown
        currentFileThumbnail.wantsLayer = true
        currentFileThumbnail.layer?.cornerRadius = 4
        currentFileThumbnail.layer?.borderWidth = 1
        currentFileThumbnail.layer?.borderColor = NSColor(red: 0.82, green: 0.86, blue: 0.91, alpha: 1).cgColor
        currentFileThumbnail.layer?.backgroundColor = NSColor.white.cgColor

        currentFileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        currentFileNameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        currentFileNameLabel.textColor = NSColor(red: 0.15, green: 0.18, blue: 0.24, alpha: 1)
        currentFileNameLabel.lineBreakMode = .byTruncatingMiddle
        currentFileNameLabel.maximumNumberOfLines = 2

        currentFileView.addSubview(currentFileThumbnail)
        currentFileView.addSubview(currentFileNameLabel)
    }

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let provider = LLMProvider(rawValue: rawValue) else {
            return
        }
        endpointField.stringValue = provider.defaultEndpoint
        modelField.stringValue = provider.defaultModel
        updateProviderFieldsVisibility()
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
        installScrollObserver()
    }

    private func installScrollObserver() {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
        guard let contentView = pdfView.documentView?.enclosingScrollView?.contentView else {
            return
        }
        contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
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
            statusLabel.stringValue = AppText.unableToOpenPDF
            return
        }
        let bookHash: String
        let cacheDirectory: URL
        do {
            bookHash = try BookCacheStore.bookHash(for: url)
            cacheDirectory = try BookCacheStore.cacheDirectory(for: bookHash)
        } catch {
            statusLabel.stringValue = AppText.unableToPrepareCache(error.localizedDescription)
            return
        }
        inputPDFURL = url
        inputPDFPageCount = document.pageCount
        translatedPDFURL = nil
        currentBookHash = bookHash
        currentCacheDirectory = cacheDirectory
        updateCurrentFileView(url: url, document: document)
        pdfView.document = document
        pdfView.clearSelection()
        pdfView.autoScales = true
        startPageField.stringValue = "\(Self.defaultStartPage)"
        endPageField.stringValue = "\(document.pageCount)"
        installScrollObserver()
        updateReaderStatus()
        translateButton.isEnabled = true
        exportButton.isEnabled = false
        exportTranslationOnlyButton.isEnabled = false
        updateClearCacheButton()
        setPageRangeInputsEnabled(true)

        statusLabel.stringValue = AppText.loadedPages(document.pageCount)
    }

    @objc private func translatePDF() {
        guard let inputPDFURL else { return }
        guard let pageRange = validatedPageRange(documentPageCount: inputPDFPageCount, showError: true) else {
            return
        }
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusLabel.stringValue = AppText.tokenEmpty
            return
        }

        saveSettings()
        guard let scriptURL = Bundle.main.resourceURL?.appendingPathComponent("translate_pdf.py") else {
            statusLabel.stringValue = AppText.missingTranslatorScript
            return
        }
        let settings = TranslationSettings(
            provider: selectedProvider,
            endpoint: endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            model: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token,
            targetLanguage: selectedTargetLanguage.rawValue,
            cacheDirectory: currentCacheDirectory
        )

        translatedPDFURL = nil
        translateButton.isEnabled = false
        cancelButton.isEnabled = true
        clearCacheButton.isEnabled = false
        exportButton.isEnabled = false
        exportTranslationOnlyButton.isEnabled = false
        setPageRangeInputsEnabled(false)
        statusLabel.stringValue = AppText.generatingPages(start: pageRange.start, end: pageRange.end)

        translationCoordinator.translate(
            inputURL: inputPDFURL,
            scriptURL: scriptURL,
            settings: settings,
            pageRange: pageRange,
            progress: { [weak self] message in
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = message
                }
            }
        ) { [weak self] result in
            switch result {
            case .success(let outputURL):
                self?.translatedPDFURL = outputURL
                self?.openPreviewPDF(outputURL)
                self?.statusLabel.stringValue = AppText.translationComplete(outputURL.path)
                self?.translateButton.isEnabled = true
                self?.cancelButton.isEnabled = false
                self?.exportButton.isEnabled = true
                self?.exportTranslationOnlyButton.isEnabled = true
                self?.updateClearCacheButton()
                self?.setPageRangeInputsEnabled(true)
            case .failure(let error):
                self?.statusLabel.stringValue = error.localizedDescription
                self?.translateButton.isEnabled = true
                self?.cancelButton.isEnabled = false
                self?.exportButton.isEnabled = false
                self?.exportTranslationOnlyButton.isEnabled = false
                self?.updateClearCacheButton()
                self?.setPageRangeInputsEnabled(true)
            }
        }
    }

    @objc private func cancelTranslation() {
        translationCoordinator.cancel()
        cancelButton.isEnabled = false
        statusLabel.stringValue = AppText.cancellingTranslation
    }

    @objc private func clearCurrentBookCache() {
        guard let currentBookHash else { return }
        do {
            let removedCount = try BookCacheStore.clearCache(for: currentBookHash)
            updateClearCacheButton()
            statusLabel.stringValue = AppText.cacheCleared(removedCount)
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func updateClearCacheButton() {
        guard let currentCacheDirectory else {
            clearCacheButton.isEnabled = false
            return
        }
        clearCacheButton.isEnabled = BookCacheStore.hasCache(at: currentCacheDirectory)
    }

    private func updateCurrentFileView(url: URL, document: PDFDocument) {
        currentFileNameLabel.stringValue = url.lastPathComponent
        if let firstPage = document.page(at: 0) {
            currentFileThumbnail.image = firstPage.thumbnail(of: NSSize(width: 76, height: 104), for: .mediaBox)
        } else {
            currentFileThumbnail.image = NSImage(named: NSImage.multipleDocumentsName)
        }
        currentFileView.isHidden = false
        currentFileHeightConstraint?.constant = 60
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
        panel.nameFieldStringValue = defaultExportFileName(kind: .bilingual)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let destinationURL = self?.pdfURL(from: url) ?? url
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: translatedPDFURL, to: destinationURL)
                self?.statusLabel.stringValue = AppText.exported(destinationURL.path)
            } catch {
                self?.statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func exportTranslationOnlyPDF() {
        guard let translatedPDFURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultExportFileName(kind: .translationOnly)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let destinationURL = self.pdfURL(from: url)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try self.writeTranslationOnlyPDF(from: translatedPDFURL, to: destinationURL)
                self.statusLabel.stringValue = AppText.exported(destinationURL.path)
            } catch {
                self.statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    private enum ExportKind {
        case bilingual
        case translationOnly
    }

    private func defaultExportFileName(kind: ExportKind) -> String {
        let baseName = inputPDFURL?.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceName = baseName?.isEmpty == false ? baseName! : "document"
        switch kind {
        case .bilingual:
            return "\(sourceName)-\(selectedTargetLanguage.fileNameComponent)-translated.pdf"
        case .translationOnly:
            return "\(sourceName)-\(selectedTargetLanguage.fileNameComponent)-translation-only.pdf"
        }
    }

    private func writeTranslationOnlyPDF(from sourceURL: URL, to destinationURL: URL) throws {
        guard let scriptURL = Bundle.main.resourceURL?.appendingPathComponent("export_translation_only.py") else {
            throw NSError(
                domain: "LeafTranslate",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: AppText.missingTranslatorScript]
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path, sourceURL.path, destinationURL.path]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "LeafTranslate",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? AppText.unableToExportPDF : stderr]
            )
        }
    }

    private func saveSettings() {
        AppSettings.save(
            provider: selectedProvider,
            endpoint: endpointField.stringValue,
            model: modelField.stringValue,
            token: tokenField.stringValue,
            targetLanguage: selectedTargetLanguage.rawValue
        )
    }

    private func pdfURL(from url: URL) -> URL {
        if url.pathExtension.lowercased() == "pdf" {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension("pdf")
    }

    private func openPreviewPDF(_ url: URL) {
        pdfView.document = PDFDocument(url: url)
        pdfView.displayMode = .twoUpContinuous
        pdfView.displayDirection = .vertical
        pdfView.clearSelection()
        pdfView.autoScales = true
        installScrollObserver()
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
        guard let document = pdfView.document else { return }
        let currentIndex = currentVisiblePageIndex(in: document) ?? 0
        let targetIndex = max(0, currentIndex - 1)
        if let page = document.page(at: targetIndex) {
            pdfView.go(to: page)
        }
        updateReaderStatus()
    }

    @objc private func nextPage() {
        guard let document = pdfView.document else { return }
        let currentIndex = currentVisiblePageIndex(in: document) ?? 0
        let targetIndex = min(document.pageCount - 1, currentIndex + 1)
        if let page = document.page(at: targetIndex) {
            pdfView.go(to: page)
        }
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
        if let document = pdfView.document {
            let index = (currentVisiblePageIndex(in: document) ?? 0) + 1
            pageLabel.stringValue = "\(index) / \(document.pageCount)"
        } else {
            pageLabel.stringValue = "- / -"
        }
        zoomLabel.stringValue = "\(Int(round(pdfView.scaleFactor * 100)))%"
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === startPageField || field === endPageField else {
            return
        }
        normalizePageRangeInputs(documentPageCount: inputPDFPageCount)
    }

    private func currentVisiblePageIndex(in document: PDFDocument) -> Int? {
        let visibleRect = pdfView.visibleRect
        let samplePoints = [
            CGPoint(x: visibleRect.midX, y: visibleRect.midY),
            CGPoint(x: visibleRect.midX, y: visibleRect.minY + visibleRect.height * 0.35),
            CGPoint(x: visibleRect.midX, y: visibleRect.minY + visibleRect.height * 0.65),
            CGPoint(x: visibleRect.minX + visibleRect.width * 0.35, y: visibleRect.midY),
            CGPoint(x: visibleRect.minX + visibleRect.width * 0.65, y: visibleRect.midY)
        ]

        for point in samplePoints {
            if let page = pdfView.page(for: point, nearest: false) {
                return document.index(for: page)
            }
        }
        if let page = pdfView.page(for: CGPoint(x: visibleRect.midX, y: visibleRect.midY), nearest: true) {
            return document.index(for: page)
        }
        if let page = pdfView.currentPage {
            return document.index(for: page)
        }
        return nil
    }

    private func validatedPageRange(documentPageCount: Int, showError: Bool) -> (start: Int, end: Int, limit: Int)? {
        normalizePageRangeInputs(documentPageCount: documentPageCount)
        let start = Int(startPageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let end = Int(endPageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        guard start > 0, end > 0 else {
            if showError {
                statusLabel.stringValue = AppText.positivePageRange
            }
            return nil
        }
        guard start <= end else {
            if showError {
                statusLabel.stringValue = AppText.startBeforeEnd
            }
            return nil
        }
        guard documentPageCount == 0 || start <= documentPageCount else {
            if showError {
                statusLabel.stringValue = AppText.startOutsidePDF
            }
            return nil
        }

        let clampedEnd = documentPageCount > 0 ? min(end, documentPageCount) : end
        return (start, clampedEnd, clampedEnd - start + 1)
    }

    private func normalizePageRangeInputs(documentPageCount: Int) {
        guard documentPageCount > 0 else { return }

        let startText = startPageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let endText = endPageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = Int(startText), start > documentPageCount {
            startPageField.stringValue = "\(documentPageCount)"
        }
        if let end = Int(endText), end > documentPageCount {
            endPageField.stringValue = "\(documentPageCount)"
        }
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        configureFieldLabel(label)
        return label
    }

    private func configureFieldLabel(_ label: NSTextField) {
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor(red: 0.30, green: 0.35, blue: 0.42, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateProviderFieldsVisibility() {
        let isCustomProvider = selectedProvider == .custom
        for view in [endpointLabel, endpointField, modelLabel, modelField] {
            view.isHidden = !isCustomProvider
        }
        tokenAfterModelConstraint?.isActive = isCustomProvider
        tokenAfterProviderConstraint?.isActive = !isCustomProvider
    }

    private var selectedProvider: LLMProvider {
        guard let rawValue = providerPopup.selectedItem?.representedObject as? String,
              let provider = LLMProvider(rawValue: rawValue) else {
            return .custom
        }
        return provider
    }

    private var selectedTargetLanguage: TargetLanguage {
        guard let rawValue = languagePopup.selectedItem?.representedObject as? String else {
            return .chinese
        }
        return TargetLanguage.normalized(rawValue)
    }
}
