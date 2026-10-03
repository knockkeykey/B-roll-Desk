import Foundation
import UniformTypeIdentifiers

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "白天"
        case .dark: return "黑夜"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var next: AppTheme {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }
}

enum SplitMode: String, CaseIterable, Codable, Identifiable {
    case line
    case sentence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return "按换行拆分"
        case .sentence: return "按句号自动拆分"
        }
    }
}

enum AnchorRollType: String, Codable, Equatable {
    case aRoll
    case bRoll

    var title: String {
        switch self {
        case .aRoll: return "A-roll"
        case .bRoll: return "B-roll"
        }
    }
}

enum BrollProductionMethod: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case undecided
    case liveAction
    case animation
    case aiVideo
    case imageMotion
    case stockFootage
    case screenRecording
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .undecided: return "未确定"
        case .liveAction: return "实拍"
        case .animation: return "动画"
        case .aiVideo: return "AI 生成视频"
        case .imageMotion: return "图片＋动效"
        case .stockFootage: return "搜索现成素材"
        case .screenRecording: return "屏幕录制"
        case .other: return "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .undecided: return "questionmark.circle"
        case .liveAction: return "camera"
        case .animation: return "sparkles.rectangle.stack"
        case .aiVideo: return "wand.and.stars"
        case .imageMotion: return "photo.on.rectangle.angled"
        case .stockFootage: return "magnifyingglass"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .other: return "ellipsis.circle"
        }
    }
}

enum BrollPreparationStatus: String, CaseIterable, Codable, Equatable, Identifiable {
    case pending
    case ready
    case bound

    static let selectableCases: [BrollPreparationStatus] = [.pending, .ready]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "待准备"
        case .ready: return "素材就绪"
        case .bound: return "已绑定"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "circle"
        case .ready: return "checkmark.circle.fill"
        case .bound: return "link.circle.fill"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "inProgress" {
            self = .pending
            return
        }
        guard let status = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown B-roll preparation status: \(rawValue)"
            )
        }
        self = status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum BrollMode: String, Codable {
    case fs = "FS"
    // Kept only so older manifests can still be decoded and migrated.
    case pip = "PIP"
}

enum MediaKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case video
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "视频"
        case .image: return "图片"
        }
    }

    var systemImage: String {
        switch self {
        case .video: return "film"
        case .image: return "photo"
        }
    }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all
    case video
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .video: return "视频"
        case .image: return "图片"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .video: return "film"
        case .image: return "photo"
        }
    }
}

struct AnchorRow: Identifiable, Hashable {
    let id: String
    let index: Int
    let text: String
}

struct ARollPacingHint: Equatable {
    let startRowIndex: Int
    let endRowIndex: Int
    let cumulativeCharacterCount: Int
    let totalCharacterCount: Int

    var cumulativeSeconds: Double { ARollPacing.seconds(for: cumulativeCharacterCount) }
    var totalSeconds: Double { ARollPacing.seconds(for: totalCharacterCount) }
}

enum ARollPacing {
    static let charactersPerMinute = 350.0
    static let maximumContinuousSeconds = 5.0

    static func seconds(for characterCount: Int) -> Double {
        Double(characterCount) * 60 / charactersPerMinute
    }

    /// Punctuation, whitespace and visual symbols are not spoken characters.
    static func spokenCharacterCount(in text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if character.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                count += 1
            }
        }
    }

    /// Analyze the complete script before any search or view filters are applied.
    static func hints(
        for rows: [AnchorRow],
        rollType: (String) -> AnchorRollType
    ) -> [String: ARollPacingHint] {
        var result: [String: ARollPacingHint] = [:]
        var run: [(row: AnchorRow, cumulativeCount: Int)] = []
        var characterCount = 0

        func finishRun() {
            guard let first = run.first, let last = run.last else { return }
            for entry in run where seconds(for: entry.cumulativeCount) > maximumContinuousSeconds {
                result[entry.row.id] = ARollPacingHint(
                    startRowIndex: first.row.index,
                    endRowIndex: last.row.index,
                    cumulativeCharacterCount: entry.cumulativeCount,
                    totalCharacterCount: characterCount
                )
            }
        }

        for row in rows {
            let count = spokenCharacterCount(in: row.text)
            // Empty anchors cannot provide a visual break, even when marked B-roll.
            guard count > 0 else { continue }
            if rollType(row.id) == .bRoll {
                finishRun()
                run.removeAll(keepingCapacity: true)
                characterCount = 0
            } else {
                characterCount += count
                run.append((row, characterCount))
            }
        }
        finishRun()
        return result
    }
}

