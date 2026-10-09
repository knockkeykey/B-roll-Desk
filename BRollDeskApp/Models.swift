import Foundation
import os.signpost
import Observation
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

protocol RollProductionMethod: CaseIterable, Equatable, Identifiable {
    var title: String { get }
    var systemImage: String { get }
}

struct ShootingDevice: Codable, Equatable, Identifiable {
    let id: String
    var name: String

    init(id: String = UUID().uuidString.lowercased(), name: String) {
        self.id = id
        self.name = name
    }

    static let defaults = [
        ShootingDevice(id: "sony", name: "索尼"),
        ShootingDevice(id: "dji", name: "大疆")
    ]

    static func validated(_ devices: [ShootingDevice]) -> [ShootingDevice]? {
        let normalized = devices.map {
            ShootingDevice(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard normalized.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }),
              Set(normalized.map(\.id)).count == normalized.count,
              Set(normalized.map { $0.name.lowercased() }).count == normalized.count else { return nil }
        return normalized
    }
}

struct ShootingDeviceRoles: Codable, Equatable {
    var mainDeviceID: String?
    var auxiliaryDeviceID: String?

    static let defaults = ShootingDeviceRoles(mainDeviceID: "sony", auxiliaryDeviceID: "dji")

    func normalized(for devices: [ShootingDevice]) -> Self {
        let ids = devices.map(\.id)
        let main = mainDeviceID.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
        let auxiliary = auxiliaryDeviceID.flatMap { ids.contains($0) && $0 != main ? $0 : nil }
            ?? ids.first(where: { $0 != main })
        return Self(mainDeviceID: main, auxiliaryDeviceID: auxiliary)
    }
}

/// A removed editor must never commit its draft into a row reusing its old index.
struct InlineEditTarget {
    let rowID: String
    let session: UUID
    let resetID: UUID

    func canCommit(session: UUID, resetID: UUID, at index: Int, in rows: [AnchorRow]) -> Bool {
        self.session == session && self.resetID == resetID && rows.indices.contains(index)
            && rows[index].id == rowID
    }
}

enum ArollProductionMethod: String, RollProductionMethod, Codable, Hashable {
    case none
    case text
    case searchMaterial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .text: return "文字"
        case .searchMaterial: return "搜索素材"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "minus.circle"
        case .text: return "text.alignleft"
        case .searchMaterial: return "magnifyingglass"
        }
    }
}

enum BrollProductionMethod: String, RollProductionMethod, Codable, Hashable {
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
        case .stockFootage: return "搜索素材"
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

/// Shared preparation choices for B-roll and bindable auxiliary A-roll.
enum ScriptPreparationFilter: String, CaseIterable, Identifiable {
    case pending, ready, unbound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "待准备"
        case .ready: return "素材就绪"
        case .unbound: return "待绑定"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return BrollPreparationStatus.pending.systemImage
        case .ready: return BrollPreparationStatus.ready.systemImage
        case .unbound: return "link.circle"
        }
    }

    func matches(_ status: BrollPreparationStatus?) -> Bool {
        guard let status else { return false }
        switch self {
        case .pending: return status == .pending
        case .ready: return status == .ready
        case .unbound: return status != .bound
        }
    }
}

/// Tri-state choice for one filter option: ignore, show only, or hide.
enum ScriptFilterState: Equatable {
    case include
    case exclude

    /// Click cycle: off → include → exclude → off.
    static func next(after state: ScriptFilterState?) -> ScriptFilterState? {
        switch state {
        case nil: return .include
        case .include: return .exclude
        case .exclude: return nil
        }
    }
}

/// One filter dimension. Included values are OR-ed; excluded values always hide.
struct ScriptFilterFacet<Value: Hashable>: Equatable {
    private(set) var states: [Value: ScriptFilterState] = [:]

    var isActive: Bool { !states.isEmpty }

    subscript(value: Value) -> ScriptFilterState? {
        get { states[value] }
        set { states[value] = newValue }
    }

    mutating func cycle(_ value: Value) {
        states[value] = ScriptFilterState.next(after: states[value])
    }

    mutating func removeAll() { states.removeAll() }

    mutating func retain(_ values: Set<Value>) {
        states = states.filter { values.contains($0.key) }
    }

    func matches(_ value: Value) -> Bool {
        switch states[value] {
        case .exclude: return false
        case .include: return true
        case nil: return !states.values.contains(.include)
        }
    }

