import AppKit
import ApplicationServices
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class AppModel {
    private struct UndoSnapshot: Equatable {
        let scriptText: String
        let splitMode: SplitMode
        let preservesEmptyAnchors: Bool
        let assignments: [String: [BrollAsset]]
        let rollTypeOverrides: [String: AnchorRollType]

        var archivedNames: Set<String> {
            Set(assignments.values.flatMap { $0.map(\.outputName) })
        }
    }

    private struct ArchiveCopy: Sendable {
        let sourceURL: URL
        let destinationURL: URL
        let didStartAccess: Bool
        let outputName: String
    }

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "webm", "avi", "mkv", "mts", "m2ts"
    ]
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp"
    ]

    var scriptText: String
    var splitMode: SplitMode
    private var preservesEmptyAnchors: Bool
    var prefix: String
    var anchorSearchText = ""
    let dropFeedback = DropFeedbackModel()
    var selectedSourceFileURL: URL?
    var sourceFileJumpID: UUID?
    var mediaFilter: MediaFilter = .all {
        didSet { rebuildVisibleSourceFiles() }
    }
    var isScriptEditorPresented = false
    var isManifestPreviewPresented = false
    private(set) var manifestPreviewText = ""
    var isClearConfirmationPresented = false
    var isBusy = false
    var statusMessage = "请设置素材来源和归档位置"
    var lastSaved = "尚未保存"
    var alert: AppAlert?

    private(set) var rows: [AnchorRow] = []
    private(set) var assignments: [String: [BrollAsset]] = [:]
    private(set) var rollTypeOverrides: [String: AnchorRollType] = [:]
    private(set) var sourceFiles: [SourceFile] = []
    private(set) var visibleSourceFiles: [SourceFile] = []
    private(set) var sourceDirectoryURL: URL?
    private(set) var destinationDirectoryURL: URL?
    private(set) var savedDirectories: [SavedDirectory] = []

    private let defaults = UserDefaults.standard
    private weak var undoManager: UndoManager?
    private var sourceAccessActive = false
    private var destinationAccessActive = false
    private var sourceFilesByName: [String: SourceFile] = [:]
    private var sourceFilesByURL: [URL: SourceFile] = [:]
    private var assignedNamesIndex: Set<String> = []
    private var assetsBySourceName: [String: [BrollAsset]] = [:]
    private var sourceScanTask: Task<[SourceFile], Error>?
    private var sourceScanGeneration = UUID()

    private let scriptKey = "broll-namer-script"
    private let splitModeKey = "broll-namer-split-mode"
    private let preservesEmptyAnchorsKey = "broll-namer-preserves-empty-anchors"
    private let rollTypeOverridesKey = "broll-namer-roll-type-overrides"
    private let prefixKey = "broll-namer-prefix"
    private let sourceBookmarkKey = "broll-namer-source-bookmark"
    private let destinationBookmarkKey = "broll-namer-destination-bookmark"
    private let savedDirectoriesKey = "broll-namer-saved-directories"

    init() {
        scriptText = defaults.string(forKey: scriptKey) ?? ""
        splitMode = SplitMode(rawValue: defaults.string(forKey: splitModeKey) ?? "line") ?? .line
        preservesEmptyAnchors = defaults.bool(forKey: preservesEmptyAnchorsKey)
        prefix = defaults.string(forKey: prefixKey) ?? ""
        rollTypeOverrides = (defaults.dictionary(forKey: rollTypeOverridesKey) ?? [:]).compactMapValues { value in
            guard let rawValue = value as? String else { return nil }
            return AnchorRollType(rawValue: rawValue)
        }

        restoreSavedDirectories()
        parseScript(persist: false)
        restoreAssignments()

        Task { @MainActor [weak self] in
            self?.restoreDirectories()
        }
    }

    var sourceDirectoryName: String {
        sourceDirectoryURL?.lastPathComponent ?? "未选择"
    }

    var destinationDirectoryName: String {
        destinationDirectoryURL?.lastPathComponent ?? "未选择"
    }

    var isPrefixValid: Bool {
        !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var assignedCount: Int {
        rows.reduce(0) { $0 + assets(for: $1.id).count }
    }

    var pendingCount: Int {
        pendingBrollCount
    }

    var pendingBrollCount: Int {
        rows.reduce(0) { $0 + (rollType(for: $1.id) == .bRoll && assets(for: $1.id).isEmpty ? 1 : 0) }
    }

    var scriptCharacterCount: Int {
        scriptText.reduce(into: 0) { count, character in
            if !character.isWhitespace {
                count += 1
            }
        }
    }

    var aRollAnchorCount: Int {
        rows.reduce(0) { $0 + (rollType(for: $1.id) == .aRoll ? 1 : 0) }
    }

    var bRollAnchorCount: Int {
        rows.reduce(0) { $0 + (rollType(for: $1.id) == .bRoll ? 1 : 0) }
    }

    var filteredRows: [AnchorRow] {
        let query = anchorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.text.localizedCaseInsensitiveContains(query) || "BR\(String(format: "%03d", $0.index))".localizedCaseInsensitiveContains(query) }
    }

    private func rebuildVisibleSourceFiles() {
        switch mediaFilter {
        case .all:
            visibleSourceFiles = sourceFiles
        case .video:
            visibleSourceFiles = sourceFiles.filter { $0.kind == .video }
        case .image:
            visibleSourceFiles = sourceFiles.filter { $0.kind == .image }
        }
    }

    func assets(for rowID: String) -> [BrollAsset] {
        assignments[rowID] ?? []
    }

    func rollType(for rowID: String) -> AnchorRollType {
        rollTypeOverrides[rowID] ?? (assets(for: rowID).isEmpty ? .aRoll : .bRoll)
    }

    func toggleRollType(for rowID: String) {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        let before = makeUndoSnapshot()
        let nextType: AnchorRollType = rollType(for: rowID) == .bRoll ? .aRoll : .bRoll
        rollTypeOverrides[rowID] = nextType
        persistPreferences()
        lastSaved = "本机已保存 \(Self.timeString())"
        statusMessage = nextType == .bRoll
            ? (assets(for: rowID).isEmpty
                ? "BR\(String(format: "%03d", row.index)) 已设为 B-roll，待绑定素材；请从素材列表拖拽素材到这条文案。"
                : "BR\(String(format: "%03d", row.index)) 已设为 B-roll")
            : "BR\(String(format: "%03d", row.index)) 已设为 A-roll"
        registerUndo(named: "切换 A/B-roll", restoring: before)
    }

    func isAssigned(_ file: SourceFile) -> Bool {
        assignedNamesIndex.contains(file.name)
    }

    func assignedAssets(forSourceName sourceName: String) -> [BrollAsset] {
        assetsBySourceName[sourceName] ?? []
    }

    func sourceFile(at url: URL) -> SourceFile? {
        sourceFilesByURL[url]
    }

    var isCurrentSourceDirectorySaved: Bool {
        guard let sourceDirectoryURL else { return false }
        let identity = directoryIdentity(for: sourceDirectoryURL)
        return savedDirectories.contains { $0.path == identity }
    }

    func persistPreferences() {
        defaults.set(scriptText, forKey: scriptKey)
        defaults.set(splitMode.rawValue, forKey: splitModeKey)
        defaults.set(preservesEmptyAnchors, forKey: preservesEmptyAnchorsKey)
        defaults.set(prefix, forKey: prefixKey)
        defaults.set(rollTypeOverrides.mapValues(\.rawValue), forKey: rollTypeOverridesKey)
        saveAssignments()
    }

    func connectUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
        if let undoManager, undoManager.levelsOfUndo < 50 {
            undoManager.levelsOfUndo = 50
        }
    }

    func setSplitMode(_ mode: SplitMode) {
        guard splitMode != mode else { return }
        let before = makeUndoSnapshot()
        splitMode = mode
        parseScript(persist: false)
        persistPreferences()
        registerUndo(named: "更改文案拆分方式", restoring: before)
    }

    func parseScript(persist: Bool = true) {
        let chunks = ScriptParser.split(scriptText, mode: splitMode, preservingEmptyLines: preservesEmptyAnchors)
        var occurrences: [String: Int] = [:]

        rows = chunks.enumerated().map { offset, text in
            let base = ScriptParser.hash(text)
            let occurrence = (occurrences[base] ?? 0) + 1
            occurrences[base] = occurrence
            return AnchorRow(
                id: ScriptParser.key(for: text, occurrence: occurrence),
                index: offset + 1,
                text: text
            )
        }
        let currentRowIDs = Set(rows.map(\.id))
        rollTypeOverrides = rollTypeOverrides.filter { currentRowIDs.contains($0.key) }
        rebuildAssignmentIndexes()

        if persist {
            persistPreferences()
        }
    }

    func replaceInlineRow(at index: Int, with text: String) {
        guard rows.indices.contains(index) else { return }
        let before = makeUndoSnapshot()
        var texts = rows.map(\.text)
        texts[index] = inlineText(text)
        applyInlineRows(texts, sourceIndices: rows.indices.map { [$0] })
        registerUndo(named: "修改文案", restoring: before)
    }

    func splitInlineRow(at index: Int, text: String, selection: NSRange) {
        guard rows.indices.contains(index) else { return }
        let before = makeUndoSnapshot()
        let value = inlineText(text) as NSString
        let safeLocation = min(max(selection.location, 0), value.length)
        let safeLength = min(max(selection.length, 0), value.length - safeLocation)
        let upper = value.substring(to: safeLocation)
        let lower = value.substring(from: safeLocation + safeLength)

        var texts = rows.map(\.text)
        texts.replaceSubrange(index...index, with: [upper, lower])
        var sourceIndices = rows.indices.map { [$0] }
        sourceIndices.replaceSubrange(index...index, with: [[index], []])
        applyInlineRows(texts, sourceIndices: sourceIndices)
        registerUndo(named: "拆分文案", restoring: before)
    }

    func mergeInlineRowWithPrevious(at index: Int, text: String) -> Int? {
        guard rows.indices.contains(index), index > 0 else { return nil }
        let before = makeUndoSnapshot()
        let insertionPoint = (rows[index - 1].text as NSString).length
        var texts = rows.map(\.text)
        texts.replaceSubrange((index - 1)...index, with: [rows[index - 1].text + inlineText(text)])
        var sourceIndices = rows.indices.map { [$0] }
        sourceIndices.replaceSubrange((index - 1)...index, with: [[index - 1, index]])
        applyInlineRows(texts, sourceIndices: sourceIndices)
        registerUndo(named: "合并文案", restoring: before)
        return insertionPoint
    }

    private func inlineText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func applyInlineRows(_ texts: [String], sourceIndices: [[Int]]) {
        let previousRows = rows
        let previousAssignments = assignments
        let previousRollTypeOverrides = rollTypeOverrides
        splitMode = .line
        preservesEmptyAnchors = true
        scriptText = texts.joined(separator: "\n")
        parseScript(persist: false)
        assignments = AnchorAssignmentMigration.migrate(
            previousAssignments,
            from: previousRows,
            to: rows,
            sourceIndices: sourceIndices
        )
        rollTypeOverrides = Dictionary(uniqueKeysWithValues: rows.enumerated().compactMap { offset, row in
            guard sourceIndices.indices.contains(offset) else { return nil }
            let inheritedType = sourceIndices[offset]
                .compactMap { sourceIndex -> AnchorRollType? in
                    guard previousRows.indices.contains(sourceIndex) else { return nil }
                    return previousRollTypeOverrides[previousRows[sourceIndex].id]
                }
                .first
            return inheritedType.map { (row.id, $0) }
        })
        rebuildAssignmentIndexes()
        persistPreferences()
        if destinationDirectoryURL != nil {
            _ = saveManifest(showMessage: false)
        }
        lastSaved = "本机已保存 \(Self.timeString())"
    }

    func chooseSourceDirectory() {
        chooseSourceDirectory(saveAsFavorite: false)
    }

    func chooseAndSaveSourceDirectory() {
        chooseSourceDirectory(saveAsFavorite: true)
    }

    func chooseSourceDirectory(saveAsFavorite: Bool) {
        let panel = NSOpenPanel()
        panel.title = "选择素材目录"
        panel.message = "选择一个包含视频素材的文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        activateSourceDirectory(url)
        if saveAsFavorite {
            saveFavoriteDirectory(url, showMessage: false)
        }
        statusMessage = "素材目录已连接：\(url.lastPathComponent)"
    }

    func acceptSourceDirectoryDrop(_ url: URL, saveAsFavorite: Bool = false) {
        activateSourceDirectory(url)
        if saveAsFavorite {
            saveFavoriteDirectory(url, showMessage: false)
        }
        statusMessage = "素材目录已连接：\(url.lastPathComponent)"
    }

    func saveCurrentSourceDirectory() {
        guard let sourceDirectoryURL else {
            showError(title: "还没有素材目录", message: "请先选择一个素材来源目录。")
            return
        }
        saveFavoriteDirectory(sourceDirectoryURL)
    }

    func selectSavedDirectory(_ id: UUID) {
        guard let savedDirectory = savedDirectories.first(where: { $0.id == id }) else { return }
        guard let url = resolveSavedDirectory(savedDirectory) else {
            showError(title: "无法打开常用目录", message: "目录权限已失效，请重新选择这个目录。")
            return
        }

        activateSourceDirectory(url)
        statusMessage = "已切换素材目录：\(url.lastPathComponent)"
    }

    func removeSavedDirectory(_ id: UUID) {
        savedDirectories.removeAll { $0.id == id }
        persistSavedDirectories()
    }

    func chooseDestinationDirectory() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "选择归档目录"
        panel.message = "选择一个用于保存复制素材和 manifest 的文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        activateDestinationDirectory(url)
        restoreManifestFromDestination()
        refreshSourceFiles()
        statusMessage = "目标目录已连接：\(url.lastPathComponent)"
    }

    func acceptDestinationDirectoryDrop(_ url: URL) {
        guard !isBusy else { return }
        activateDestinationDirectory(url)
        restoreManifestFromDestination()
        refreshSourceFiles()
        statusMessage = "目标目录已连接：\(url.lastPathComponent)"
    }

    func refreshSourceFiles() {
        sourceScanTask?.cancel()
        sourceScanTask = nil

        guard let directoryURL = sourceDirectoryURL else {
            sourceScanGeneration = UUID()
            installSourceFiles([])
            return
        }

        let generation = UUID()
        sourceScanGeneration = generation
        let didStartAccess = directoryURL.startAccessingSecurityScopedResource()
        let videoExtensions = Self.videoExtensions
        let imageExtensions = Self.imageExtensions
        let scanTask = Task.detached(priority: .userInitiated) {
            defer {
                if didStartAccess {
                    directoryURL.stopAccessingSecurityScopedResource()
                }
            }
            return try SourceFileScanner.scan(
                in: directoryURL,
                videoExtensions: videoExtensions,
                imageExtensions: imageExtensions
            )
        }
        sourceScanTask = scanTask

        Task { @MainActor [weak self] in
            do {
                let files = try await scanTask.value
                guard let self, self.sourceScanGeneration == generation else { return }
                self.sourceScanTask = nil
                self.installSourceFiles(files)
            } catch is CancellationError {
                guard let self, self.sourceScanGeneration == generation else { return }
                self.sourceScanTask = nil
            } catch {
                guard let self, self.sourceScanGeneration == generation else { return }
                self.sourceScanTask = nil
                self.installSourceFiles([])
                self.statusMessage = "无法读取素材目录：\(error.localizedDescription)"
            }
        }
    }

    private func installSourceFiles(_ files: [SourceFile]) {
        var byName: [String: SourceFile] = [:]
        var byURL: [URL: SourceFile] = [:]
        for file in files {
            byName[file.name] = file
            byURL[file.url] = file
        }

        sourceFilesByName = byName
        sourceFilesByURL = byURL
        sourceFiles = files
        rebuildVisibleSourceFiles()

        if let selectedSourceFileURL, byURL[selectedSourceFileURL] == nil {
            self.selectedSourceFileURL = nil
        }
    }

    func requestClearAssignments() {
        guard !isBusy else { return }
        guard !assignments.isEmpty || destinationDirectoryURL != nil else { return }
        isClearConfirmationPresented = true
    }

    func clearAssignments() {
        guard !isBusy else { return }
        guard let destinationDirectoryURL else {
            showError(title: "无法清空配对记录", message: "请先重新选择归档位置，才能删除归档副本并更新清单。")
            return
        }

        // Clearing can also remove unrecorded archive files, so earlier undo entries
        // must not appear to undo a different action after this irreversible cleanup.
        undoManager?.removeAllActions()

        let recordedNames = Set(assignments.values.flatMap { $0.map(\.outputName) })
        let mediaExtensions = Self.videoExtensions.union(Self.imageExtensions)
        let didStartAccess = destinationDirectoryURL.startAccessingSecurityScopedResource()
        isBusy = true
        statusMessage = "正在清理归档副本…"

        let cleanupTask = Task.detached(priority: .utility) {
            defer {
                if didStartAccess {
                    destinationDirectoryURL.stopAccessingSecurityScopedResource()
                }
            }
            let discoveredNames = try ArchiveCleaner.discoverCopies(
                in: destinationDirectoryURL,
                mediaExtensions: mediaExtensions
            )
            let outputNames = recordedNames.union(discoveredNames)
            return ArchiveCleaner.removeCopies(named: outputNames, from: destinationDirectoryURL)
        }

        Task { @MainActor [weak self] in
            defer { self?.isBusy = false }
            do {
                let cleanup = try await cleanupTask.value
                guard let self, self.destinationDirectoryURL == destinationDirectoryURL else { return }
                self.finishClearAssignments(cleanup)
            } catch {
                self?.showError(title: "无法读取归档位置", message: "尚未清空配对记录：\(error.localizedDescription)")
            }
        }
    }

    private func finishClearAssignments(_ cleanup: ArchiveCleanupResult) {
        assignments = assignments.compactMapValues { assets in
            let remaining = assets.filter { cleanup.failedNames.contains($0.outputName) }
            return remaining.isEmpty ? nil : remaining
        }
        rebuildAssignmentIndexes()
        let localSaved = saveAssignments()
        let manifestSaved = saveManifest(showMessage: false)
        refreshSourceFiles()

        if !cleanup.failedNames.isEmpty {
            let examples = cleanup.failedNames.sorted().prefix(3).joined(separator: "、")
            let suffix = cleanup.failedNames.count > 3 ? "等" : ""
            let manifestNote = manifestSaved
                ? "清单已更新；未删除的文件仍留在归档位置，对应绑定会保留。"
                : "清单更新也失败了，请检查归档目录。"
            let localNote = localSaved ? "" : "本机记录保存也失败了。"
            showError(
                title: "部分归档副本删除失败",
                message: "有 \(cleanup.failedNames.count) 个归档文件未能删除：\(examples)\(suffix)。\(manifestNote)\(localNote)"
            )
        } else if !localSaved {
            showError(title: "本机配对记录保存失败", message: "归档副本已删除，但本机记录未能保存。请检查应用数据目录。")
        } else if manifestSaved {
            lastSaved = "已清空 \(Self.timeString())"
            let missingNote = cleanup.missingCount > 0 ? "，另有 \(cleanup.missingCount) 个文件原本不存在" : ""
            statusMessage = "已删除 \(cleanup.deletedCount) 个归档副本\(missingNote)，并更新 JSON / Markdown 清单"
        }
    }

    func saveManifest(showMessage: Bool = true) -> Bool {
        guard let destinationDirectoryURL else {
            showError(title: "还没有归档目录", message: "请先选择一个归档目录，再保存清单。")
            return false
        }

        let manifest = currentManifest()
        do {
            try writeManifest(manifest, to: destinationDirectoryURL)
            lastSaved = "已保存 \(Self.timeString())"
            if showMessage {
                statusMessage = "清单已保存到 \(destinationDirectoryURL.lastPathComponent)"
            }
            return true
        } catch {
            showError(title: "保存清单失败", message: error.localizedDescription)
            return false
        }
    }

    func revealManifest() {
        guard let destinationDirectoryURL else {
            showError(title: "还没有归档位置", message: "请先选择归档文件夹，才能在 Finder 中定位 JSON 清单。")
            return
        }
        guard saveManifest(showMessage: false) else { return }
        let url = destinationDirectoryURL.appendingPathComponent("broll-manifest.json")
        guard revealInFinder(url) else { return }
        statusMessage = "已在 Finder 中定位 JSON 清单"
    }

    @discardableResult
    func revealInFinder(_ url: URL) -> Bool {
        do {
            try FinderTabOpener.reveal(url)
            return true
        } catch let error as FinderTabError {
            showError(
                title: "无法在 Finder 标签页中定位",
                message: error.localizedDescription,
                action: error.alertAction
            )
            return false
        } catch {
            showError(title: "无法在 Finder 标签页中定位", message: error.localizedDescription)
            return false
        }
    }

    func openAccessibilitySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        guard NSWorkspace.shared.open(settingsURL) else {
            showError(
                title: "无法打开辅助功能设置",
                message: "请手动前往“系统设置 > 隐私与安全性 > 辅助功能”，启用 B-roll 配对台。"
            )
            return
        }

        statusMessage = "请在辅助功能中启用 B-roll 配对台，然后返回重试"
    }

    func previewManifest() {
        do {
            let data = try encodedJSON(currentManifest())
            manifestPreviewText = String(decoding: data, as: UTF8.self)
            isManifestPreviewPresented = true
        } catch {
            showError(title: "无法预览 JSON 清单", message: error.localizedDescription)
        }
    }

    func importScript() {
        let panel = NSOpenPanel()
        panel.title = "导入文案"
        panel.message = "选择 .txt 或 .md 文稿"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            scriptText = try String(contentsOf: url, encoding: .utf8)
            preservesEmptyAnchors = false
            parseScript()
            statusMessage = "已导入文案：\(url.lastPathComponent)"
        } catch {
            showError(title: "导入文案失败", message: error.localizedDescription)
        }
    }

    func reveal(_ asset: BrollAsset) {
        guard let destinationDirectoryURL else { return }
        let url = destinationDirectoryURL.appendingPathComponent(asset.outputName)
        revealInFinder(url)
    }

    func sourceFile(for asset: BrollAsset) -> SourceFile? {
        sourceFilesByName[asset.sourceName]
    }

    func jumpToSourceFile(for asset: BrollAsset) {
        guard let file = sourceFile(for: asset) else { return }
        mediaFilter = .all
        selectedSourceFileURL = file.url
        sourceFileJumpID = UUID()
    }

    func revealSourceDirectory() {
        revealDirectory(sourceDirectoryURL)
    }

    func revealDestinationDirectory() {
        revealDirectory(destinationDirectoryURL)
    }

    func attach(urls: [URL], to rowID: String) async {
        guard !isBusy else { return }
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard isPrefixValid else {
            showError(title: "请填写命名前缀", message: "绑定素材前，请先在左侧“归档设置”中填写命名前缀。")
            return
        }
        guard sourceDirectoryURL != nil else {
            showError(title: "请先选择素材来源", message: "绑定素材前，请先在“素材目录”栏头选择素材来源文件夹。")
            return
        }
        guard destinationDirectoryURL != nil else {
            showError(title: "请先选择归档位置", message: "绑定素材前，请先在左侧“归档设置”中选择归档文件夹。")
            return
        }

        let mediaURLs = urls.filter { mediaKind(for: $0) != nil }
        guard !mediaURLs.isEmpty else {
            showError(title: "没有识别到素材", message: "请拖入图片或视频文件。")
            return
        }

        let undoState = makeUndoSnapshot()

        isBusy = true
        dropFeedback.isFileDragActive = false
        defer { isBusy = false }

        let prefixValue = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixPart = "\(ScriptParser.sanitizePart(prefixValue, maxLength: 30))_"
        let label = ScriptParser.sanitizePart(row.text, maxLength: 24)
        let baseCode = "BR\(String(format: "%03d", row.index))"
        var copiedCount = 0
        var skippedCount = 0

        for sourceURL in mediaURLs {
            let sourceName = sourceURL.lastPathComponent
            if assets(for: rowID).contains(where: { $0.sourceName == sourceName }) {
                skippedCount += 1
                continue
            }

            let baseName = "\(prefixPart)\(baseCode)_\(label)\(ScriptParser.extensionForFileName(sourceName))"
            let outputName = uniqueOutputName(baseName)
            guard let destinationDirectoryURL else { return }
            let outputURL = destinationDirectoryURL.appendingPathComponent(outputName)
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()

            do {
                statusMessage = "正在归档：\(sourceName)"
                try await copyFile(from: sourceURL, to: outputURL)
                let asset = BrollAsset(
                    id: "\(row.id)-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.lowercased())",
                    anchorKey: row.id,
                    anchorIndex: row.index,
                    anchorText: row.text,
                    sourceName: sourceName,
                    outputName: outputName,
                    mode: .fs,
                    targetTrack: "V2",
                    audio: "mute",
                    copiedAt: ISO8601DateFormatter().string(from: Date())
                )
                assignments[rowID, default: []].append(asset)
                rollTypeOverrides[rowID] = .bRoll
                copiedCount += 1
            } catch {
                showError(title: "归档失败：\(sourceName)", message: error.localizedDescription)
            }

            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard copiedCount > 0 else {
            if skippedCount > 0 {
                statusMessage = "这条素材已经绑定到当前句子"
            }
            return
        }

        rebuildAssignmentIndexes()
        saveAssignments()
        _ = saveManifest(showMessage: false)
        refreshSourceFiles()
        registerUndo(named: "绑定素材", restoring: undoState)
        lastSaved = "本机已保存 \(Self.timeString())"
        let archiveSummary = "本次新增 \(copiedCount) 个；当前清单共 \(assignedCount) 个已绑定素材"
        statusMessage = skippedCount > 0
            ? "\(archiveSummary)，跳过 \(skippedCount) 个重复素材"
            : "\(archiveSummary)，已保存到 \(destinationDirectoryName)"
    }

    func unbind(_ asset: BrollAsset) {
        guard !isBusy else { return }
        guard var rowAssets = assignments[asset.anchorKey] else { return }
        let undoState = makeUndoSnapshot()
        guard let destinationDirectoryURL else {
            showError(title: "无法取消绑定", message: "请先重新选择归档目录，才能删除对应的归档副本并更新清单。")
            return
        }

        let outputFileName = URL(fileURLWithPath: asset.outputName).lastPathComponent
        let archivedURL = destinationDirectoryURL.appendingPathComponent(outputFileName)
        if FileManager.default.fileExists(atPath: archivedURL.path) {
            do {
                try FileManager.default.removeItem(at: archivedURL)
            } catch {
                showError(title: "删除归档副本失败", message: "\(outputFileName) 仍保留在归档目录，因此这次没有取消绑定。\n\(error.localizedDescription)")
                return
            }
        }

        rowAssets.removeAll { $0.id == asset.id }

        if rowAssets.isEmpty {
            assignments.removeValue(forKey: asset.anchorKey)
        } else {
            assignments[asset.anchorKey] = rowAssets
        }

        rebuildAssignmentIndexes()
        saveAssignments()
        let manifestSaved = saveManifest(showMessage: false)
        refreshSourceFiles()
        registerUndo(named: "取消素材绑定", restoring: undoState)
        lastSaved = "本机已保存 \(Self.timeString())"
        statusMessage = manifestSaved
            ? "已取消绑定并删除归档副本：\(asset.sourceName)"
            : "已取消绑定并删除归档副本，但清单更新失败：\(asset.sourceName)"
    }

    private func copyFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }.value
    }

    private func uniqueOutputName(_ baseName: String) -> String {
        guard let destinationDirectoryURL else { return baseName }
        let fileManager = FileManager.default
        let baseURL = destinationDirectoryURL.appendingPathComponent(baseName)
        if !fileManager.fileExists(atPath: baseURL.path) {
            return baseName
        }

        let baseNSString = baseName as NSString
        let stem = baseNSString.deletingPathExtension
        let ext = baseNSString.pathExtension.isEmpty ? "" : ".\(baseNSString.pathExtension)"
        for counter in 2..<1000 {
            let candidate = "\(stem)_\(String(format: "%02d", counter))\(ext)"
            if !fileManager.fileExists(atPath: destinationDirectoryURL.appendingPathComponent(candidate).path) {
                return candidate
            }
        }
        return "\(stem)_\(UUID().uuidString.prefix(8))\(ext)"
    }

    private func mediaKind(for url: URL, contentType: UTType? = nil) -> MediaKind? {
        let pathExtension = url.pathExtension.lowercased()
        if Self.videoExtensions.contains(pathExtension) {
            return .video
        }
        if Self.imageExtensions.contains(pathExtension) {
            return .image
        }

        let type = contentType ?? (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
        if type?.conforms(to: .movie) == true {
            return .video
        }
        if type?.conforms(to: .image) == true {
            return .image
        }
        return nil
    }

    private func rebuildAssignmentIndexes() {
        var names: Set<String> = []
        var assetsByName: [String: [BrollAsset]] = [:]

        for row in rows {
            let assets = assignments[row.id] ?? []
            for asset in assets {
                names.insert(asset.sourceName)
                names.insert(asset.outputName)
                assetsByName[asset.sourceName, default: []].append(asset)
            }
        }

        assignedNamesIndex = names
        assetsBySourceName = assetsByName
    }

    private func makeUndoSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            scriptText: scriptText,
            splitMode: splitMode,
            preservesEmptyAnchors: preservesEmptyAnchors,
            assignments: assignments,
            rollTypeOverrides: rollTypeOverrides
        )
    }

    private func registerUndo(named actionName: String, restoring snapshot: UndoSnapshot) {
        guard let undoManager, makeUndoSnapshot() != snapshot else { return }
        undoManager.registerUndo(withTarget: self) { model in
            let current = model.makeUndoSnapshot()
            model.registerUndo(named: actionName, restoring: current)
            model.applyUndoSnapshot(snapshot)
            model.reconcileArchiveCopies(from: current, to: snapshot)
            model.undoManager?.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func applyUndoSnapshot(_ snapshot: UndoSnapshot) {
        scriptText = snapshot.scriptText
        splitMode = snapshot.splitMode
        preservesEmptyAnchors = snapshot.preservesEmptyAnchors
        parseScript(persist: false)
        assignments = snapshot.assignments
        rollTypeOverrides = snapshot.rollTypeOverrides
        rebuildAssignmentIndexes()
        persistPreferences()
        if destinationDirectoryURL != nil {
            _ = saveManifest(showMessage: false)
        }
        lastSaved = "已撤回到 \(Self.timeString())"
    }

    private func reconcileArchiveCopies(from current: UndoSnapshot, to target: UndoSnapshot) {
        let removedNames = current.archivedNames.subtracting(target.archivedNames)
        if let destinationDirectoryURL {
            for name in removedNames where name == (name as NSString).lastPathComponent {
                try? FileManager.default.removeItem(at: destinationDirectoryURL.appendingPathComponent(name))
            }
        }

        let restoredNames = target.archivedNames.subtracting(current.archivedNames)
        guard !restoredNames.isEmpty,
              let sourceDirectoryURL,
              let destinationDirectoryURL else {
            if !removedNames.isEmpty { refreshSourceFiles() }
            return
        }

        var copies: [ArchiveCopy] = []
        for asset in target.assignments.values.flatMap({ $0 }) where restoredNames.contains(asset.outputName) {
            let sourceURL = sourceDirectoryURL.appendingPathComponent(asset.sourceName)
            let destinationURL = destinationDirectoryURL.appendingPathComponent(asset.outputName)
            guard !FileManager.default.fileExists(atPath: destinationURL.path),
                  FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            copies.append(ArchiveCopy(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                didStartAccess: sourceURL.startAccessingSecurityScopedResource(),
                outputName: asset.outputName
            ))
        }

        guard !copies.isEmpty else {
            if !removedNames.isEmpty { refreshSourceFiles() }
            statusMessage = "撤回了绑定记录；无法从当前素材目录恢复已删除的归档副本"
            return
        }

        statusMessage = "正在恢复已删除的归档副本…"
        let copyTask = Task.detached(priority: .utility) {
            var failedNames: [String] = []
            defer {
                for copy in copies where copy.didStartAccess {
                    copy.sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            for copy in copies {
                do {
                    try FileManager.default.copyItem(at: copy.sourceURL, to: copy.destinationURL)
                } catch {
                    failedNames.append(copy.outputName)
                }
            }
            return failedNames
        }

        Task { @MainActor [weak self] in
            let failedNames = await copyTask.value
            guard let self else { return }
            self.refreshSourceFiles()
            if !failedNames.isEmpty {
                self.showError(
                    title: "归档副本未能全部恢复",
                    message: "撤回记录已恢复，但以下文件复制失败：\(failedNames.prefix(3).joined(separator: "、"))"
                )
            } else {
                self.statusMessage = "已恢复 \(copies.count) 个归档副本"
            }
        }
    }

    private func currentManifest() -> BrollManifest {
        BrollManifest(
            defaultAudio: "mute",
            placements: rows.compactMap { row in
                let rowAssets = assets(for: row.id)
                guard !rowAssets.isEmpty else { return nil }
                return ManifestPlacement(
                    id: "BR\(String(format: "%03d", row.index))",
                    text: row.text,
                    files: rowAssets.map(\.outputName)
                )
            }
        )
    }

    private func encodedJSON(_ manifest: BrollManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private func writeManifest(_ manifest: BrollManifest, to directoryURL: URL) throws {
        try encodedJSON(manifest).write(
            to: directoryURL.appendingPathComponent("broll-manifest.json"),
            options: .atomic
        )
        try manifestMarkdown(manifest).write(
            to: directoryURL.appendingPathComponent("broll-manifest.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func manifestMarkdown(_ manifest: BrollManifest) -> String {
        var lines = [
            "# B-roll placement map",
            "",
            "- Default video audio: \(manifest.defaultAudio)",
            "- Track: choose an available track above the matching A-roll in the current ChatCut timeline",
            "",
            "| ID | Anchor text | B-roll file |",
            "|---|---|---|"
        ]

        for placement in manifest.placements {
            for file in placement.files {
                lines.append("| \(placement.id) | \(placement.text.replacingOccurrences(of: "|", with: "\\|")) | \(file) |")
            }
        }

        lines.append(contentsOf: [
            "",
            "## Codex handoff",
            "",
            "读取同目录的 `broll-manifest.json`，按 text 在当前最终 A-roll 中定位。将 files 中的素材放到对应位置上方的可用轨道；同一文案有多个文件时，按列表顺序处理并结合当前时间线安排轨道。视频静音，不修改 A-roll。",
            ""
        ])
        return lines.joined(separator: "\n")
    }

    private func restoreManifestFromDestination() {
        guard let destinationDirectoryURL else { return }
        let manifestURL = destinationDirectoryURL.appendingPathComponent("broll-manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(BrollManifest.self, from: data)
            var changed = false
            for placement in manifest.placements {
                guard let row = matchingRow(for: placement) else { continue }
                let fileNames = placement.files.filter { file in
                    !file.isEmpty && file == (file as NSString).lastPathComponent && file != "." && file != ".."
                }
                let assets = fileNames.map { file in
                    BrollAsset(
                        id: "manifest-\(row.id)-\(file)",
                        anchorKey: row.id,
                        anchorIndex: row.index,
                        anchorText: row.text,
                        sourceName: file,
                        outputName: file,
                        mode: .fs,
                        targetTrack: "",
                        audio: manifest.defaultAudio,
                        copiedAt: ""
                    )
                }
                changed = mergeManifestAssets(assets, into: row) || changed
            }
            if changed {
                rebuildAssignmentIndexes()
                saveAssignments()
                lastSaved = "已从 manifest 恢复"
            }
        } catch {
            statusMessage = "无法读取目标目录中的 manifest：\(error.localizedDescription)"
        }
    }

    private func assetIdentity(_ asset: BrollAsset) -> String {
        "\(asset.anchorKey)|\(asset.outputName)"
    }

    private func mergeManifestAssets(_ assets: [BrollAsset], into row: AnchorRow) -> Bool {
        var current = assignments[row.id] ?? []
        var known = Set(current.map(assetIdentity))
        var changed = false
        for asset in assets where !known.contains(assetIdentity(asset)) {
            current.append(asset)
            known.insert(assetIdentity(asset))
            changed = true
        }
        if !current.isEmpty {
            assignments[row.id] = current
        }
        return changed
    }

    private func matchingRow(for placement: ManifestPlacement) -> AnchorRow? {
        let textMatches = rows.filter { $0.text == placement.text }
        if let index = Int(placement.id.dropFirst(2)),
           let exactMatch = textMatches.first(where: { $0.index == index }) {
            return exactMatch
        }
        return textMatches.count == 1 ? textMatches.first : nil
    }

    private func restoreAssignments() {
        guard let url = assignmentsURL else { return }
        do {
            let data = try Data(contentsOf: url)
            let store = try JSONDecoder().decode(AssignmentStore.self, from: data)
            guard store.version == 1 else { return }
            assignments = store.assignments.mapValues { $0.map(\.fullScreen) }
            rebuildAssignmentIndexes()
            if assignments != store.assignments {
                saveAssignments()
            }
            if assignedCount > 0 {
                lastSaved = "已从本机恢复"
            }
        } catch {
            // A missing or old local cache is a normal first-run state.
        }
    }

    @discardableResult
    private func saveAssignments() -> Bool {
        guard let url = assignmentsURL else { return false }
        do {
            let folderURL = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let store = AssignmentStore(version: 1, assignments: assignments)
            let data = try JSONEncoder().encode(store)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            statusMessage = "本机配对记录保存失败，请保留目标目录中的 manifest"
            return false
        }
    }

    private var assignmentsURL: URL? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return appSupport
            .appendingPathComponent("BrollNamer", isDirectory: true)
            .appendingPathComponent("assignments.json")
    }

    private func saveFavoriteDirectory(_ url: URL, showMessage: Bool = true) {
        let identity = directoryIdentity(for: url)

        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            if let index = savedDirectories.firstIndex(where: { $0.path == identity }) {
                savedDirectories[index].name = url.lastPathComponent
                savedDirectories[index].path = identity
                savedDirectories[index].bookmarkData = bookmarkData
            } else {
                savedDirectories.append(
                    SavedDirectory(
                        id: UUID(),
                        name: url.lastPathComponent,
                        path: identity,
                        bookmarkData: bookmarkData
                    )
                )
            }

            persistSavedDirectories()
            if showMessage {
                statusMessage = "已保存常用目录：\(url.lastPathComponent)"
            }
        } catch {
            showError(title: "保存常用目录失败", message: error.localizedDescription)
        }
    }

    private func restoreSavedDirectories() {
        guard let data = defaults.data(forKey: savedDirectoriesKey) else { return }
        savedDirectories = (try? JSONDecoder().decode([SavedDirectory].self, from: data)) ?? []
    }

    private func persistSavedDirectories() {
        do {
            let data = try JSONEncoder().encode(savedDirectories)
            defaults.set(data, forKey: savedDirectoriesKey)
        } catch {
            statusMessage = "常用目录保存失败"
        }
    }

    private func resolveSavedDirectory(_ savedDirectory: SavedDirectory) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: savedDirectory.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                refreshSavedDirectoryBookmark(for: savedDirectory.id, url: url)
            }
            return url
        } catch {
            return nil
        }
    }

    private func refreshSavedDirectoryBookmark(for id: UUID, url: URL) {
        guard let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ), let index = savedDirectories.firstIndex(where: { $0.id == id }) else {
            return
        }

        savedDirectories[index].name = url.lastPathComponent
        savedDirectories[index].path = directoryIdentity(for: url)
        savedDirectories[index].bookmarkData = bookmarkData
        persistSavedDirectories()
    }

    private func directoryIdentity(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func revealDirectory(_ url: URL?) {
        guard let url else { return }
        revealInFinder(url)
    }

    private func restoreDirectories() {
        if let url = resolvedBookmark(forKey: sourceBookmarkKey) {
            sourceDirectoryURL = url
            sourceAccessActive = url.startAccessingSecurityScopedResource()
        }
        if let url = resolvedBookmark(forKey: destinationBookmarkKey) {
            destinationDirectoryURL = url
            destinationAccessActive = url.startAccessingSecurityScopedResource()
            restoreManifestFromDestination()
            statusMessage = "目标目录：\(url.lastPathComponent)"
        }
        refreshSourceFiles()
    }

    private func activateSourceDirectory(_ url: URL) {
        if sourceDirectoryURL?.standardizedFileURL != url.standardizedFileURL {
            undoManager?.removeAllActions()
        }
        if sourceAccessActive {
            sourceDirectoryURL?.stopAccessingSecurityScopedResource()
        }
        sourceAccessActive = url.startAccessingSecurityScopedResource()
        sourceDirectoryURL = url
        storeBookmark(for: url, key: sourceBookmarkKey)
        refreshSourceFiles()
    }

    private func activateDestinationDirectory(_ url: URL) {
        if destinationDirectoryURL?.standardizedFileURL != url.standardizedFileURL {
            undoManager?.removeAllActions()
        }
        if destinationAccessActive {
            destinationDirectoryURL?.stopAccessingSecurityScopedResource()
        }
        destinationAccessActive = url.startAccessingSecurityScopedResource()
        destinationDirectoryURL = url
        storeBookmark(for: url, key: destinationBookmarkKey)
    }

    private func storeBookmark(for url: URL, key: String) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: key)
        } catch {
            statusMessage = "无法记住目录权限，下次打开时需要重新选择目录"
        }
    }

    private func resolvedBookmark(forKey key: String) -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                storeBookmark(for: url, key: key)
            }
            return url
        } catch {
            return nil
        }
    }

    private func showError(title: String, message: String, action: AppAlertAction? = nil) {
        statusMessage = message
        alert = AppAlert(title: title, message: message, action: action)
    }

    private static func timeString() -> String {
        DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
    }
}

