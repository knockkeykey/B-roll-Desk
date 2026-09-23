import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "webm", "avi", "mkv", "mts", "m2ts"
    ]
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp"
    ]

    @Published var scriptText: String
    @Published var splitMode: SplitMode
    @Published var prefix: String
    @Published var defaultMode: BrollMode
    @Published var selectedAnchorID: String?
    @Published var anchorSearchText = ""
    let dropFeedback = DropFeedbackModel()
    @Published var selectedSourceFileURL: URL?
    @Published var mediaFilter: MediaFilter = .all
    @Published var isScriptEditorPresented = false
    @Published var isClearConfirmationPresented = false
    @Published var isBusy = false
    @Published var statusMessage = "请设置素材来源和归档位置"
    @Published var lastSaved = "尚未保存"
    @Published var alert: AppAlert?

    @Published private(set) var rows: [AnchorRow] = []
    @Published private(set) var assignments: [String: [BrollAsset]] = [:]
    @Published private(set) var sourceFiles: [SourceFile] = []
    @Published private(set) var sourceDirectoryURL: URL?
    @Published private(set) var destinationDirectoryURL: URL?
    @Published private(set) var savedDirectories: [SavedDirectory] = []

    private let defaults = UserDefaults.standard
    private var sourceAccessActive = false
    private var destinationAccessActive = false

    private let scriptKey = "broll-namer-script"
    private let splitModeKey = "broll-namer-split-mode"
    private let prefixKey = "broll-namer-prefix"
    private let defaultModeKey = "broll-namer-default-mode"
    private let sourceBookmarkKey = "broll-namer-source-bookmark"
    private let destinationBookmarkKey = "broll-namer-destination-bookmark"
    private let savedDirectoriesKey = "broll-namer-saved-directories"

    init() {
        scriptText = defaults.string(forKey: scriptKey) ?? ""
        splitMode = SplitMode(rawValue: defaults.string(forKey: splitModeKey) ?? "line") ?? .line
        prefix = defaults.string(forKey: prefixKey) ?? ""
        defaultMode = BrollMode(rawValue: defaults.string(forKey: defaultModeKey) ?? "FS") ?? .fs

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
        rows.reduce(0) { $0 + (assets(for: $1.id).isEmpty ? 1 : 0) }
    }

    var scriptCharacterCount: Int {
        scriptText.reduce(into: 0) { count, character in
            if !character.isWhitespace {
                count += 1
            }
        }
    }

    var aRollAnchorCount: Int {
        pendingCount
    }

    var bRollAnchorCount: Int {
        rows.count - pendingCount
    }

    var filteredRows: [AnchorRow] {
        let query = anchorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.text.localizedCaseInsensitiveContains(query) || "BR\(String(format: "%03d", $0.index))".localizedCaseInsensitiveContains(query) }
    }

    var visibleSourceFiles: [SourceFile] {
        switch mediaFilter {
        case .all:
            return sourceFiles
        case .video:
            return sourceFiles.filter { $0.kind == .video }
        case .image:
            return sourceFiles.filter { $0.kind == .image }
        }
    }

    func assets(for rowID: String) -> [BrollAsset] {
        assignments[rowID] ?? []
    }

    func isAssigned(_ file: SourceFile) -> Bool {
        assignedNames.contains(file.name)
    }

    var isCurrentSourceDirectorySaved: Bool {
        guard let sourceDirectoryURL else { return false }
        let identity = directoryIdentity(for: sourceDirectoryURL)
        return savedDirectories.contains { $0.path == identity }
    }

    func persistPreferences() {
        defaults.set(scriptText, forKey: scriptKey)
        defaults.set(splitMode.rawValue, forKey: splitModeKey)
        defaults.set(prefix, forKey: prefixKey)
        defaults.set(defaultMode.rawValue, forKey: defaultModeKey)
        saveAssignments()
    }

    func parseScript(persist: Bool = true) {
        let chunks = ScriptParser.split(scriptText, mode: splitMode)
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

        if let selectedAnchorID, rows.contains(where: { $0.id == selectedAnchorID }) == false {
            self.selectedAnchorID = rows.first?.id
        } else if self.selectedAnchorID == nil {
            self.selectedAnchorID = rows.first?.id
        }

        if persist {
            persistPreferences()
        }
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

    func refreshSourceFiles() {
        guard let directoryURL = sourceDirectoryURL else {
            sourceFiles = []
            return
        }

        do {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentTypeKey]
            sourceFiles = try FileManager.default
                .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                .compactMap { url in
                    let values = try? url.resourceValues(forKeys: keys)
                    guard values?.isRegularFile != false else { return nil }
                    guard let kind = mediaKind(for: url, contentType: values?.contentType) else { return nil }
                    return SourceFile(
                        url: url,
                        byteCount: Int64(values?.fileSize ?? 0),
                        kind: kind
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            if let selectedSourceFileURL,
               sourceFiles.contains(where: { $0.url == selectedSourceFileURL }) == false {
                self.selectedSourceFileURL = nil
            }
        } catch {
            sourceFiles = []
            statusMessage = "无法读取素材目录：\(error.localizedDescription)"
        }
    }

    func requestClearAssignments() {
        guard assignedCount > 0 else { return }
        isClearConfirmationPresented = true
    }

    func clearAssignments() {
        assignments.removeAll()
        saveAssignments()
        _ = saveManifest(showMessage: false)
        refreshSourceFiles()
        lastSaved = "配对记录已清空"
        statusMessage = "已清空本次配对记录；目标目录中的视频未删除"
    }

    func saveManifest(showMessage: Bool = true) -> Bool {
        guard let destinationDirectoryURL else {
            showError(title: "还没有归档目录", message: "请先选择一个归档目录，再保存清单。")
            return false
        }

        let manifest = currentManifest()
        do {
            let jsonData = try encodedJSON(manifest)
            try jsonData.write(to: destinationDirectoryURL.appendingPathComponent("broll-manifest.json"), options: .atomic)
            try manifestMarkdown(manifest).write(
                to: destinationDirectoryURL.appendingPathComponent("broll-manifest.md"),
                atomically: true,
                encoding: .utf8
            )
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

    func exportManifest() {
        let panel = NSSavePanel()
        panel.title = "导出 B-roll 清单"
        panel.message = "选择 broll-manifest.json 的保存位置"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "broll-manifest.json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try encodedJSON(currentManifest()).write(to: url, options: .atomic)
            statusMessage = "清单已导出：\(url.lastPathComponent)"
        } catch {
            showError(title: "导出清单失败", message: error.localizedDescription)
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
            parseScript()
            statusMessage = "已导入文案：\(url.lastPathComponent)"
        } catch {
            showError(title: "导入文案失败", message: error.localizedDescription)
        }
    }

    func reveal(_ asset: BrollAsset) {
        guard let destinationDirectoryURL else { return }
        let url = destinationDirectoryURL.appendingPathComponent(asset.outputName)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealSourceDirectory() {
        revealDirectory(sourceDirectoryURL)
    }

    func revealDestinationDirectory() {
        revealDirectory(destinationDirectoryURL)
    }

    func attach(urls: [URL], to rowID: String) async {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard isPrefixValid else {
            showError(title: "请填写期数 / 前缀", message: "绑定素材前，请先在左侧“命名规则”中填写期数或前缀。")
            return
        }
        guard sourceDirectoryURL != nil else {
            showError(title: "请先选择素材来源", message: "绑定素材前，请先在“素材目录”栏头选择素材来源文件夹。")
            return
        }
        guard destinationDirectoryURL != nil else {
            showError(title: "请先选择归档位置", message: "绑定素材前，请先在左侧“目录”中选择归档文件夹。")
            return
        }

        let mediaURLs = urls.filter { mediaKind(for: $0) != nil }
        guard !mediaURLs.isEmpty else {
            showError(title: "没有识别到素材", message: "请拖入图片或视频文件。")
            return
        }

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
                    mode: defaultMode,
                    targetTrack: "V2",
                    audio: "mute",
                    copiedAt: ISO8601DateFormatter().string(from: Date())
                )
                assignments[rowID, default: []].append(asset)
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

        saveAssignments()
        _ = saveManifest(showMessage: false)
        refreshSourceFiles()
        lastSaved = "本机已保存 \(Self.timeString())"
        let archiveSummary = "本次新增 \(copiedCount) 个；当前清单共 \(assignedCount) 个已绑定素材"
        statusMessage = skippedCount > 0
            ? "\(archiveSummary)，跳过 \(skippedCount) 个重复素材"
            : "\(archiveSummary)，已保存到 \(destinationDirectoryName)"
    }

    func unbind(_ asset: BrollAsset) {
        guard var rowAssets = assignments[asset.anchorKey] else { return }
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

        saveAssignments()
        let manifestSaved = saveManifest(showMessage: false)
        refreshSourceFiles()
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

    private var assignedNames: Set<String> {
        Set(rows.flatMap { assets(for: $0.id) }.flatMap { [$0.sourceName, $0.outputName] })
    }

    private func currentManifest() -> BrollManifest {
        BrollManifest(
            schema: "broll-manifest.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            tool: "B-roll 配对台",
            destinationDirectory: destinationDirectoryURL?.lastPathComponent,
            naming: ManifestNaming(
                filenamePattern: "期数或前缀_BR###_文案短句.ext",
                defaultTrack: "V2",
                defaultAudio: "mute",
                copyMode: true
            ),
            anchors: rows.map { row in
                ManifestAnchor(id: row.id, index: row.index, text: row.text, assets: assets(for: row.id))
            }
        )
    }

    private func encodedJSON(_ manifest: BrollManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private func manifestMarkdown(_ manifest: BrollManifest) -> String {
        var lines = [
            "# B-roll placement map",
            "",
            "- Generated: \(manifest.generatedAt)",
            "- Destination: \(manifest.destinationDirectory ?? "not selected")",
            "- Default track: V2",
            "- Default audio: mute",
            "",
            "| ID | Anchor text | Output file | Mode | Track | Audio |",
            "|---|---|---|---|---|---|"
        ]

        for anchor in manifest.anchors {
            if anchor.assets.isEmpty {
                lines.append("| BR\(String(format: "%03d", anchor.index)) | \(anchor.text.replacingOccurrences(of: "|", with: "\\|")) |  |  |  |  |")
                continue
            }
            for asset in anchor.assets {
                lines.append("| BR\(String(format: "%03d", anchor.index)) | \(anchor.text.replacingOccurrences(of: "|", with: "\\|")) | \(asset.outputName) | \(asset.mode.rawValue) | \(asset.targetTrack) | \(asset.audio) |")
            }
        }

        lines.append(contentsOf: [
            "",
            "## Codex handoff",
            "",
            "读取同目录的 `broll-manifest.json`，按 anchor text 在当前最终 A-roll 中定位，再把 output file 放到 V2。不要重新改动 A-roll。",
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
            guard manifest.schema == "broll-manifest.v1" else { return }

            var changed = false
            for anchor in manifest.anchors {
                var current = assignments[anchor.id] ?? []
                var known = Set(current.map(assetIdentity))
                for asset in anchor.assets where !known.contains(assetIdentity(asset)) {
                    current.append(asset)
                    known.insert(assetIdentity(asset))
                    changed = true
                }
                if !current.isEmpty {
                    assignments[anchor.id] = current
                }
            }

            if changed {
                saveAssignments()
                lastSaved = "已从 manifest 恢复"
            }
        } catch {
            statusMessage = "无法读取目标目录中的 manifest：\(error.localizedDescription)"
        }
    }

    private func assetIdentity(_ asset: BrollAsset) -> String {
        asset.id.isEmpty ? "\(asset.outputName)|\(asset.sourceName)" : asset.id
    }

    private func restoreAssignments() {
        guard let url = assignmentsURL else { return }
        do {
            let data = try Data(contentsOf: url)
            let store = try JSONDecoder().decode(AssignmentStore.self, from: data)
            guard store.version == 1 else { return }
            assignments = store.assignments
            if assignedCount > 0 {
                lastSaved = "已从本机恢复"
            }
        } catch {
            // A missing or old local cache is a normal first-run state.
        }
    }

    private func saveAssignments() {
        guard let url = assignmentsURL else { return }
        do {
            let folderURL = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let store = AssignmentStore(version: 1, assignments: assignments)
            let data = try JSONEncoder().encode(store)
            try data.write(to: url, options: .atomic)
        } catch {
            statusMessage = "本机配对记录保存失败，请保留目标目录中的 manifest"
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
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
        if sourceAccessActive {
            sourceDirectoryURL?.stopAccessingSecurityScopedResource()
        }
        sourceAccessActive = url.startAccessingSecurityScopedResource()
        sourceDirectoryURL = url
        storeBookmark(for: url, key: sourceBookmarkKey)
        refreshSourceFiles()
    }

    private func activateDestinationDirectory(_ url: URL) {
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

    private func showError(title: String, message: String) {
        statusMessage = message
        alert = AppAlert(title: title, message: message)
    }

    private static func timeString() -> String {
        DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
    }
}