    /// Overlapping options (e.g. ready and unbound) keep exclusions ahead of inclusions.
    func matches(anyOf values: Set<Value>) -> Bool {
        if values.contains(where: { states[$0] == .exclude }) { return false }
        return !states.values.contains(.include) || values.contains(where: { states[$0] == .include })
    }
}

/// Roll-specific facets combine with one shared preparation filter.
struct ScriptRowFilter: Equatable {
    struct Attributes: Equatable {
        let rollType: AnchorRollType
        let isBlank: Bool
        /// nil means no shooting device is set.
        let shootingDeviceID: String?
        let arollMethod: ArollProductionMethod
        let brollMethod: BrollProductionMethod
        let brollStatus: BrollPreparationStatus
        /// nil for A-roll rows that do not offer individual footage binding.
        var arollStatus: BrollPreparationStatus? = nil

        var preparationStatus: BrollPreparationStatus? {
            rollType == .aRoll ? arollStatus : brollStatus
        }
    }

    var showsAroll = true
    var showsBroll = true
    var shootingDevices = ScriptFilterFacet<String?>()
    var arollMethods = ScriptFilterFacet<ArollProductionMethod>()
    var brollMethods = ScriptFilterFacet<BrollProductionMethod>()
    var preparationStatuses = ScriptFilterFacet<ScriptPreparationFilter>()

    var hasArollConditions: Bool { shootingDevices.isActive || arollMethods.isActive }
    var hasBrollConditions: Bool { brollMethods.isActive }

    var isActive: Bool {
        !showsAroll || !showsBroll || hasArollConditions || hasBrollConditions || preparationStatuses.isActive
    }

    var activeConditionCount: Int {
        (showsAroll ? 0 : 1) + (showsBroll ? 0 : 1)
            + shootingDevices.states.count + arollMethods.states.count
            + brollMethods.states.count + preparationStatuses.states.count
    }

    func matches(_ row: Attributes) -> Bool {
        // Blank rows carry no content to filter by, so any active filter hides them.
        if isActive && row.isBlank { return false }
        guard matchesPreparation(row.preparationStatus) else { return false }
        switch row.rollType {
        case .aRoll:
            return showsAroll
                && shootingDevices.matches(row.shootingDeviceID)
                && arollMethods.matches(row.arollMethod)
        case .bRoll:
            return showsBroll
                && brollMethods.matches(row.brollMethod)
        }
    }

    private func matchesPreparation(_ status: BrollPreparationStatus?) -> Bool {
        guard preparationStatuses.isActive else { return true }
        guard let status else { return false }
        return preparationStatuses.matches(anyOf: Set(ScriptPreparationFilter.allCases.filter { $0.matches(status) }))
    }

    mutating func reset() { self = ScriptRowFilter() }
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

/// A script overview, weighted by spoken text length rather than media timecodes.
struct ScriptDistribution: Equatable {
    struct Segment: Identifiable, Equatable {
        let row: AnchorRow
        let rollType: AnchorRollType
        let startFraction: Double
        let endFraction: Double

        var id: String { row.id }
        var fraction: Double { endFraction - startFraction }
    }

    let segments: [Segment]

    init(rows: [AnchorRow], rollType: (String) -> AnchorRollType) {
        let weightedRows = rows.compactMap { row -> (AnchorRow, Int)? in
            let count = Self.spokenCharacterCount(in: row.text)
            return count > 0 ? (row, count) : nil
        }
        let total = weightedRows.reduce(0) { $0 + $1.1 }
        var offset = 0
        segments = weightedRows.map { row, count in
            let start = offset
            offset += count
            return Segment(
                row: row,
                rollType: rollType(row.id),
                startFraction: Double(start) / Double(total),
                endFraction: Double(offset) / Double(total)
            )
        }
    }

    /// Count text characters without punctuation, whitespace or visual symbols.
    private static func spokenCharacterCount(in text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if character.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                count += 1
            }
        }
    }
}

struct VisibleScriptRow: Equatable {
    let id: String
    let startFraction: Double
    let endFraction: Double
}

/// A normalized window into the complete script; all navigation shares these bounds.
struct ScriptTimelineViewport: Equatable {
    static let minimumSpan = 0.02
    static let full = ScriptTimelineViewport(start: 0, end: 1)

    let start: Double
    let end: Double

    var span: Double { end - start }
    var center: Double { (start + end) / 2 }

