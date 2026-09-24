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

struct BrollAsset: Identifiable, Codable, Hashable {
    let id: String
    let anchorKey: String
    let anchorIndex: Int
    let anchorText: String
    let sourceName: String
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

struct ManifestPlacement: Codable, Hashable {
    let id: String
    let text: String
    let files: [String]
}

struct BrollManifest: Codable, Hashable {
    let defaultAudio: String
    let placements: [ManifestPlacement]
}

struct AssignmentStore: Codable {
    let version: Int
    let assignments: [String: [BrollAsset]]
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
                    modificationDate: values?.contentModificationDate
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
        if mode == .line && preservingEmptyLines {
            return raw
                .replacingOccurrences(of: "\r", with: "")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