private enum FinderTabOpener {
    static func reveal(_ url: URL) throws {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw FinderTabError.accessibilityPermissionRequired
        }

        let targetURL = url.standardizedFileURL
        let isDirectory = (try? targetURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folderURL = isDirectory ? targetURL : targetURL.deletingLastPathComponent()
        let shouldSelectTarget = !isDirectory && FileManager.default.fileExists(atPath: targetURL.path)
        let folderPath = appleScriptString(folderURL.path)
        let targetPath = appleScriptString(targetURL.path)

        let selectionCommand = shouldSelectTarget
            ? "set selection to {(POSIX file \"\(targetPath)\") as alias}"
            : ""

        let source = """
        tell application "Finder"
            activate
            set existingWindowCount to count of Finder windows
        end tell

        if existingWindowCount > 0 then
            tell application "System Events"
                tell process "Finder"
                    keystroke "t" using {command down}
                end tell
            end tell
            delay 0.12
        else
            tell application "Finder"
                make new Finder window
            end tell
        end if

        tell application "Finder"
            set target of front Finder window to (POSIX file "\(folderPath)" as alias)
            \(selectionCommand)
        end tell
        """

        var errorInfo: NSDictionary?
        guard NSAppleScript(source: source)?.executeAndReturnError(&errorInfo) != nil else {
            throw FinderTabError.automationFailed(errorInfo?.description ?? "Finder 自动化未完成。")
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

private enum FinderTabError: LocalizedError {
    case accessibilityPermissionRequired
    case automationFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "请在辅助功能设置中启用 B-roll 配对台，然后返回这里再试一次。"
        case .automationFailed(let details):
            return "请允许 B-roll 配对台控制 Finder 和 System Events，然后重试。\n\n\(details)"
        }
    }

    var alertAction: AppAlertAction? {
        switch self {
        case .accessibilityPermissionRequired:
            return .openAccessibilitySettings
        case .automationFailed:
            return nil
        }
    }
}