    init(start: Double, end: Double) {
        guard start.isFinite, end.isFinite else {
            self.start = 0
            self.end = 1
            return
        }
        let span = min(1, max(Self.minimumSpan, end - start))
        let lower = min(1 - span, max(0, (start + end - span) / 2))
        self.start = lower
        self.end = lower + span
    }

    func zoomed(by factor: Double) -> Self {
        guard factor.isFinite, factor > 0 else { return self }
        let newSpan = min(1, max(Self.minimumSpan, span / factor))
        return Self(start: center - newSpan / 2, end: center + newSpan / 2)
    }

    func moved(by offset: Double) -> Self {
        guard offset.isFinite else { return self }
        let lower = min(1 - span, max(0, start + offset))
        return Self(start: lower, end: lower + span)
    }

    func panned(byScrollDelta delta: Double, precise: Bool, viewportWidth: Double) -> Self {
        guard delta.isFinite, viewportWidth.isFinite, viewportWidth > 0 else { return self }
        let step = delta * (precise ? 1 / viewportWidth : 0.08)
        // Move relative to the visible range so navigation stays controllable at any zoom.
        return moved(by: -span * min(0.5, max(-0.5, step)))
    }

    func resizingStart(to value: Double) -> Self {
        guard value.isFinite else { return self }
        return Self(start: min(end - Self.minimumSpan, max(0, value)), end: end)
    }

    func resizingEnd(to value: Double) -> Self {
        guard value.isFinite else { return self }
        return Self(start: start, end: max(start + Self.minimumSpan, min(1, value)))
    }

    static func following(_ visibleRows: [VisibleScriptRow], in distribution: ScriptDistribution,
                          preservingSpan span: Double) -> Self? {
        let visible = Dictionary(visibleRows.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let ranges = distribution.segments.compactMap { segment -> (Double, Double)? in
            guard let row = visible[segment.id] else { return nil }
            return (segment.startFraction + segment.fraction * row.startFraction,
                    segment.startFraction + segment.fraction * row.endFraction)
        }
        guard let lower = ranges.map(\.0).min(), let upper = ranges.map(\.1).max() else { return nil }
        let center = (lower + upper) / 2
        return Self(start: center - span / 2, end: center + span / 2)
    }
}

/// One live viewport and selection for the embedded timeline and its separate window.
@Observable
@MainActor
final class ScriptTimelineState {
    struct RevealRequest: Equatable {
        let rowID: String
        let token = UUID()
    }

    private(set) var viewport = ScriptTimelineViewport.full
    private(set) var followsScript = true
    var visibleRows: [VisibleScriptRow] = []
    var matchedRowIDs: Set<String>?
    var selectedRowID: String?
    private(set) var revealRequest: RevealRequest?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hasInitialized = false
    private static let zoomKey = "broll-namer-timeline-visible-fraction"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var rememberedSpan: Double {
        let saved = defaults.object(forKey: Self.zoomKey) as? Double ?? 0.1
        return saved.isFinite ? min(1, max(ScriptTimelineViewport.minimumSpan, saved)) : 0.1
    }

    func initializeIfNeeded(in distribution: ScriptDistribution) {
        guard !hasInitialized else { return }
        hasInitialized = true
        updateFollowRange(in: distribution)
    }

    func updateFollowRange(in distribution: ScriptDistribution) {
        let span = rememberedSpan
        let next = followsScript
            ? (ScriptTimelineViewport.following(visibleRows, in: distribution, preservingSpan: span)
               ?? ScriptTimelineViewport(start: viewport.center - span / 2, end: viewport.center + span / 2))
            : .full
        if next != viewport { viewport = next }
    }

    func followSelection(in distribution: ScriptDistribution) {
        guard followsScript, let segment = distribution.segments.first(where: { $0.id == selectedRowID }),
              segment.startFraction < viewport.start || segment.endFraction > viewport.end else { return }
        let center = (segment.startFraction + segment.endFraction) / 2
        let next = ScriptTimelineViewport(start: center - viewport.span / 2, end: center + viewport.span / 2)
        if next != viewport { viewport = next }
    }

    func toggleFollowMode(in distribution: ScriptDistribution) {
        followsScript.toggle()
        updateFollowRange(in: distribution)
    }

    func setRange(_ range: ScriptTimelineViewport) {
        hasInitialized = true
        followsScript = true
        if defaults.object(forKey: Self.zoomKey) as? Double != range.span {
            defaults.set(range.span, forKey: Self.zoomKey)
        }
        viewport = range
    }

