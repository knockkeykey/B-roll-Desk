import Foundation

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

enum BrollMode: String, CaseIterable, Codable, Identifiable {
    case fs = "FS"
    case pip = "PIP"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fs: return "FS · 全屏"
        case .pip: return "PIP · 画中画"
        }
    }
}

enum MediaKind: String, CaseIterable, Codable, Identifiable {
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
}

struct ManifestNaming: Codable, Hashable {
    let filenamePattern: String
    let defaultTrack: String
    let defaultAudio: String
    let copyMode: Bool
}

struct ManifestAnchor: Codable, Hashable {
    let id: String
    let index: Int
    let text: String
    let assets: [BrollAsset]
}

struct BrollManifest: Codable, Hashable {
    let schema: String
    let generatedAt: String
    let tool: String
    let destinationDirectory: String?
    let naming: ManifestNaming
    let anchors: [ManifestAnchor]
}

struct AssignmentStore: Codable {
    let version: Int
    let assignments: [String: [BrollAsset]]
}

struct SourceFile: Identifiable, Hashable {
    let url: URL
    let byteCount: Int64
    let kind: MediaKind

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct SavedDirectory: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var bookmarkData: Data
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum ScriptParser {
    static func split(_ raw: String, mode: SplitMode) -> [String] {
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