struct BrollAsset: Identifiable, Codable, Hashable {
    let id: String
    let anchorKey: String
    let anchorIndex: Int
    let anchorText: String
    let sourceName: String
    let sourceDirectoryID: String?
    let sourceRelativePath: String?
    let outputName: String
    let mode: BrollMode
    let targetTrack: String
    let audio: String
    let copiedAt: String

    var fullScreen: BrollAsset {
        guard mode != .fs else { return self }
        return BrollAsset(
            id: id,
            anchorKey: anchorKey,
            anchorIndex: anchorIndex,
            anchorText: anchorText,
            sourceName: sourceName,
            sourceDirectoryID: sourceDirectoryID,
            sourceRelativePath: sourceRelativePath,
            outputName: outputName,
            mode: .fs,
            targetTrack: targetTrack,
            audio: audio,
            copiedAt: copiedAt
        )
    }
}

enum AnchorAssignmentMigration {
    static func migrate(
        _ assignments: [String: [BrollAsset]],
        from oldRows: [AnchorRow],
        to newRows: [AnchorRow],
        sourceIndices: [[Int]]
    ) -> [String: [BrollAsset]] {
        let visibleKeys = Set(oldRows.map(\.id))
        var migrated = assignments.filter { !visibleKeys.contains($0.key) }

        for (offset, row) in newRows.enumerated() where sourceIndices.indices.contains(offset) {
            let assets = sourceIndices[offset].flatMap { sourceIndex -> [BrollAsset] in
                guard oldRows.indices.contains(sourceIndex) else { return [] }
                return assignments[oldRows[sourceIndex].id] ?? []
            }
            guard !assets.isEmpty else { continue }
            migrated[row.id] = assets.map { asset in
                BrollAsset(
                    id: asset.id,
                    anchorKey: row.id,
                    anchorIndex: row.index,
                    anchorText: row.text,
                    sourceName: asset.sourceName,
                    sourceDirectoryID: asset.sourceDirectoryID,
                    sourceRelativePath: asset.sourceRelativePath,
                    outputName: asset.outputName,
                    mode: asset.mode,
                    targetTrack: asset.targetTrack,
                    audio: asset.audio,
                    copiedAt: asset.copiedAt
                )
            }
        }
        return migrated
    }
}

enum AnchorNoteMigration {
    static func migrate(
        _ notes: [String: String],
        from oldRows: [AnchorRow],
        to newRows: [AnchorRow],
        sourceIndices: [[Int]]
    ) -> [String: String] {
        var migrated: [String: String] = [:]

        for (offset, row) in newRows.enumerated() where sourceIndices.indices.contains(offset) {
            let noteParts = sourceIndices[offset].compactMap { sourceIndex -> String? in
                guard oldRows.indices.contains(sourceIndex),
                      let note = notes[oldRows[sourceIndex].id],
                      !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return note
            }
            if !noteParts.isEmpty {
                migrated[row.id] = noteParts.joined(separator: "\n\n")
            }
        }

        return migrated
    }

    static func migrateAfterScriptEdit(
        _ notes: [String: String],
        from oldRows: [AnchorRow],
        to newRows: [AnchorRow]
    ) -> [String: String] {
        guard !notes.isEmpty, !oldRows.isEmpty else { return [:] }

        let difference = newRows.map(\.id).difference(from: oldRows.map(\.id))
        let removedOldIndices = Set(difference.compactMap { change -> Int? in
            guard case let .remove(offset, _, _) = change else { return nil }
            return offset
        })
        let insertedNewIndices = Set(difference.compactMap { change -> Int? in
            guard case let .insert(offset, _, _) = change else { return nil }
            return offset
        })

        var sourceIndices = Array(repeating: [Int](), count: newRows.count)
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldRows.count || newIndex < newRows.count {
            let oldIsChanged = removedOldIndices.contains(oldIndex)
            let newIsChanged = insertedNewIndices.contains(newIndex)

            if oldIndex < oldRows.count, newIndex < newRows.count,
               !oldIsChanged, !newIsChanged {
                sourceIndices[newIndex] = [oldIndex]
                oldIndex += 1
                newIndex += 1
                continue
            }

            var oldGap: [Int] = []
            while oldIndex < oldRows.count, removedOldIndices.contains(oldIndex) {
                oldGap.append(oldIndex)
                oldIndex += 1
            }

            var newGap: [Int] = []
            while newIndex < newRows.count, insertedNewIndices.contains(newIndex) {
                newGap.append(newIndex)
                newIndex += 1
            }

            if oldGap.count == newGap.count {
                for (sourceIndex, targetIndex) in zip(oldGap, newGap) {
                    sourceIndices[targetIndex] = [sourceIndex]
                }
            } else if oldGap.count == 1, let sourceIndex = oldGap.first, let targetIndex = newGap.first {
                sourceIndices[targetIndex] = [sourceIndex]
            } else if newGap.count == 1, let targetIndex = newGap.first {
                sourceIndices[targetIndex] = oldGap
            }
        }

        return migrate(notes, from: oldRows, to: newRows, sourceIndices: sourceIndices)
    }
}