    func requestReveal(_ rowID: String) {
        revealRequest = RevealRequest(rowID: rowID)
    }
}

enum AssetArchiveDirectory: String, Codable, Hashable {
    case bRoll = "B-roll"
    case aRoll = "A-roll"
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
    var archiveDirectory: AssetArchiveDirectory = .bRoll
    var sourceFilePath: String? = nil
    var sourceFileBookmark: Data? = nil

    var archiveRelativePath: String { "\(archiveDirectory.rawValue)/\(outputName)" }

    func reanchored(to row: AnchorRow) -> Self {
        guard anchorKey != row.id || anchorIndex != row.index || anchorText != row.text else { return self }
        return Self(id: id, anchorKey: row.id, anchorIndex: row.index, anchorText: row.text,
                    sourceName: sourceName, sourceDirectoryID: sourceDirectoryID, sourceRelativePath: sourceRelativePath,
                    outputName: outputName, mode: mode, targetTrack: targetTrack, audio: audio, copiedAt: copiedAt,
                    archiveDirectory: archiveDirectory, sourceFilePath: sourceFilePath, sourceFileBookmark: sourceFileBookmark)
    }

    func relocated(to directory: AssetArchiveDirectory, named name: String) -> Self {
        Self(id: id, anchorKey: anchorKey, anchorIndex: anchorIndex, anchorText: anchorText,
             sourceName: sourceName, sourceDirectoryID: sourceDirectoryID, sourceRelativePath: sourceRelativePath,
             outputName: name, mode: mode, targetTrack: directory == .aRoll ? "V2" : "V3", audio: "preserve",
             copiedAt: copiedAt, archiveDirectory: directory,
             sourceFilePath: sourceFilePath, sourceFileBookmark: sourceFileBookmark)
    }

    private enum CodingKeys: String, CodingKey {
        case id, anchorKey, anchorIndex, anchorText, sourceName, sourceDirectoryID, sourceRelativePath
        case outputName, mode, targetTrack, audio, copiedAt, archiveDirectory, sourceFilePath, sourceFileBookmark
    }

    init(id: String, anchorKey: String, anchorIndex: Int, anchorText: String, sourceName: String,
         sourceDirectoryID: String?, sourceRelativePath: String?, outputName: String, mode: BrollMode,
         targetTrack: String, audio: String, copiedAt: String, archiveDirectory: AssetArchiveDirectory = .bRoll,
         sourceFilePath: String? = nil, sourceFileBookmark: Data? = nil) {
        self.id = id
        self.anchorKey = anchorKey
        self.anchorIndex = anchorIndex
        self.anchorText = anchorText
        self.sourceName = sourceName
        self.sourceDirectoryID = sourceDirectoryID
        self.sourceRelativePath = sourceRelativePath
        self.outputName = outputName
        self.mode = mode
        self.targetTrack = targetTrack
        self.audio = audio
        self.copiedAt = copiedAt
        self.archiveDirectory = archiveDirectory
        self.sourceFilePath = sourceFilePath
        self.sourceFileBookmark = sourceFileBookmark
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        anchorKey = try c.decode(String.self, forKey: .anchorKey)
        anchorIndex = try c.decode(Int.self, forKey: .anchorIndex)
        anchorText = try c.decode(String.self, forKey: .anchorText)
        sourceName = try c.decode(String.self, forKey: .sourceName)
        sourceDirectoryID = try c.decodeIfPresent(String.self, forKey: .sourceDirectoryID)
        sourceRelativePath = try c.decodeIfPresent(String.self, forKey: .sourceRelativePath)
        outputName = try c.decode(String.self, forKey: .outputName)
        mode = try c.decode(BrollMode.self, forKey: .mode)
        targetTrack = try c.decode(String.self, forKey: .targetTrack)
        // Older versions instructed the editor to discard B-roll audio. Preserve it now.
        audio = "preserve"
        copiedAt = try c.decode(String.self, forKey: .copiedAt)
        archiveDirectory = try c.decodeIfPresent(AssetArchiveDirectory.self, forKey: .archiveDirectory) ?? .bRoll
        sourceFilePath = try c.decodeIfPresent(String.self, forKey: .sourceFilePath)
        sourceFileBookmark = try c.decodeIfPresent(Data.self, forKey: .sourceFileBookmark)
    }

    var fullScreen: BrollAsset {
        guard mode != .fs || audio != "preserve" else { return self }
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
            audio: "preserve",
            copiedAt: copiedAt,
            archiveDirectory: archiveDirectory,
            sourceFilePath: sourceFilePath,
            sourceFileBookmark: sourceFileBookmark
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
                    copiedAt: asset.copiedAt,
                    archiveDirectory: asset.archiveDirectory,
                    sourceFilePath: asset.sourceFilePath,
                    sourceFileBookmark: asset.sourceFileBookmark
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

struct AIBrollPlacement: Codable, Hashable {
    let text: String
    let files: [String]
}

struct AIBrollManifest: Codable, Hashable {
    let placements: [AIBrollPlacement]
    var defaultAudio = "preserve"

    init(placements: [AIBrollPlacement]) { self.placements = placements }

    private enum CodingKeys: String, CodingKey { case placements, defaultAudio }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        placements = try c.decode([AIBrollPlacement].self, forKey: .placements)
        defaultAudio = "preserve"
    }
}

struct CodexARollPlacement: Codable {
    let rowID: String
    let text: String
    let device: ShootingDevice
    let files: [String]
}

struct CodexARollManifest: Codable {
    let mainDevice: ShootingDevice?
    let auxiliaryDevice: ShootingDevice?
    let placements: [CodexARollPlacement]
    var defaultAudio = "preserve"
    var coveredMainAudio = "mute_preserving_source"
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
    var arollProductionMethods: [String: ArollProductionMethod]
    var arollShootingDevices: [String: ShootingDevice?]
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
        arollProductionMethods: [String: ArollProductionMethod] = [:],
        arollShootingDevices: [String: ShootingDevice?] = [:],
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
        self.arollProductionMethods = arollProductionMethods
        self.arollShootingDevices = arollShootingDevices
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
        case arollProductionMethods
        case arollShootingDevices
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
        arollProductionMethods = try container.decodeIfPresent(
            [String: ArollProductionMethod].self,
            forKey: .arollProductionMethods
        ) ?? [:]
        arollShootingDevices = try container.decodeIfPresent(
            [String: ShootingDevice?].self, forKey: .arollShootingDevices
        ) ?? [:]
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
        try container.encode(arollProductionMethods, forKey: .arollProductionMethods)
        try container.encode(arollShootingDevices, forKey: .arollShootingDevices)
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
                    of: #"^(?:.*_)?[AB]R[0-9]{3,}_.+\.[^.]+$"#,
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

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
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

/// Local, opt-in timing only: no script text, paths or asset names enter the log.
struct InlinePerformanceSpan {
    static let log = OSLog(subsystem: "com.keyknock.BrollNamer", category: .pointsOfInterest)
    let name: StaticString
    let id: OSSignpostID
    init(_ name: StaticString) {
        self.name = name
        id = OSSignpostID(log: Self.log)
        os_signpost(.begin, log: Self.log, name: name, signpostID: id)
    }
    func end() { os_signpost(.end, log: Self.log, name: name, signpostID: id) }
}

@MainActor enum InlineEditPerformance {
    private struct Sample {
        let token: UUID
        let kind: String
        let start: TimeInterval
        let span: InlinePerformanceSpan
        var modelMS: Double = 0
        var displayMS: Double = 0
    }
    private static var sample: Sample?
    private static let output = ProcessInfo.processInfo.environment["BROLL_DESK_INLINE_METRICS"]
    private static let writer = DispatchQueue(label: "com.keyknock.broll.inline-metrics")
    static var token: UUID? { sample?.token }

    static func begin(_ kind: String) {
        sample?.span.end()
        sample = Sample(token: UUID(), kind: kind, start: ProcessInfo.processInfo.systemUptime,
                        span: InlinePerformanceSpan("InlineKeyToFocus"))
    }
    static func modelFinished(since start: TimeInterval) {
        sample?.modelMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
    }
    static func displayed(_ token: UUID?) {
        guard let token, let start = sample?.start, sample?.token == token else { return }
        sample?.displayMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
    }
    static func ready(_ token: UUID?) {
        guard let token, let value = sample, value.token == token else { return }
        let inputMS = (ProcessInfo.processInfo.systemUptime - value.start) * 1000
        value.span.end()
        sample = nil
        guard let output else { return }
        let record: [String: Any] = ["kind": value.kind, "modelMS": value.modelMS,
                                     "displayMS": value.displayMS, "inputMS": inputMS]
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0a)
        let bytes = data
        writer.async {
            if !FileManager.default.fileExists(atPath: output) {
                FileManager.default.createFile(atPath: output, contents: nil)
            }
            guard let handle = FileHandle(forWritingAtPath: output) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: bytes)
        }
    }
}