struct ManifestPlacement: Codable, Hashable {
    let id: String
    let text: String
    let files: [String]
}

struct BrollManifest: Codable, Hashable {
    let defaultAudio: String
    let placements: [ManifestPlacement]
}

struct CodexBrollPlacement: Codable, Hashable {
    let text: String
    let files: [String]
}

struct CodexBrollManifest: Codable, Hashable {
    let placements: [CodexBrollPlacement]
}

struct AssignmentStore: Codable {
    let version: Int
    let assignments: [String: [BrollAsset]]
}

struct ProjectSourceDirectory: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let path: String
    let bookmarkData: Data?

    init(id: String = UUID().uuidString.lowercased(), name: String, path: String, bookmarkData: Data?) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case bookmarkData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? path
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
    }
}

struct BrollProjectSettings: Codable {
    let formatVersion: Int
    let projectID: String
    var prefix: String
    var scriptRelativePath: String
    var sourceDirectories: [ProjectSourceDirectory]
    var splitMode: SplitMode
    var preservesEmptyAnchors: Bool
    var anchorNotes: [String: String]
    var rollTypeOverrides: [String: AnchorRollType]
    var capturedBrollRowIDs: [String]
    var brollProductionMethods: [String: BrollProductionMethod]
    var brollPreparationStatuses: [String: BrollPreparationStatus]
    var assignments: [String: [BrollAsset]]
    var animationTasks: [AnimationTask]

    init(
        projectID: String = UUID().uuidString.lowercased(),
        prefix: String = "",
        scriptRelativePath: String = "../A-roll/正确文案.txt",
        sourceDirectories: [ProjectSourceDirectory] = [],
        splitMode: SplitMode = .line,
        preservesEmptyAnchors: Bool = true,
        anchorNotes: [String: String] = [:],
        rollTypeOverrides: [String: AnchorRollType] = [:],
        capturedBrollRowIDs: [String] = [],
        brollProductionMethods: [String: BrollProductionMethod] = [:],
        brollPreparationStatuses: [String: BrollPreparationStatus] = [:],
        assignments: [String: [BrollAsset]] = [:],
        animationTasks: [AnimationTask] = []
    ) {
        self.formatVersion = animationTasks.isEmpty ? 3 : 4
        self.projectID = projectID
        self.prefix = prefix
        self.scriptRelativePath = scriptRelativePath
        self.sourceDirectories = sourceDirectories
        self.splitMode = splitMode
        self.preservesEmptyAnchors = preservesEmptyAnchors
        self.anchorNotes = anchorNotes
        self.rollTypeOverrides = rollTypeOverrides
        self.capturedBrollRowIDs = capturedBrollRowIDs
        self.brollProductionMethods = brollProductionMethods
        self.brollPreparationStatuses = brollPreparationStatuses
        self.assignments = assignments
        self.animationTasks = animationTasks
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case projectID
        case prefix
        case scriptRelativePath
        case sourceDirectories
        case sourceDirectory
        case splitMode
        case preservesEmptyAnchors
        case anchorNotes
        case rollTypeOverrides
        case capturedBrollRowIDs
        case brollProductionMethods
        case brollPreparationStatuses
        case assignments
        case animationTasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID) ?? UUID().uuidString.lowercased()
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        scriptRelativePath = try container.decodeIfPresent(String.self, forKey: .scriptRelativePath)
            ?? "../A-roll/正确文案.txt"
        if let directories = try container.decodeIfPresent([ProjectSourceDirectory].self, forKey: .sourceDirectories) {
            sourceDirectories = directories
        } else if let legacyDirectory = try container.decodeIfPresent(ProjectSourceDirectory.self, forKey: .sourceDirectory) {
            sourceDirectories = [legacyDirectory]
        } else {
            sourceDirectories = []
        }
        splitMode = try container.decodeIfPresent(SplitMode.self, forKey: .splitMode) ?? .line
        preservesEmptyAnchors = try container.decodeIfPresent(Bool.self, forKey: .preservesEmptyAnchors) ?? true
        anchorNotes = try container.decodeIfPresent([String: String].self, forKey: .anchorNotes) ?? [:]
        rollTypeOverrides = try container.decodeIfPresent([String: AnchorRollType].self, forKey: .rollTypeOverrides) ?? [:]
        capturedBrollRowIDs = try container.decodeIfPresent([String].self, forKey: .capturedBrollRowIDs) ?? []
        brollProductionMethods = try container.decodeIfPresent(
            [String: BrollProductionMethod].self,
            forKey: .brollProductionMethods
        ) ?? [:]
        brollPreparationStatuses = try container.decodeIfPresent(
            [String: BrollPreparationStatus].self,
            forKey: .brollPreparationStatuses
        ) ?? [:]
        assignments = try container.decodeIfPresent([String: [BrollAsset]].self, forKey: .assignments) ?? [:]
        animationTasks = try container.decodeIfPresent([AnimationTask].self, forKey: .animationTasks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(prefix, forKey: .prefix)
        try container.encode(scriptRelativePath, forKey: .scriptRelativePath)
        try container.encode(sourceDirectories, forKey: .sourceDirectories)
        try container.encode(splitMode, forKey: .splitMode)
        try container.encode(preservesEmptyAnchors, forKey: .preservesEmptyAnchors)
        try container.encode(anchorNotes, forKey: .anchorNotes)
        try container.encode(rollTypeOverrides, forKey: .rollTypeOverrides)
        try container.encode(capturedBrollRowIDs, forKey: .capturedBrollRowIDs)
        try container.encode(brollProductionMethods, forKey: .brollProductionMethods)
        try container.encode(brollPreparationStatuses, forKey: .brollPreparationStatuses)
        try container.encode(assignments, forKey: .assignments)
        try container.encode(animationTasks, forKey: .animationTasks)
    }
}

struct ArchiveCleanupResult: Sendable {
    var deletedCount = 0
    var missingCount = 0
    var failedNames: Set<String> = []
}

enum ArchiveCleaner {
    static func discoverCopies(in directoryURL: URL, mediaExtensions: Set<String>) throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return Set(urls.compactMap { url in
            guard mediaExtensions.contains(url.pathExtension.lowercased()),
                  url.lastPathComponent.range(
                    of: #"^.+_BR[0-9]{3,}_.+\.[^.]+$"#,
                    options: .regularExpression
                  ) != nil,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url.lastPathComponent
        })
    }

    static func removeCopies(named outputNames: Set<String>, from directoryURL: URL) -> ArchiveCleanupResult {
        let fileManager = FileManager.default
        var result = ArchiveCleanupResult()

        for outputName in outputNames.sorted() {
            guard !outputName.isEmpty,
                  outputName == (outputName as NSString).lastPathComponent,
                  outputName != ".", outputName != ".." else {
                result.failedNames.insert(outputName)
                continue
            }

            let archivedURL = directoryURL.appendingPathComponent(outputName)
            do {
                let values = try archivedURL.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory != true else {
                    result.failedNames.insert(outputName)
                    continue
                }
                try fileManager.removeItem(at: archivedURL)
                result.deletedCount += 1
            } catch {
                let fileError = error as NSError
                if fileError.domain == NSCocoaErrorDomain &&
                    [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(fileError.code) {
                    result.missingCount += 1
                } else {
                    result.failedNames.insert(outputName)
                }
            }
        }

        return result
    }
}

struct SourceFile: Identifiable, Hashable, Sendable {
    let url: URL
    let byteCount: Int64
    let kind: MediaKind
    let modificationDate: Date?
    let sourceDirectoryID: String
    let sourceDirectoryName: String
    let relativePath: String

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var cacheIdentity: String {
        let modified = modificationDate.map { String($0.timeIntervalSince1970.bitPattern) } ?? "unknown"
        return "\(url.standardizedFileURL.path)|\(byteCount)|\(modified)"
    }
}

enum SourceFileScanner {
    static func scan(
        in directoryURL: URL,
        sourceDirectoryID: String,
        videoExtensions: Set<String>,
        imageExtensions: Set<String>
    ) throws -> [SourceFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentTypeKey,
            .contentModificationDateKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        var files: [SourceFile] = []
        files.reserveCapacity(urls.count)

        for (index, url) in urls.enumerated() {
            if index.isMultiple(of: 128) {
                try Task<Never, Never>.checkCancellation()
            }

            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile != false else { continue }

            let pathExtension = url.pathExtension.lowercased()
            let kind: MediaKind?
            if videoExtensions.contains(pathExtension) {
                kind = .video
            } else if imageExtensions.contains(pathExtension) {
                kind = .image
            } else if values?.contentType?.conforms(to: .movie) == true {
                kind = .video
            } else if values?.contentType?.conforms(to: .image) == true {
                kind = .image
            } else {
                kind = nil
            }

            guard let kind else { continue }
            files.append(
                SourceFile(
                    url: url,
                    byteCount: Int64(values?.fileSize ?? 0),
                    kind: kind,
                    modificationDate: values?.contentModificationDate,
                    sourceDirectoryID: sourceDirectoryID,
                    sourceDirectoryName: directoryURL.lastPathComponent,
                    relativePath: url.lastPathComponent
                )
            )
        }

        try Task<Never, Never>.checkCancellation()
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return files
    }
}

struct SavedDirectory: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var bookmarkData: Data
}

enum AppAlertAction: Equatable {
    case openAccessibilitySettings
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: AppAlertAction?

    init(title: String, message: String, action: AppAlertAction? = nil) {
        self.title = title
        self.message = message
        self.action = action
    }
}

enum ScriptParser {
    static func split(_ raw: String, mode: SplitMode, preservingEmptyLines: Bool = false) -> [String] {
        guard !raw.isEmpty else { return [] }
        if mode == .line && preservingEmptyLines {
            return raw
                .replacingOccurrences(of: "\r", with: "")
                .components(separatedBy: "\n")
        }

        let normalized = raw.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        switch mode {
        case .line:
            return normalized
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case .sentence:
            return normalized
                .components(separatedBy: "\n")
                .flatMap(splitLineIntoSentences)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    private static func splitLineIntoSentences(_ line: String) -> [String] {
        var sentences: [String] = []
        var buffer = ""
        let punctuation = Set("。！？!?".map(String.Element.init))

        for character in line {
            buffer.append(character)
            if punctuation.contains(character) {
                sentences.append(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !buffer.isEmpty {
            sentences.append(buffer)
        }
        return sentences
    }

    // Matches the browser tool's FNV-1a hash over JavaScript UTF-16 code units.
    static func hash(_ value: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for codeUnit in value.utf16 {
            hash ^= UInt32(codeUnit)
            hash = hash &* 1_677_7619
        }
        return String(hash, radix: 16)
    }

    static func key(for text: String, occurrence: Int) -> String {
        "\(hash(text))-\(occurrence)"
    }

    static func sanitizePart(_ value: String, maxLength: Int = 24) -> String {
        let normalized = value.precomposedStringWithCompatibilityMapping
        let invalidScalars = Set("\\/:*?\"<>|".unicodeScalars)
        var output = ""

        for scalar in normalized.unicodeScalars {
            let properties = scalar.properties
            if invalidScalars.contains(scalar)
                || properties.isWhitespace
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar) {
                output.append("_")
            } else {
                output.append(String(scalar))
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let limited = String(trimmed.prefix(maxLength))
        return limited.isEmpty ? "未命名" : limited
    }

    static func extensionForFileName(_ fileName: String) -> String {
        let pathExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard !pathExtension.isEmpty, pathExtension.count <= 8,
              pathExtension.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }) else {
            return ".mp4"
        }
        return ".\(pathExtension)"
    }
}

enum MediaFormatting {
    static func bytes(_ byteCount: Int64) -> String {
        guard byteCount > 0 else { return "未知大小" }
        let bytes = Double(byteCount)
        if bytes < 1024 * 1024 {
            return "\(Int((bytes / 1024).rounded())) KB"
        }
        if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", bytes / (1024 * 1024))
        }
        return String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
    }
}
