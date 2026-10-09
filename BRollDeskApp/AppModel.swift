import AppKit
import CoreServices
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
        let anchorNotes: [String: String]
        let rollTypeOverrides: [String: AnchorRollType]
        let capturedBrollRowIDs: Set<String>
        let arollProductionMethods: [String: ArollProductionMethod]
        let arollShootingDevices: [String: ShootingDevice?]
        let brollProductionMethods: [String: BrollProductionMethod]
        let brollPreparationStatuses: [String: BrollPreparationStatus]
        let animationTasks: [AnimationTask]

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
    private(set) var shootingDevices: [ShootingDevice] = ShootingDevice.defaults
    var anchorSearchText = ""
    let scriptTimeline = ScriptTimelineState()
    let dropFeedback = DropFeedbackModel()
    var selectedSourceFileURL: URL?
    var sourceFileJumpID: UUID?
    var mediaFilter: MediaFilter = .all {
        didSet { rebuildVisibleSourceFiles() }
    }
    private(set) var selectedSourceDirectoryID: String? {
        didSet { rebuildVisibleSourceFiles() }
    }
    var isAnimationPanelPresented = false
    var deepSeekKeyDraft = ""
    var animationRules = AnimationWorkflow.defaultRules
    var animationTemplate = AnimationWorkflow.defaultTemplate
    var animationCharacterPath = ""
    private(set) var animationCharacterImage: NSImage?
    var animationOutputDirectoryPath = ""
    /// Analysis results waiting for confirmation; the script is untouched until applied.
    var animationReviewItems: [AnimationReviewItem] = []
    @ObservationIgnored private var animationReviewBaseline: (project: String, snapshot: UndoSnapshot)?
    private(set) var animationTasks: [AnimationTask] = []
    private(set) var isAnalyzingAnimations = false
    private(set) var isTestingDeepSeek = false
    private(set) var animationFeedback = ""
    @ObservationIgnored private var animationRequest: Task<Void, Never>?
    private var animationRequestID = UUID()
    private let animationTasksKey = "broll-namer-animation-tasks"
    private let animationRulesKey = "broll-namer-animation-rules"
    private let animationTemplateKey = "broll-namer-animation-template"
    private let animationCharacterKey = "broll-namer-animation-character"
    private let animationCharacterBookmarkKey = "broll-namer-animation-character-bookmark"
    private let animationOutputDirectoryKey = "broll-namer-animation-output-directory"

    var isScriptEditorPresented = false
    var isManifestPreviewPresented = false
    private(set) var manifestPreviewText = ""
    var isClearConfirmationPresented = false
    var isARollReplacementConfirmationPresented = false
    var isARollRemovalConfirmationPresented = false
    var isBusy = false
    /// 正在处理拖拽绑定的文案行，用于在行内显示 loading
    var bindingRowIDs: Set<String> = []
    var statusMessage = "请设置素材来源和剪辑项目文件夹"
    var lastSaved = "尚未保存"
    var alert: AppAlert?
    private(set) var canUndo = false
    private(set) var canRedo = false

    private(set) var rows: [AnchorRow] = []
    private(set) var assignments: [String: [BrollAsset]] = [:]
    private(set) var anchorNotes: [String: String] = [:]
    private(set) var rollTypeOverrides: [String: AnchorRollType] = [:]
    private(set) var capturedBrollRowIDs: Set<String> = []
    private(set) var arollProductionMethods: [String: ArollProductionMethod] = [:]
    private(set) var arollShootingDevices: [String: ShootingDevice?] = [:]
    private(set) var brollProductionMethods: [String: BrollProductionMethod] = [:]
    private(set) var brollPreparationStatuses: [String: BrollPreparationStatus] = [:]
    private(set) var sourceFiles: [SourceFile] = []
    private(set) var visibleSourceFiles: [SourceFile] = []
    private(set) var sourceDirectories: [ProjectSourceDirectory] = []
    private(set) var sourceDirectoryURL: URL?
    private(set) var destinationDirectoryURL: URL?
    private(set) var savedDirectories: [SavedDirectory] = []
    private var pendingARollVideoURL: URL?

    private var brollDirectoryURL: URL? {
        destinationDirectoryURL?.appendingPathComponent("B-roll", isDirectory: true)
    }

    private var aRollDirectoryURL: URL? {
        destinationDirectoryURL?.appendingPathComponent("A-roll", isDirectory: true)
    }

    private var aRollScriptURL: URL? {
        aRollDirectoryURL?.appendingPathComponent("正确文案.txt")
    }

    private var projectSettingsURL: URL? {
        brollDirectoryURL?.appendingPathComponent("project-settings.json")
    }

    private let defaults: UserDefaults
    let undoManager = UndoManager()
    private var sourceAccessActive: [String: Bool] = [:]
    private var destinationAccessActive = false
    private var sourceFilesByName: [String: [SourceFile]] = [:]
    private var sourceFilesByURL: [URL: SourceFile] = [:]
    private var assignedSourceIdentities: Set<String> = []
    private var assignedLegacySourceNames: Set<String> = []
    private var assetsBySourceIdentity: [String: [BrollAsset]] = [:]
    private var assetsByLegacySourceName: [String: [BrollAsset]] = [:]
    private var sourceDirectoryURLs: [String: URL] = [:]
    private var sourceDirectoryReadFailures: Set<String> = []
    private var sourceScanTask: Task<([SourceFile], [String], [String]), Error>?
    private var sourceScanGeneration = UUID()
    private var sourceDirectoryWatchers: [String: SourceDirectoryWatcher] = [:]
    private var sourceRefreshWorkItem: DispatchWorkItem?
    @ObservationIgnored private var volumeNotificationObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var projectID = UUID().uuidString.lowercased()

    private let scriptKey = "broll-namer-script"
    private let splitModeKey = "broll-namer-split-mode"
    private let preservesEmptyAnchorsKey = "broll-namer-preserves-empty-anchors"
    private let anchorNotesKey = "broll-namer-anchor-notes"
    private let rollTypeOverridesKey = "broll-namer-roll-type-overrides"
    private let capturedBrollRowsKey = "broll-namer-captured-broll-rows"
    private let arollProductionMethodsKey = "broll-namer-aroll-production-methods"
    private let shootingDevicesKey = "broll-namer-shooting-devices"
    private let arollShootingDevicesKey = "broll-namer-aroll-shooting-devices"
    private let brollProductionMethodsKey = "broll-namer-production-methods"
    private let brollPreparationStatusesKey = "broll-namer-preparation-statuses"
    private let prefixKey = "broll-namer-prefix"
    private let sourceBookmarkKey = "broll-namer-source-bookmark"
    private let destinationBookmarkKey = "broll-namer-destination-bookmark"
    private let savedDirectoriesKey = "broll-namer-saved-directories"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: shootingDevicesKey),
           let saved = try? JSONDecoder().decode([ShootingDevice].self, from: data),
           let validated = ShootingDevice.validated(saved) {
            shootingDevices = validated
        }
        if let data = defaults.data(forKey: arollShootingDevicesKey) {
            arollShootingDevices = (try? JSONDecoder().decode([String: ShootingDevice?].self, from: data)) ?? [:]
        }
        undoManager.levelsOfUndo = 50
        scriptText = defaults.string(forKey: scriptKey) ?? ""
        splitMode = SplitMode(rawValue: defaults.string(forKey: splitModeKey) ?? "line") ?? .line
        preservesEmptyAnchors = defaults.bool(forKey: preservesEmptyAnchorsKey)
        prefix = defaults.string(forKey: prefixKey) ?? ""
        anchorNotes = defaults.dictionary(forKey: anchorNotesKey) as? [String: String] ?? [:]
        rollTypeOverrides = (defaults.dictionary(forKey: rollTypeOverridesKey) ?? [:]).compactMapValues { value in
            guard let rawValue = value as? String else { return nil }
            return AnchorRollType(rawValue: rawValue)
        }
        capturedBrollRowIDs = Set(defaults.stringArray(forKey: capturedBrollRowsKey) ?? [])
        arollProductionMethods = (defaults.dictionary(forKey: arollProductionMethodsKey) ?? [:]).compactMapValues { value in
            guard let rawValue = value as? String else { return nil }
            return ArollProductionMethod(rawValue: rawValue)
        }
        brollProductionMethods = (defaults.dictionary(forKey: brollProductionMethodsKey) ?? [:]).compactMapValues { value in
            guard let rawValue = value as? String else { return nil }
            return BrollProductionMethod(rawValue: rawValue)
        }
        brollPreparationStatuses = (defaults.dictionary(forKey: brollPreparationStatusesKey) ?? [:]).compactMapValues { value in
            guard let rawValue = value as? String,
                  let status = BrollPreparationStatus(rawValue: rawValue),
                  status != .bound else { return nil }
            return status
        }
        for rowID in capturedBrollRowIDs where brollPreparationStatuses[rowID] == nil {
            brollPreparationStatuses[rowID] = .ready
        }

        let savedAnimationRules = defaults.string(forKey: animationRulesKey) ?? AnimationWorkflow.defaultRules
        animationRules = AnimationWorkflow.rulesWithoutVisualIdea(savedAnimationRules)
        if animationRules != savedAnimationRules {
            defaults.set(animationRules, forKey: animationRulesKey)
        }
        animationTemplate = defaults.string(forKey: animationTemplateKey) ?? AnimationWorkflow.defaultTemplate
        animationCharacterPath = defaults.string(forKey: animationCharacterKey) ?? ""
        animationOutputDirectoryPath = defaults.string(forKey: animationOutputDirectoryKey) ?? ""
        if animationTemplate == AnimationWorkflow.legacyTemplate {
            // Old default embedded the character path; split it into the dedicated setting.
            animationTemplate = AnimationWorkflow.defaultTemplate
            if defaults.string(forKey: animationCharacterKey) == nil {
                animationCharacterPath = AnimationWorkflow.legacyCharacterPath
            }
            defaults.set(animationTemplate, forKey: animationTemplateKey)
            defaults.set(animationCharacterPath, forKey: animationCharacterKey)
        }
        restoreAnimationCharacterImage()
        if let data = defaults.data(forKey: animationTasksKey) {
            animationTasks = (try? JSONDecoder().decode([AnimationTask].self, from: data)) ?? []
        }
        restoreSavedDirectories()
        parseScript(persist: false)
        restoreAssignments()
        if migrateAnimationReasonsToNotes() { persistPreferences() }
        observeExternalVolumeChanges()

        Task { @MainActor [weak self] in
            self?.restoreDirectories()
        }
    }

    var sourceDirectoryName: String {
        if let selectedSourceDirectoryID,
           let directory = sourceDirectories.first(where: { $0.id == selectedSourceDirectoryID }) {
            return directory.name
        }
        switch sourceDirectories.count {
        case 0: return "未选择目录"
        case 1: return sourceDirectories[0].name
        default: return "\(sourceDirectories.count) 个目录"
        }
    }

    var sourceDirectoryTooltip: String {
        if let selectedSourceDirectoryID,
           let directory = sourceDirectories.first(where: { $0.id == selectedSourceDirectoryID }) {
            return "\(directory.name)：\(directory.path)"
        }
        return sourceDirectories.isEmpty
            ? "尚未选择素材来源"
            : sourceDirectories.map { "\($0.name)：\($0.path)" }.joined(separator: "\n\n")
    }

    func isSourceDirectoryConnected(path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        return sourceDirectories.contains { $0.path == standardizedPath }
    }

    func isSourceDirectoryAvailable(id: String) -> Bool {
        sourceDirectoryURLs[id] != nil && !sourceDirectoryReadFailures.contains(id)
    }

    func selectSourceDirectory(_ id: String?) {
        guard id == nil || sourceDirectories.contains(where: { $0.id == id }) else { return }
        selectedSourceDirectoryID = id
        if let id {
            if let url = sourceDirectoryURLs[id] {
                sourceDirectoryURL = url
                storeBookmark(for: url, key: sourceBookmarkKey)
            }
        }
    }

    var destinationDirectoryName: String {
        destinationDirectoryURL?.lastPathComponent ?? "未选择"
    }

    var aRollVideoDisplayName: String? {
        guard let aRollDirectoryURL,
              let videos = try? existingARollVideos(in: aRollDirectoryURL) else { return nil }
        return videos.first?.lastPathComponent
    }

    var aRollReplacementConfirmationMessage: String {
        let existingName = aRollVideoDisplayName ?? "现有视频"
        return "项目中已有 \(existingName)。确认后，现有 A-roll 视频会移到废纸篓；新视频会复制到 A-roll 文件夹并命名为 A-roll。"
    }

    var isPrefixValid: Bool {
        !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var assignedCount: Int {
        meaningfulRows.reduce(0) { $0 + assets(for: $1.id).count }
    }

    var pendingCount: Int {
        pendingBrollCount
    }

    var pendingBrollCount: Int {
        meaningfulRows.reduce(0) { $0 + (rollType(for: $1.id) == .bRoll && assets(for: $1.id).isEmpty ? 1 : 0) }
    }

    var hasScriptContent: Bool {
        rows.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var scriptAnchorCount: Int {
        meaningfulRows.count
    }

    private var meaningfulRows: [AnchorRow] {
        rows.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var scriptCharacterCount: Int {
        scriptText.reduce(into: 0) { count, character in
            if !character.isWhitespace {
                count += 1
            }
        }
    }

    var aRollAnchorCount: Int {
        meaningfulRows.reduce(0) { $0 + (rollType(for: $1.id) == .aRoll ? 1 : 0) }
    }

    var bRollAnchorCount: Int {
        meaningfulRows.reduce(0) { $0 + (rollType(for: $1.id) == .bRoll ? 1 : 0) }
    }

    var pendingPreparationBrollCount: Int {
        brollPreparationStatusCount(.pending)
    }

    var readyPreparationBrollCount: Int {
        brollPreparationStatusCount(.ready)
    }

    var boundPreparationBrollCount: Int {
        brollPreparationStatusCount(.bound)
    }

    func brollProductionMethodCount(_ method: BrollProductionMethod) -> Int {
        meaningfulRows.reduce(0) {
            $0 + (rollType(for: $1.id) == .bRoll && brollProductionMethod(for: $1.id) == method ? 1 : 0)
        }
    }

    func arollProductionMethodCount(_ method: ArollProductionMethod) -> Int {
        meaningfulRows.reduce(0) {
            $0 + (rollType(for: $1.id) == .aRoll && arollProductionMethod(for: $1.id) == method ? 1 : 0)
        }
    }

    func arollShootingDeviceCount(_ deviceID: String?) -> Int {
        meaningfulRows.reduce(0) {
            $0 + (rollType(for: $1.id) == .aRoll && shootingDevice(for: $1.id)?.id == deviceID ? 1 : 0)
        }
    }

    func brollPreparationStatusCount(_ status: BrollPreparationStatus) -> Int {
        meaningfulRows.reduce(0) {
            $0 + (rollType(for: $1.id) == .bRoll && brollPreparationStatus(for: $1.id) == status ? 1 : 0)
        }
    }

    func filterAttributes(for row: AnchorRow) -> ScriptRowFilter.Attributes {
        ScriptRowFilter.Attributes(
            rollType: rollType(for: row.id),
            isBlank: row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            shootingDeviceID: shootingDevice(for: row.id)?.id,
            arollMethod: arollProductionMethod(for: row.id),
            brollMethod: brollProductionMethod(for: row.id),
            brollStatus: brollPreparationStatus(for: row.id)
        )
    }

    var filteredRows: [AnchorRow] {
        let query = anchorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private func rebuildVisibleSourceFiles() {
        let files = selectedSourceDirectoryID.map { id in
            sourceFiles.filter { $0.sourceDirectoryID == id }
        } ?? sourceFiles
        switch mediaFilter {
        case .all:
            visibleSourceFiles = files
        case .video:
            visibleSourceFiles = files.filter { $0.kind == .video }
        case .image:
            visibleSourceFiles = files.filter { $0.kind == .image }
        }
    }

    func assets(for rowID: String) -> [BrollAsset] {
        assignments[rowID] ?? []
    }

    func note(for rowID: String) -> String {
        anchorNotes[rowID] ?? ""
    }

    func setNote(_ note: String, for rowID: String) {
        guard rows.contains(where: { $0.id == rowID }) else { return }
        let before = makeUndoSnapshot()
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            anchorNotes.removeValue(forKey: rowID)
        } else {
            anchorNotes[rowID] = note
        }
        guard makeUndoSnapshot() != before else { return }
        persistPreferences()
        lastSaved = "本机已保存 \(Self.timeString())"
        registerUndo(named: "编辑文案备注", restoring: before)
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

    func shootingDevice(for rowID: String) -> ShootingDevice? {
        guard let selection = arollShootingDevices[rowID] else {
            return shootingDevices.first(where: { $0.id == ShootingDevice.defaults[0].id })
        }
        guard let saved = selection else { return nil }
        return shootingDevices.first(where: { $0.id == saved.id }) ?? saved
    }

    func setShootingDevice(_ device: ShootingDevice?, for rowID: String) {
        guard let row = rows.first(where: { $0.id == rowID }), rollType(for: rowID) == .aRoll,
              shootingDevice(for: rowID)?.id != device?.id else { return }
        if let device, !shootingDevices.contains(where: { $0.id == device.id }) { return }

        let before = makeUndoSnapshot()
        if let device {
            arollShootingDevices[rowID] = shootingDevices.first(where: { $0.id == device.id })
        } else {
            arollShootingDevices.updateValue(nil, forKey: rowID)
        }
        persistPreferences()
        lastSaved = "本机已保存 \(Self.timeString())"
        statusMessage = "BR\(String(format: "%03d", row.index)) 拍摄设备：\(device?.name ?? "无")"
        registerUndo(named: "更改 A-roll 拍摄设备", restoring: before)
    }

    @discardableResult
    func updateShootingDevices(_ devices: [ShootingDevice]) -> Bool {
        guard let validated = ShootingDevice.validated(devices) else { return false }
        shootingDevices = validated
        defaults.set(try? JSONEncoder().encode(validated), forKey: shootingDevicesKey)
        arollShootingDevices = arollShootingDevices.mapValues { saved -> ShootingDevice? in
            guard let saved else { return nil }
            return validated.first(where: { $0.id == saved.id }) ?? saved
        }
        persistPreferences()
        statusMessage = "拍摄设备选项已保存"
        return true
    }

    func arollProductionMethod(for rowID: String) -> ArollProductionMethod {
        arollProductionMethods[rowID] ?? .none
    }

    func setArollProductionMethod(_ method: ArollProductionMethod, for rowID: String) {
        guard let row = rows.first(where: { $0.id == rowID }), rollType(for: rowID) == .aRoll,
              arollProductionMethod(for: rowID) != method else { return }

        let before = makeUndoSnapshot()
        arollProductionMethods[rowID] = method
        persistPreferences()
        lastSaved = "本机已保存 \(Self.timeString())"
        statusMessage = "BR\(String(format: "%03d", row.index)) 制作方式：\(method.title)"
        registerUndo(named: "更改 A-roll 制作方式", restoring: before)
    }

    func brollProductionMethod(for rowID: String) -> BrollProductionMethod {
        brollProductionMethods[rowID] ?? .liveAction
    }

    func setBrollProductionMethod(_ method: BrollProductionMethod, for rowID: String) {
        guard let row = rows.first(where: { $0.id == rowID }), rollType(for: rowID) == .bRoll,
              brollProductionMethod(for: rowID) != method else { return }

        let before = makeUndoSnapshot()
        brollProductionMethods[rowID] = method
        persistPreferences()
        lastSaved = "本机已保存 \(Self.timeString())"
        statusMessage = "BR\(String(format: "%03d", row.index)) 制作方式：\(method.title)"
        registerUndo(named: "更改 B-roll 制作方式", restoring: before)
    }

    func brollPreparationStatus(for rowID: String) -> BrollPreparationStatus {
        if !assets(for: rowID).isEmpty { return .bound }
        return brollPreparationStatuses[rowID] ?? (capturedBrollRowIDs.contains(rowID) ? .ready : .pending)
    }

    func setBrollPreparationStatus(_ status: BrollPreparationStatus, for rowID: String) {
        guard status != .bound,
              let row = rows.first(where: { $0.id == rowID }),
              rollType(for: rowID) == .bRoll,
              assets(for: rowID).isEmpty,
              brollPreparationStatus(for: rowID) != status else { return }

        let before = makeUndoSnapshot()
        if status == .pending {
            brollPreparationStatuses.removeValue(forKey: rowID)
        } else {
            brollPreparationStatuses[rowID] = status
        }
        if status == .ready {
            capturedBrollRowIDs.insert(rowID)
        } else {
            capturedBrollRowIDs.remove(rowID)
        }
        persistPreferences()
        lastSaved = "本机已保存 \(Self.timeString())"
        statusMessage = "BR\(String(format: "%03d", row.index)) 准备进度：\(status.title)"
        registerUndo(named: "更改 B-roll 准备进度", restoring: before)
    }

    func isAssigned(_ file: SourceFile) -> Bool {
        assignedSourceIdentities.contains(sourceIdentity(directoryID: file.sourceDirectoryID, relativePath: file.relativePath))
            || assignedLegacySourceNames.contains(file.name)
    }

    func assignedAssets(for file: SourceFile) -> [BrollAsset] {
        let identity = sourceIdentity(directoryID: file.sourceDirectoryID, relativePath: file.relativePath)
        return (assetsBySourceIdentity[identity] ?? []) + (assetsByLegacySourceName[file.name] ?? [])
    }

    func sourceFile(at url: URL) -> SourceFile? {
        sourceFilesByURL[url.standardizedFileURL]
    }

    var isCurrentSourceDirectorySaved: Bool {
        guard let sourceDirectoryURL else { return false }
        let identity = directoryIdentity(for: sourceDirectoryURL)
        return savedDirectories.contains { $0.path == identity }
    }

    private func sourceIdentity(directoryID: String, relativePath: String) -> String {
        "\(directoryID)|\(relativePath)"
    }

    func persistPreferences() {
        defaults.set(scriptText, forKey: scriptKey)
        defaults.set(splitMode.rawValue, forKey: splitModeKey)
        defaults.set(preservesEmptyAnchors, forKey: preservesEmptyAnchorsKey)
        defaults.set(anchorNotes, forKey: anchorNotesKey)
        defaults.set(prefix, forKey: prefixKey)
        defaults.set(rollTypeOverrides.mapValues(\.rawValue), forKey: rollTypeOverridesKey)
        defaults.set(capturedBrollRowIDs.sorted(), forKey: capturedBrollRowsKey)
        defaults.set(arollProductionMethods.mapValues(\.rawValue), forKey: arollProductionMethodsKey)
        defaults.set(try? JSONEncoder().encode(arollShootingDevices), forKey: arollShootingDevicesKey)
        defaults.set(brollProductionMethods.mapValues(\.rawValue), forKey: brollProductionMethodsKey)
        defaults.set(brollPreparationStatuses.mapValues(\.rawValue), forKey: brollPreparationStatusesKey)
        defaults.set(try? JSONEncoder().encode(animationTasks), forKey: animationTasksKey)
        saveAssignments()
        saveProjectSettings()
    }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        refreshUndoAvailability()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        refreshUndoAvailability()
    }

    private func discardUndoActions() {
        undoManager.removeAllActions()
        refreshUndoAvailability()
    }

    private func refreshUndoAvailability() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
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
        let previousRows = rows
        let previousNotes = anchorNotes
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
        if !previousRows.isEmpty {
            for index in animationTasks.indices {
                let text = animationTasks[index].text
                if previousRows.filter({ $0.text == text }).count != rows.filter({ $0.text == text }).count {
                    animationTasks[index].rowID = ""
                }
            }
        }
        let currentRowIDs = Set(rows.map(\.id))
        if previousRows.isEmpty {
            anchorNotes = previousNotes.filter { currentRowIDs.contains($0.key) }
        } else {
            anchorNotes = AnchorNoteMigration.migrateAfterScriptEdit(previousNotes, from: previousRows, to: rows)
        }
        rollTypeOverrides = rollTypeOverrides.filter { currentRowIDs.contains($0.key) }
        capturedBrollRowIDs = capturedBrollRowIDs.filter { currentRowIDs.contains($0) }
        arollProductionMethods = arollProductionMethods.filter { currentRowIDs.contains($0.key) }
        arollShootingDevices = arollShootingDevices.filter { currentRowIDs.contains($0.key) }
        brollProductionMethods = brollProductionMethods.filter { currentRowIDs.contains($0.key) }
        brollPreparationStatuses = brollPreparationStatuses.filter { currentRowIDs.contains($0.key) }
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

    func deleteInlineRow(at index: Int) {
        guard rows.indices.contains(index) else { return }
        let before = makeUndoSnapshot()
        var texts = rows.map(\.text)
        var sourceIndices = rows.indices.map { [$0] }
        texts.remove(at: index)
        sourceIndices.remove(at: index)
        applyInlineRows(texts, sourceIndices: sourceIndices)
        registerUndo(named: "删除文案", restoring: before)
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
        let previousNotes = anchorNotes
        let previousRollTypeOverrides = rollTypeOverrides
        let previousCapturedBrollRowIDs = capturedBrollRowIDs
        let previousArollProductionMethods = arollProductionMethods
        let previousShootingDevices = arollShootingDevices
        let previousBrollProductionMethods = brollProductionMethods
        let previousBrollPreparationStatuses = brollPreparationStatuses
        let previousAnimationTasks = animationTasks
        splitMode = .line
        preservesEmptyAnchors = !texts.isEmpty
        scriptText = texts.joined(separator: "\n")
        parseScript(persist: false)
        assignments = AnchorAssignmentMigration.migrate(
            previousAssignments,
            from: previousRows,
            to: rows,
            sourceIndices: sourceIndices
        )
        anchorNotes = AnchorNoteMigration.migrate(
            previousNotes,
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
        capturedBrollRowIDs = Set(rows.enumerated().compactMap { offset, row in
            guard sourceIndices.indices.contains(offset) else { return nil }
            let wasCaptured = sourceIndices[offset].contains { sourceIndex in
                previousRows.indices.contains(sourceIndex) &&
                    previousCapturedBrollRowIDs.contains(previousRows[sourceIndex].id)
            }
            return wasCaptured ? row.id : nil
        })
        arollProductionMethods = Dictionary(uniqueKeysWithValues: rows.enumerated().compactMap { offset, row in
            guard sourceIndices.indices.contains(offset) else { return nil }
            let inheritedMethod = sourceIndices[offset]
                .compactMap { sourceIndex -> ArollProductionMethod? in
                    guard previousRows.indices.contains(sourceIndex) else { return nil }
                    return previousArollProductionMethods[previousRows[sourceIndex].id]
                }
                .first
            return inheritedMethod.map { (row.id, $0) }
        })
        arollShootingDevices = Dictionary(uniqueKeysWithValues: rows.enumerated().compactMap { offset, row in
            guard sourceIndices.indices.contains(offset) else { return nil }
            let inheritedDevice = sourceIndices[offset].compactMap { sourceIndex -> ShootingDevice?? in
                guard previousRows.indices.contains(sourceIndex) else { return nil }
                return previousShootingDevices[previousRows[sourceIndex].id]
            }.first
            return inheritedDevice.map { (row.id, $0) }
        })
        brollProductionMethods = Dictionary(uniqueKeysWithValues: rows.enumerated().compactMap { offset, row in
            guard sourceIndices.indices.contains(offset) else { return nil }
            let inheritedMethod = sourceIndices[offset]
                .compactMap { sourceIndex -> BrollProductionMethod? in
                    guard previousRows.indices.contains(sourceIndex) else { return nil }
                    return previousBrollProductionMethods[previousRows[sourceIndex].id]
                }
                .first
            return inheritedMethod.map { (row.id, $0) }
        })
        brollPreparationStatuses = Dictionary(uniqueKeysWithValues: rows.enumerated().compactMap { offset, row in
            guard sourceIndices.indices.contains(offset) else { return nil }
            let inheritedStatus = sourceIndices[offset]
                .compactMap { sourceIndex -> BrollPreparationStatus? in
                    guard previousRows.indices.contains(sourceIndex) else { return nil }
                    return previousBrollPreparationStatuses[previousRows[sourceIndex].id]
                }
                .first
            return inheritedStatus.map { (row.id, $0) }
        })
        animationTasks = previousAnimationTasks.map { task in
            var migrated = task
            if let originalIndex = previousRows.firstIndex(where: { $0.id == task.rowID }) {
                let targets = rows.indices.filter {
                    sourceIndices.indices.contains($0) && sourceIndices[$0].contains(originalIndex) && rows[$0].text == task.text
                }
                migrated.rowID = targets.count == 1 ? rows[targets[0]].id : ""
            }
            return migrated
        }
        rebuildAssignmentIndexes()
        persistPreferences()
        if destinationDirectoryURL != nil {
            _ = saveManifest(showMessage: false)
            saveConfirmedProjectScriptIfPresent()
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
        panel.title = "添加素材目录"
        panel.message = "可一次选择多个素材文件夹；已添加的目录会继续保留"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let previousCount = sourceDirectories.count
        for url in panel.urls {
            activateSourceDirectory(url, persistProjectSettings: false, refresh: false)
            if saveAsFavorite {
                saveFavoriteDirectory(url, showMessage: false)
            }
        }
        if destinationDirectoryURL != nil {
            saveProjectSettings()
        }
        refreshSourceFiles()
        statusMessage = "已选择 \(panel.urls.count) 个目录，当前项目共连接 \(sourceDirectories.count) 个来源（新增 \(sourceDirectories.count - previousCount) 个）"
    }

    func acceptSourceDirectoryDrop(_ url: URL, saveAsFavorite: Bool = false) {
        activateSourceDirectory(url)
        if saveAsFavorite {
            saveFavoriteDirectory(url, showMessage: false)
        }
        statusMessage = "已添加素材目录：\(url.lastPathComponent)（当前共 \(sourceDirectories.count) 个来源）"
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
        statusMessage = "常用素材目录已连接到本项目：\(url.lastPathComponent)"
    }

    func removeProjectSourceDirectory(_ id: String) {
        guard !isBusy,
              let reference = sourceDirectories.first(where: { $0.id == id }) else { return }
        let referencePath = URL(fileURLWithPath: reference.path, isDirectory: true).standardizedFileURL.path
        let wasCurrentDirectory = sourceDirectoryURL?.standardizedFileURL.path == referencePath
        let bookmarkPointsToRemovedDirectory =
            resolvedBookmark(forKey: sourceBookmarkKey)?.standardizedFileURL.path == referencePath
        sourceScanTask?.cancel()
        let sourceURL = sourceDirectoryURLs.removeValue(forKey: id)
        sourceDirectoryWatchers.removeValue(forKey: id)?.stop()
        if let sourceURL, sourceAccessActive.removeValue(forKey: id) == true {
            sourceURL.stopAccessingSecurityScopedResource()
        } else {
            sourceAccessActive.removeValue(forKey: id)
        }
        sourceDirectories.removeAll { $0.id == id }
        sourceDirectoryReadFailures.remove(id)
        if selectedSourceDirectoryID == id {
            selectedSourceDirectoryID = nil
        }
        if wasCurrentDirectory {
            sourceDirectoryURL = sourceDirectories.reversed().compactMap { sourceDirectoryURLs[$0.id] }.first
        }
        if wasCurrentDirectory || bookmarkPointsToRemovedDirectory {
            if sourceDirectoryURL == nil {
                sourceDirectoryURL = sourceDirectories.reversed().compactMap { sourceDirectoryURLs[$0.id] }.first
            }
            if let sourceDirectoryURL {
                storeBookmark(for: sourceDirectoryURL, key: sourceBookmarkKey)
            } else {
                defaults.removeObject(forKey: sourceBookmarkKey)
            }
        }
        persistPreferences()
        refreshSourceFiles()
        statusMessage = "已从本项目素材来源中移除：\(reference.name)"
    }

    func removeCurrentSourceDirectory() {
        guard let sourceDirectoryURL else { return }
        let currentPath = sourceDirectoryURL.standardizedFileURL.path
        guard let reference = sourceDirectories.first(where: {
            $0.path == currentPath || sourceDirectoryURLs[$0.id]?.standardizedFileURL.path == currentPath
        }) else { return }
        removeProjectSourceDirectory(reference.id)
    }

    func reconnectProjectSourceDirectory(_ id: String) {
        guard let existingReference = sourceDirectories.first(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.title = "重新连接素材目录"
        panel.message = "选择“\(existingReference.name)”现在所在的文件夹"
        panel.prompt = "重新连接"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        activateSourceDirectory(url, reference: existingReference)
        statusMessage = "已重新连接素材目录：\(url.lastPathComponent)"
    }

    func removeSavedDirectory(_ id: UUID) {
        savedDirectories.removeAll { $0.id == id }
        persistSavedDirectories()
    }

    func chooseDestinationDirectory() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "选择剪辑项目文件夹"
        panel.message = "选择项目文件夹；App 会在里面创建 B-roll 和 A-roll 文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard activateDestinationDirectory(url) else { return }
        guard loadProjectState(at: url) else { return }
        refreshSourceFiles()
        updateProjectRestoreStatus(for: url)
    }

    func clearDestinationDirectory() {
        guard !isBusy, let directoryURL = destinationDirectoryURL else { return }

        // Save the current project before clearing its in-memory session. Project files
        // remain the source of truth and can restore this state when selected again.
        persistPreferences()
        saveConfirmedProjectScriptIfPresent()

        defaults.removeObject(forKey: destinationBookmarkKey)
        defaults.removeObject(forKey: sourceBookmarkKey)
        if destinationAccessActive {
            directoryURL.stopAccessingSecurityScopedResource()
        }
        destinationAccessActive = false
        destinationDirectoryURL = nil

        clearCurrentProjectState()
        // Clear the app-level fallback cache too, so a later launch with no project
        // selected does not repopulate this project's data in the interface.
        persistPreferences()
        statusMessage = "已取消选择剪辑项目文件夹，项目文件仍保留在原位置。"
    }

    private func clearCurrentProjectState() {
        cancelAnimationAnalysis()
        animationTasks = []
        animationFeedback = ""
        isAnimationPanelPresented = false
        discardUndoActions()

        scriptText = ""
        splitMode = .line
        preservesEmptyAnchors = false
        prefix = ""
        anchorSearchText = ""
        projectID = UUID().uuidString.lowercased()

        rows = []
        assignments = [:]
        anchorNotes = [:]
        rollTypeOverrides = [:]
        capturedBrollRowIDs = []
        arollProductionMethods = [:]
        arollShootingDevices = [:]
        brollProductionMethods = [:]
        brollPreparationStatuses = [:]
        rebuildAssignmentIndexes()

        clearSourceDirectories()
        mediaFilter = .all
        sourceFileJumpID = nil
        bindingRowIDs.removeAll()
        dropFeedback.isFileDragActive = false

        pendingARollVideoURL = nil
        isScriptEditorPresented = false
        isManifestPreviewPresented = false
        manifestPreviewText = ""
        isClearConfirmationPresented = false
        isARollReplacementConfirmationPresented = false
        isARollRemovalConfirmationPresented = false
        alert = nil
        lastSaved = "尚未保存"
    }

    func chooseARollVideo() {
        guard !isBusy,
              pendingARollVideoURL == nil,
              !isARollRemovalConfirmationPresented else { return }
        guard destinationDirectoryURL != nil else {
            showError(title: "请先选择剪辑项目文件夹", message: "选择剪辑项目文件夹后，才能把视频放入项目的 A-roll 文件夹。")
            return
        }

        let panel = NSOpenPanel()
        panel.title = "上传 A-roll 视频"
        panel.message = "选择一个视频；原文件会保留，项目副本会命名为 A-roll"
        panel.prompt = "上传"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.movie] + Self.videoExtensions.compactMap {
            UTType(filenameExtension: $0)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor [weak self] in
            await self?.importARollVideo(from: [url])
        }
    }

    func importARollVideo(from urls: [URL]) async {
        guard !isBusy,
              pendingARollVideoURL == nil,
              !isARollRemovalConfirmationPresented else { return }
        guard let aRollDirectoryURL else {
            showError(title: "请先选择剪辑项目文件夹", message: "选择剪辑项目文件夹后，才能把视频放入项目的 A-roll 文件夹。")
            return
        }
        guard urls.count == 1, let sourceURL = urls.first else {
            showError(title: "一次上传一个视频", message: "请一次选择或拖入一个 A-roll 视频文件。")
            return
        }
        guard Self.videoExtensions.contains(sourceURL.pathExtension.lowercased()),
              (try? sourceURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            showError(title: "无法上传这个文件", message: "请拖入支持的视频文件。")
            return
        }

        let existingVideos: [URL]
        do {
            existingVideos = try existingARollVideos(in: aRollDirectoryURL)
        } catch {
            showError(title: "无法读取 A-roll 文件夹", message: error.localizedDescription)
            return
        }

        if existingVideos.contains(where: { $0.standardizedFileURL == sourceURL.standardizedFileURL }) {
            statusMessage = "这个视频已经是当前项目的 A-roll"
            return
        }

        guard existingVideos.isEmpty else {
            pendingARollVideoURL = sourceURL
            isARollReplacementConfirmationPresented = true
            return
        }

        await copyARollVideo(from: sourceURL, replacing: [])
    }

    func confirmARollVideoReplacement() {
        guard let sourceURL = pendingARollVideoURL,
              let aRollDirectoryURL else {
            cancelARollVideoReplacement()
            return
        }

        let existingVideos: [URL]
        do {
            existingVideos = try existingARollVideos(in: aRollDirectoryURL)
        } catch {
            cancelARollVideoReplacement()
            showError(title: "无法读取 A-roll 文件夹", message: error.localizedDescription)
            return
        }
        pendingARollVideoURL = nil
        isARollReplacementConfirmationPresented = false
        Task { @MainActor [weak self] in
            await self?.copyARollVideo(from: sourceURL, replacing: existingVideos)
        }
    }

    func cancelARollVideoReplacement() {
        pendingARollVideoURL = nil
        isARollReplacementConfirmationPresented = false
    }

    func requestARollVideoRemoval() {
        guard !isBusy,
              !isARollReplacementConfirmationPresented,
              !isARollRemovalConfirmationPresented,
              aRollVideoDisplayName != nil else { return }
        isARollRemovalConfirmationPresented = true
    }

    func cancelARollVideoRemoval() {
        isARollRemovalConfirmationPresented = false
    }

    func confirmARollVideoRemoval() {
        guard !isBusy, let aRollDirectoryURL else {
            isARollRemovalConfirmationPresented = false
            return
        }
        isARollRemovalConfirmationPresented = false

        let existingVideos: [URL]
        do {
            existingVideos = try existingARollVideos(in: aRollDirectoryURL)
        } catch {
            showError(title: "无法读取 A-roll 文件夹", message: error.localizedDescription)
            return
        }
        guard !existingVideos.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }

        var movedCount = 0
        var failures: [String] = []
        for videoURL in existingVideos {
            do {
                try FileManager.default.trashItem(at: videoURL, resultingItemURL: nil)
                movedCount += 1
            } catch {
                failures.append("\(videoURL.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            lastSaved = "已移出 A-roll \(Self.timeString())"
            statusMessage = "已将项目 A-roll 文件移入废纸篓。"
        } else {
            showError(
                title: "部分 A-roll 视频移出失败",
                message: "已移入废纸篓 \(movedCount) 个 A-roll 视频。\n\(failures.joined(separator: "\n"))"
            )
        }
    }

    private func copyARollVideo(from sourceURL: URL, replacing existingVideos: [URL]) async {
        guard !isBusy, let aRollDirectoryURL else { return }
        isBusy = true
        defer { isBusy = false }

        let fileManager = FileManager.default
        let fileExtension = sourceURL.pathExtension
        let targetURL = aRollDirectoryURL.appendingPathComponent("A-roll.\(fileExtension)")
        let stagingURL = aRollDirectoryURL.appendingPathComponent(
            ".A-roll-upload-\(UUID().uuidString).\(fileExtension)"
        )
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        statusMessage = "正在复制 A-roll 视频：\(sourceURL.lastPathComponent)"
        do {
            try await copyFile(from: sourceURL, to: stagingURL)
            for existingURL in existingVideos {
                try fileManager.trashItem(at: existingURL, resultingItemURL: nil)
            }
            try fileManager.moveItem(at: stagingURL, to: targetURL)
            lastSaved = "已保存 A-roll \(Self.timeString())"
            statusMessage = "已保存到 A-roll/\(targetURL.lastPathComponent)；原视频文件保留"
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            showError(title: "上传 A-roll 视频失败", message: error.localizedDescription)
        }
    }

    private func existingARollVideos(in directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare("A-roll") == .orderedSame &&
                Self.videoExtensions.contains(url.pathExtension.lowercased()) &&
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func acceptDestinationDirectoryDrop(_ url: URL) {
        guard !isBusy else { return }
        guard activateDestinationDirectory(url) else { return }
        guard loadProjectState(at: url) else { return }
        refreshSourceFiles()
        updateProjectRestoreStatus(for: url)
    }

    func refreshSourceFiles(recoverSourceDirectories: Bool = false) {
        if recoverSourceDirectories {
            let reconnectedCount = reconnectAvailableSourceDirectories(forceRefreshAccess: true)
            if reconnectedCount > 0 {
                statusMessage = "已重新连接素材目录，正在刷新素材列表。"
            } else if sourceDirectories.contains(where: { sourceDirectoryURLs[$0.id] == nil }) {
                statusMessage = "素材来源磁盘当前不可用；重新插入后会自动恢复素材列表。"
            }
        }

        sourceScanTask?.cancel()
        sourceScanTask = nil

        let roots = sourceDirectories.compactMap { reference in
            sourceDirectoryURLs[reference.id].map { (reference.id, $0) }
        }
        guard !roots.isEmpty else {
            sourceScanGeneration = UUID()
            sourceDirectoryReadFailures.removeAll()
            installSourceFiles([])
            return
        }

        let generation = UUID()
        sourceScanGeneration = generation
        let videoExtensions = Self.videoExtensions
        let imageExtensions = Self.imageExtensions
        let scanTask = Task.detached(priority: .userInitiated) {
            var files: [SourceFile] = []
            var failures: [String] = []
            var failedDirectoryIDs: [String] = []
            for (directoryID, directoryURL) in roots {
                try Task<Never, Never>.checkCancellation()
                do {
                    files.append(contentsOf: try SourceFileScanner.scan(
                        in: directoryURL,
                        sourceDirectoryID: directoryID,
                        videoExtensions: videoExtensions,
                        imageExtensions: imageExtensions
                    ))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append("\(directoryURL.lastPathComponent)：\(error.localizedDescription)")
                    failedDirectoryIDs.append(directoryID)
                }
            }
            files.sort {
                let nameOrder = $0.name.localizedStandardCompare($1.name)
                return nameOrder == .orderedSame
                    ? $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
                    : nameOrder == .orderedAscending
            }
            return (files, failures, failedDirectoryIDs)
        }
        sourceScanTask = scanTask

        Task { @MainActor [weak self] in
            do {
                let (files, failures, failedDirectoryIDs) = try await scanTask.value
                guard let self, self.sourceScanGeneration == generation else { return }
                self.sourceScanTask = nil
                let hadReadFailures = !self.sourceDirectoryReadFailures.isEmpty
                self.sourceDirectoryReadFailures = Set(failedDirectoryIDs)
                self.installSourceFiles(files)
                if !failures.isEmpty {
                    self.statusMessage = "部分素材目录无法读取：\(failures.joined(separator: "；"))"
                } else if hadReadFailures {
                    self.statusMessage = "素材目录已恢复，素材列表已刷新"
                }
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
        var byName: [String: [SourceFile]] = [:]
        var byURL: [URL: SourceFile] = [:]
        for file in files {
            byName[file.name, default: []].append(file)
            byURL[file.url.standardizedFileURL] = file
        }

        sourceFilesByName = byName
        sourceFilesByURL = byURL
        sourceFiles = files
        rebuildVisibleSourceFiles()

        if let selectedSourceFileURL, byURL[selectedSourceFileURL.standardizedFileURL] == nil {
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
            showError(title: "无法清空配对记录", message: "请先重新选择剪辑项目文件夹，才能删除其中的副本并更新对照表。")
            return
        }

        // Clearing can also remove unrecorded archive files, so earlier undo entries
        // must not appear to undo a different action after this irreversible cleanup.
        discardUndoActions()

        let recordedNames = Set(assignments.values.flatMap { $0.map(\.outputName) })
        let mediaExtensions = Self.videoExtensions.union(Self.imageExtensions)
        guard let brollDirectoryURL else { return }
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
                in: brollDirectoryURL,
                mediaExtensions: mediaExtensions
            )
            let outputNames = recordedNames.union(discoveredNames)
            return ArchiveCleaner.removeCopies(named: outputNames, from: brollDirectoryURL)
        }

        Task { @MainActor [weak self] in
            defer { self?.isBusy = false }
            do {
                let cleanup = try await cleanupTask.value
                guard let self, self.destinationDirectoryURL == destinationDirectoryURL else { return }
                self.finishClearAssignments(cleanup)
            } catch {
                self?.showError(title: "无法读取剪辑项目文件夹", message: "尚未清空配对记录：\(error.localizedDescription)")
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
            ? "对照表已更新；未删除的文件仍留在 B-roll 文件夹，对应绑定会保留。"
                : "对照表更新也失败了，请检查 B-roll 文件夹。"
            let localNote = localSaved ? "" : "本机记录保存也失败了。"
            showError(
                title: "部分归档副本删除失败",
                message: "有 \(cleanup.failedNames.count) 个 B-roll 文件未能删除：\(examples)\(suffix)。\(manifestNote)\(localNote)"
            )
        } else if !localSaved {
            showError(title: "本机配对记录保存失败", message: "归档副本已删除，但本机记录未能保存。请检查应用数据目录。")
        } else if manifestSaved {
            lastSaved = "已清空 \(Self.timeString())"
            let missingNote = cleanup.missingCount > 0 ? "，另有 \(cleanup.missingCount) 个文件原本不存在" : ""
            statusMessage = "已删除 \(cleanup.deletedCount) 个 B-roll 副本\(missingNote)，并更新 JSON 对照表"
        }
    }

    func saveManifest(showMessage: Bool = true) -> Bool {
        guard destinationDirectoryURL != nil else {
            showError(title: "还没有剪辑项目文件夹", message: "请先选择剪辑项目文件夹，再保存对照表。")
            return false
        }

        let manifest = currentManifest()
        do {
            guard let brollDirectoryURL else { return false }
            try writeManifest(manifest, to: brollDirectoryURL)
            saveProjectSettings()
            lastSaved = "已保存 \(Self.timeString())"
            if showMessage {
                statusMessage = "对照表已保存到 B-roll 文件夹"
            }
            return true
        } catch {
            showError(title: "保存对照表失败", message: error.localizedDescription)
            return false
        }
    }

    func revealManifest() {
        guard destinationDirectoryURL != nil else {
            showError(title: "还没有剪辑项目文件夹", message: "请先选择剪辑项目文件夹，才能在 Finder 中定位 Codex JSON 对照表。")
            return
        }
        guard saveManifest(showMessage: false) else { return }
        guard let brollDirectoryURL else { return }
        let url = brollDirectoryURL.appendingPathComponent("broll-for-codex.json")
        guard revealInFinder(url) else { return }
        statusMessage = "已在 Finder 中定位 Codex JSON 对照表"
    }

    @discardableResult
    func revealInFinder(_ url: URL) -> Bool {
        do {
            try FinderItemOpener.reveal(url)
            return true
        } catch {
            showError(title: "无法在 Finder 中显示项目", message: error.localizedDescription)
            return false
        }
    }

    func previewManifest() {
        do {
            let data = try encodedJSON(currentCodexManifest())
            manifestPreviewText = String(decoding: data, as: UTF8.self)
            isManifestPreviewPresented = true
        } catch {
            showError(title: "无法预览 Codex JSON 对照表", message: error.localizedDescription)
        }
    }

    func importScript() {
        guard destinationDirectoryURL != nil else {
            showError(title: "请先选择剪辑项目文件夹", message: "选择项目文件夹后，才能向这个项目导入文案。")
            return
        }

        let panel = NSOpenPanel()
        panel.title = "导入文案"
        panel.message = "选择 .txt 或 .md 文稿"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importScript(from: url)
    }

    func importScript(from url: URL) {
        guard destinationDirectoryURL != nil else {
            showError(title: "请先选择剪辑项目文件夹", message: "选择项目文件夹后，才能向这个项目导入文案。")
            return
        }

        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension == "txt" || fileExtension == "md" else {
            showError(title: "不支持的文案格式", message: "请选择或拖入 .txt 或 .md 文稿。")
            return
        }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            scriptText = try String(contentsOf: url, encoding: .utf8)
            preservesEmptyAnchors = false
            parseScript()
            statusMessage = "已导入文案：\(url.lastPathComponent)"
        } catch {
            showError(title: "导入文案失败", message: error.localizedDescription)
        }
    }

    func confirmScript() {
        parseScript()
        guard let destinationDirectoryURL, let aRollScriptURL else {
            statusMessage = "文案已保存在本机；选择剪辑项目文件夹后，才能保存到 A-roll。"
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationDirectoryURL.appendingPathComponent("A-roll", isDirectory: true),
                withIntermediateDirectories: true
            )
            if scriptText.isEmpty, !FileManager.default.fileExists(atPath: aRollScriptURL.path) {
                saveProjectSettings()
                statusMessage = "文案为空，尚未生成 A-roll/正确文案.txt"
                return
            }
            try scriptText.write(to: aRollScriptURL, atomically: true, encoding: .utf8)
            persistPreferences()
            lastSaved = "已保存到 A-roll \(Self.timeString())"
            statusMessage = "已确认并保存：A-roll/正确文案.txt"
        } catch {
            showError(title: "保存正确文案失败", message: error.localizedDescription)
        }
    }

    private func saveConfirmedProjectScriptIfPresent() {
        guard let aRollScriptURL,
              FileManager.default.fileExists(atPath: aRollScriptURL.path) else { return }
        do {
            try scriptText.write(to: aRollScriptURL, atomically: true, encoding: .utf8)
        } catch {
            showError(title: "同步正确文案失败", message: error.localizedDescription)
        }
    }

    func reveal(_ asset: BrollAsset) {
        guard let brollDirectoryURL else { return }
        let url = brollDirectoryURL.appendingPathComponent(asset.outputName)
        revealInFinder(url)
    }

    func revealSource(_ asset: BrollAsset) {
        guard let url = sourceURL(for: asset) else {
            showError(
                title: "无法定位源素材",
                message: "请重新连接素材来源目录后再试。"
            )
            return
        }
        revealInFinder(url)
    }

    func sourceFile(for asset: BrollAsset) -> SourceFile? {
        if let directoryID = asset.sourceDirectoryID,
           let relativePath = asset.sourceRelativePath,
           let directoryURL = sourceDirectoryURLs[directoryID] {
            let url = directoryURL.appendingPathComponent(relativePath).standardizedFileURL
            return sourceFilesByURL[url]
        }
        let matches = sourceFilesByName[asset.sourceName] ?? []
        return matches.count == 1 ? matches.first : nil
    }

    func sourceOriginLabel(for asset: BrollAsset) -> String {
        guard let directoryID = asset.sourceDirectoryID,
              let relativePath = asset.sourceRelativePath,
              let directory = sourceDirectories.first(where: { $0.id == directoryID }) else {
            return asset.sourceName
        }
        return "\(directory.path)/\(relativePath)"
    }

    private func sourceOrigin(for url: URL) -> (directoryID: String?, relativePath: String?) {
        let normalizedURL = url.standardizedFileURL
        if let file = sourceFilesByURL[normalizedURL] {
            return (file.sourceDirectoryID, file.relativePath)
        }

        let filePath = normalizedURL.path
        let matchingRoots = sourceDirectories.compactMap { reference -> (ProjectSourceDirectory, URL)? in
            guard let directoryURL = sourceDirectoryURLs[reference.id] else { return nil }
            let rootPath = directoryURL.standardizedFileURL.path
            let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            guard filePath.hasPrefix(rootPrefix) else { return nil }
            return (reference, directoryURL)
        }
        guard let (reference, directoryURL) = matchingRoots.max(by: {
            $0.1.path.count < $1.1.path.count
        }) else { return (nil, nil) }
        let rootPath = directoryURL.standardizedFileURL.path
        let rootPrefixLength = (rootPath.hasSuffix("/") ? rootPath : rootPath + "/").count
        return (reference.id, String(filePath.dropFirst(rootPrefixLength)))
    }

    private func sourceURL(for asset: BrollAsset) -> URL? {
        if let directoryID = asset.sourceDirectoryID,
           let relativePath = asset.sourceRelativePath,
           let directoryURL = sourceDirectoryURLs[directoryID] {
            return directoryURL.appendingPathComponent(relativePath).standardizedFileURL
        }
        if let file = sourceFile(for: asset) {
            return file.url
        }
        guard sourceDirectories.count == 1,
              let onlyDirectoryURL = sourceDirectoryURLs[sourceDirectories[0].id] else { return nil }
        return onlyDirectoryURL.appendingPathComponent(asset.sourceName)
    }

    func jumpToSourceFile(for asset: BrollAsset) {
        guard let file = sourceFile(for: asset) else { return }
        selectedSourceDirectoryID = file.sourceDirectoryID
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
        guard destinationDirectoryURL != nil else {
            showError(title: "请先选择剪辑项目文件夹", message: "绑定素材前，请先在左侧选择剪辑项目文件夹。")
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
        let prefixPart = prefixValue.isEmpty
            ? ""
            : "\(ScriptParser.sanitizePart(prefixValue, maxLength: 30))_"
        let label = ScriptParser.sanitizePart(row.text, maxLength: 24)
        let baseCode = "BR\(String(format: "%03d", row.index))"
        var copiedCount = 0
        var skippedCount = 0

        for sourceURL in mediaURLs {
            let sourceName = sourceURL.lastPathComponent
            let origin = sourceOrigin(for: sourceURL)
            let isAlreadyAssigned = assets(for: rowID).contains { asset in
                if let directoryID = origin.directoryID, let relativePath = origin.relativePath {
                    return asset.sourceDirectoryID == directoryID && asset.sourceRelativePath == relativePath
                }
                return asset.sourceDirectoryID == nil && asset.sourceName == sourceName
            }
            if isAlreadyAssigned {
                skippedCount += 1
                continue
            }

            let baseName = "\(prefixPart)\(baseCode)_\(label)\(ScriptParser.extensionForFileName(sourceName))"
            let outputName = uniqueOutputName(baseName)
            guard let brollDirectoryURL else { return }
            let outputURL = brollDirectoryURL.appendingPathComponent(outputName)
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
                    sourceDirectoryID: origin.directoryID,
                    sourceRelativePath: origin.relativePath,
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
        let archiveSummary = "本次新增 \(copiedCount) 个；对照表中共 \(assignedCount) 个素材"
        statusMessage = skippedCount > 0
            ? "\(archiveSummary)，跳过 \(skippedCount) 个重复素材"
            : "\(archiveSummary)，已保存到 B-roll 文件夹"
    }

    func unbind(_ asset: BrollAsset) {
        guard !isBusy else { return }
        guard var rowAssets = assignments[asset.anchorKey] else { return }
        let undoState = makeUndoSnapshot()
        guard let brollDirectoryURL else {
            showError(title: "无法取消绑定", message: "请先重新选择剪辑项目文件夹，才能删除 B-roll 中的副本并更新对照表。")
            return
        }

        let outputFileName = URL(fileURLWithPath: asset.outputName).lastPathComponent
        let archivedURL = brollDirectoryURL.appendingPathComponent(outputFileName)
        if FileManager.default.fileExists(atPath: archivedURL.path) {
            do {
                try FileManager.default.removeItem(at: archivedURL)
            } catch {
                showError(title: "删除 B-roll 副本失败", message: "\(outputFileName) 仍保留在 B-roll 文件夹，因此这次没有取消绑定。\n\(error.localizedDescription)")
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
            ? "已取消绑定并删除 B-roll 副本：\(asset.sourceName)"
            : "已取消绑定并删除 B-roll 副本，但对照表更新失败：\(asset.sourceName)"
    }

    private func copyFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }.value
    }

    private func uniqueOutputName(_ baseName: String) -> String {
        guard let brollDirectoryURL else { return baseName }
        let fileManager = FileManager.default
        let baseURL = brollDirectoryURL.appendingPathComponent(baseName)
        if !fileManager.fileExists(atPath: baseURL.path) {
            return baseName
        }

        let baseNSString = baseName as NSString
        let stem = baseNSString.deletingPathExtension
        let ext = baseNSString.pathExtension.isEmpty ? "" : ".\(baseNSString.pathExtension)"
        for counter in 2..<1000 {
            let candidate = "\(stem)_\(String(format: "%02d", counter))\(ext)"
            if !fileManager.fileExists(atPath: brollDirectoryURL.appendingPathComponent(candidate).path) {
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
        var sourceIdentities: Set<String> = []
        var legacySourceNames: Set<String> = []
        var assetsByIdentity: [String: [BrollAsset]] = [:]
        var assetsByLegacyName: [String: [BrollAsset]] = [:]
        var rowsWithAssets: Set<String> = []

        for row in rows {
            let assets = assignments[row.id] ?? []
            if !assets.isEmpty {
                rowsWithAssets.insert(row.id)
            }
            for asset in assets {
                if let directoryID = asset.sourceDirectoryID,
                   let relativePath = asset.sourceRelativePath {
                    let identity = sourceIdentity(directoryID: directoryID, relativePath: relativePath)
                    sourceIdentities.insert(identity)
                    assetsByIdentity[identity, default: []].append(asset)
                } else {
                    legacySourceNames.insert(asset.sourceName)
                    assetsByLegacyName[asset.sourceName, default: []].append(asset)
                }
            }
        }

        assignedSourceIdentities = sourceIdentities
        assignedLegacySourceNames = legacySourceNames
        assetsBySourceIdentity = assetsByIdentity
        assetsByLegacySourceName = assetsByLegacyName

        let previousCapturedRows = capturedBrollRowIDs
        capturedBrollRowIDs.formUnion(rowsWithAssets)
        if capturedBrollRowIDs != previousCapturedRows {
            defaults.set(capturedBrollRowIDs.sorted(), forKey: capturedBrollRowsKey)
        }
    }

    private func makeUndoSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            scriptText: scriptText,
            splitMode: splitMode,
            preservesEmptyAnchors: preservesEmptyAnchors,
            assignments: assignments,
            anchorNotes: anchorNotes,
            rollTypeOverrides: rollTypeOverrides,
            capturedBrollRowIDs: capturedBrollRowIDs,
            arollProductionMethods: arollProductionMethods,
            arollShootingDevices: arollShootingDevices,
            brollProductionMethods: brollProductionMethods,
            brollPreparationStatuses: brollPreparationStatuses,
            animationTasks: animationTasks
        )
    }

    private func registerUndo(named actionName: String, restoring snapshot: UndoSnapshot) {
        guard undoManager.isUndoing || undoManager.isRedoing || makeUndoSnapshot() != snapshot else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                let current = model.makeUndoSnapshot()
                model.registerUndo(named: actionName, restoring: current)
                model.applyUndoSnapshot(snapshot)
                model.reconcileArchiveCopies(from: current, to: snapshot)
                model.undoManager.setActionName(actionName)
            }
        }
        undoManager.setActionName(actionName)
        refreshUndoAvailability()
    }

    private func applyUndoSnapshot(_ snapshot: UndoSnapshot) {
        scriptText = snapshot.scriptText
        splitMode = snapshot.splitMode
        preservesEmptyAnchors = snapshot.preservesEmptyAnchors
        parseScript(persist: false)
        assignments = snapshot.assignments
        anchorNotes = snapshot.anchorNotes
        rollTypeOverrides = snapshot.rollTypeOverrides
        capturedBrollRowIDs = snapshot.capturedBrollRowIDs
        arollProductionMethods = snapshot.arollProductionMethods
        arollShootingDevices = snapshot.arollShootingDevices
        brollProductionMethods = snapshot.brollProductionMethods
        brollPreparationStatuses = snapshot.brollPreparationStatuses
        animationTasks = snapshot.animationTasks
        rebuildAssignmentIndexes()
        persistPreferences()
        if destinationDirectoryURL != nil {
            _ = saveManifest(showMessage: false)
            saveConfirmedProjectScriptIfPresent()
        }
        let action = undoManager.isUndoing ? "已撤回到" : "已恢复到"
        lastSaved = "\(action) \(Self.timeString())"
    }

    private func reconcileArchiveCopies(from current: UndoSnapshot, to target: UndoSnapshot) {
        let removedNames = current.archivedNames.subtracting(target.archivedNames)
        if let brollDirectoryURL {
            for name in removedNames where name == (name as NSString).lastPathComponent {
                try? FileManager.default.removeItem(at: brollDirectoryURL.appendingPathComponent(name))
            }
        }

        let restoredNames = target.archivedNames.subtracting(current.archivedNames)
        guard !restoredNames.isEmpty else {
            if !removedNames.isEmpty { refreshSourceFiles() }
            return
        }

        guard let brollDirectoryURL else { return }

        var copies: [ArchiveCopy] = []
        for asset in target.assignments.values.flatMap({ $0 }) where restoredNames.contains(asset.outputName) {
            guard let sourceURL = sourceURL(for: asset) else { continue }
            let destinationURL = brollDirectoryURL.appendingPathComponent(asset.outputName)
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
            statusMessage = "撤回了绑定记录；无法从已连接的素材目录恢复已删除的归档副本"
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

    private func currentCodexManifest() -> CodexBrollManifest {
        let manifest = currentManifest()
        return CodexBrollManifest(
            placements: manifest.placements.map { placement in
                CodexBrollPlacement(text: placement.text, files: placement.files)
            }
        )
    }

    private func encodedJSON<T: Encodable>(_ manifest: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private func writeManifest(_ manifest: BrollManifest, to directoryURL: URL) throws {
        try encodedJSON(manifest).write(
            to: directoryURL.appendingPathComponent("broll-manifest.json"),
            options: .atomic
        )
        let codexManifest = CodexBrollManifest(
            placements: manifest.placements.map { placement in
                CodexBrollPlacement(text: placement.text, files: placement.files)
            }
        )
        try encodedJSON(codexManifest).write(
            to: directoryURL.appendingPathComponent("broll-for-codex.json"),
            options: .atomic
        )
    }

    private func restoreManifestFromDestination() {
        guard let brollDirectoryURL else { return }
        let manifestURL = brollDirectoryURL.appendingPathComponent("broll-manifest.json")
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
                        sourceDirectoryID: nil,
                        sourceRelativePath: nil,
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
            statusMessage = "无法读取 B-roll 文件夹中的映射文件：\(error.localizedDescription)"
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
            statusMessage = "本机配对记录保存失败，请保留 B-roll 文件夹中的映射文件"
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
        if let url = resolvedBookmark(forKey: destinationBookmarkKey) {
            destinationDirectoryURL = url
            destinationAccessActive = url.startAccessingSecurityScopedResource()
            do {
                try prepareProjectFolders(at: url)
                if loadProjectState(at: url) {
                    updateProjectRestoreStatus(for: url)
                }
            } catch {
                showError(
                    title: "无法准备剪辑项目文件夹",
                    message: "创建 B-roll、A-roll 文件夹或整理旧的 B-roll 文件时失败：\(error.localizedDescription)"
                )
            }
        } else if let url = resolvedBookmark(forKey: sourceBookmarkKey), isDirectoryReachable(url) {
            activateSourceDirectory(url)
        }
        refreshSourceFiles()
    }

    private func observeExternalVolumeChanges() {
        let workspace = NSWorkspace.shared
        let mountCenter = workspace.notificationCenter
        let mountObserver = mountCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: workspace,
            queue: .main
        ) { [weak self] notification in
            guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor [weak self] in
                self?.handleMountedVolume(at: volumeURL)
            }
        }
        volumeNotificationObservers.append((mountCenter, mountObserver))

        let unmountObserver = mountCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: workspace,
            queue: .main
        ) { [weak self] notification in
            guard let mountedPath = notification.userInfo?["NSDevicePath"] as? String else { return }
            Task { @MainActor [weak self] in
                self?.handleUnmountedVolume(at: mountedPath)
            }
        }
        volumeNotificationObservers.append((mountCenter, unmountObserver))
    }

    private func handleUnmountedVolume(at mountedPath: String) {
        let volumePath = URL(fileURLWithPath: mountedPath, isDirectory: true).standardizedFileURL.path
        let disconnectedIDs = sourceDirectories.compactMap { reference -> String? in
            let activePath = sourceDirectoryURLs[reference.id]?.standardizedFileURL.path
            return path(reference.path, isInside: volumePath) || activePath.map { path($0, isInside: volumePath) } == true
                ? reference.id
                : nil
        }
        guard !disconnectedIDs.isEmpty else { return }

        disconnectedIDs.forEach(disconnectSourceDirectory)
        sourceDirectoryURL = sourceDirectories.reversed().compactMap { sourceDirectoryURLs[$0.id] }.first
        refreshSourceFiles()
        statusMessage = "素材磁盘已弹出；重新插入后会自动恢复素材列表。"
    }

    private func handleMountedVolume(at volumeURL: URL) {
        let reconnectedCount = reconnectAvailableSourceDirectories(
            mountedVolumeURL: volumeURL,
            forceRefreshAccess: true
        )
        guard reconnectedCount > 0 else { return }
        refreshSourceFiles()
        statusMessage = "素材磁盘已重新连接，正在刷新素材列表。"
    }

    @discardableResult
    private func reconnectAvailableSourceDirectories(
        mountedVolumeURL: URL? = nil,
        forceRefreshAccess: Bool
    ) -> Int {
        var reconnectedCount = 0
        let previousCurrentDirectoryID = sourceDirectoryURL.flatMap { currentURL in
            sourceDirectories.first {
                sourceDirectoryURLs[$0.id]?.standardizedFileURL == currentURL.standardizedFileURL
            }?.id
        }

        for reference in sourceDirectories {
            let resolvedURL = resolveProjectSourceDirectory(reference)
            guard let resolvedURL, isDirectoryReachable(resolvedURL) else {
                if mountedVolumeURL == nil {
                    disconnectSourceDirectory(reference.id)
                }
                continue
            }

            if let mountedVolumeURL {
                let volumePath = mountedVolumeURL.standardizedFileURL.path
                let activePath = sourceDirectoryURLs[reference.id]?.standardizedFileURL.path
                guard path(resolvedURL.path, isInside: volumePath) ||
                        path(reference.path, isInside: volumePath) ||
                        activePath.map({ path($0, isInside: volumePath) }) == true else {
                    continue
                }
            }

            let currentURL = sourceDirectoryURLs[reference.id]
            let sameURL = currentURL?.standardizedFileURL == resolvedURL.standardizedFileURL
            guard forceRefreshAccess || !sameURL || sourceAccessActive[reference.id] != true else { continue }

            activateSourceDirectory(
                resolvedURL,
                reference: reference,
                refresh: false,
                forceRefreshAccess: forceRefreshAccess || !sameURL
            )
            reconnectedCount += 1
        }

        if sourceDirectories.isEmpty,
           let url = resolvedBookmark(forKey: sourceBookmarkKey),
           isDirectoryReachable(url),
           mountedVolumeURL.map({ path(url.path, isInside: $0.path) }) ?? true {
            activateSourceDirectory(url, refresh: false, forceRefreshAccess: forceRefreshAccess)
            reconnectedCount += 1
        }

        if let previousCurrentDirectoryID,
           let currentURL = sourceDirectoryURLs[previousCurrentDirectoryID] {
            sourceDirectoryURL = currentURL
        }

        return reconnectedCount
    }

    private func disconnectSourceDirectory(_ id: String) {
        sourceDirectoryWatchers.removeValue(forKey: id)?.stop()
        let url = sourceDirectoryURLs.removeValue(forKey: id)
        if sourceAccessActive.removeValue(forKey: id) == true {
            url?.stopAccessingSecurityScopedResource()
        }
        if let url, sourceDirectoryURL?.standardizedFileURL == url.standardizedFileURL {
            sourceDirectoryURL = sourceDirectories.reversed().compactMap { sourceDirectoryURLs[$0.id] }.first
        }
    }

    private func isDirectoryReachable(_ url: URL) -> Bool {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func path(_ path: String, isInside rootPath: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        let normalizedRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let rootPrefix = normalizedRoot == "/" ? "/" : normalizedRoot + "/"
        return normalizedPath == normalizedRoot || normalizedPath.hasPrefix(rootPrefix)
    }

    private func activateSourceDirectory(
        _ url: URL,
        reference: ProjectSourceDirectory? = nil,
        persistProjectSettings: Bool = true,
        refresh: Bool = true,
        forceRefreshAccess: Bool = false
    ) {
        let normalizedURL = url.standardizedFileURL
        let existingReference = reference ?? sourceDirectories.first {
            sourceDirectoryURLs[$0.id]?.standardizedFileURL == normalizedURL || $0.path == normalizedURL.path
        }
        let sourceReference = makeProjectSourceDirectory(
            for: normalizedURL,
            id: existingReference?.id
        )
        if let index = sourceDirectories.firstIndex(where: { $0.id == sourceReference.id }) {
            sourceDirectories[index] = sourceReference
        } else {
            sourceDirectories.append(sourceReference)
        }

        let previousURL = sourceDirectoryURLs[sourceReference.id]
        let sameURL = previousURL?.standardizedFileURL == normalizedURL
        let shouldRestartAccess = forceRefreshAccess || !sameURL || sourceAccessActive[sourceReference.id] != true
        if shouldRestartAccess {
            if sourceAccessActive.removeValue(forKey: sourceReference.id) == true {
                previousURL?.stopAccessingSecurityScopedResource()
            }
            sourceDirectoryWatchers.removeValue(forKey: sourceReference.id)?.stop()
            sourceAccessActive[sourceReference.id] = normalizedURL.startAccessingSecurityScopedResource()
        }

        sourceDirectoryURLs[sourceReference.id] = normalizedURL
        sourceDirectoryReadFailures.remove(sourceReference.id)
        sourceDirectoryURL = normalizedURL
        storeBookmark(for: normalizedURL, key: sourceBookmarkKey)
        sourceDirectoryWatchers.removeValue(forKey: sourceReference.id)?.stop()
        watchSourceDirectory(normalizedURL, id: sourceReference.id)
        if destinationDirectoryURL != nil, persistProjectSettings {
            saveProjectSettings()
        }
        if refresh {
            refreshSourceFiles()
        }
    }

    private func watchSourceDirectory(_ url: URL, id: String) {
        let watcher = SourceDirectoryWatcher(directoryURL: url) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.scheduleSourceRefresh()
            }
        }
        sourceDirectoryWatchers[id] = watcher
        watcher.start()
    }

    private func scheduleSourceRefresh() {
        sourceRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sourceRefreshWorkItem = nil
            self.refreshSourceFiles()
        }
        sourceRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    @discardableResult
    private func activateDestinationDirectory(_ url: URL) -> Bool {
        let isSameDirectory = destinationDirectoryURL?.standardizedFileURL == url.standardizedFileURL
        let didStartAccess = isSameDirectory
            ? destinationAccessActive
            : url.startAccessingSecurityScopedResource()

        do {
            try prepareProjectFolders(at: url)
        } catch {
            if !isSameDirectory, didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
            showError(
                title: "无法准备剪辑项目文件夹",
                message: "创建 B-roll、A-roll 文件夹或整理旧的 B-roll 文件时失败：\(error.localizedDescription)"
            )
            return false
        }

        if !isSameDirectory {
            discardUndoActions()
            if destinationAccessActive {
                destinationDirectoryURL?.stopAccessingSecurityScopedResource()
            }
            destinationDirectoryURL = url
            destinationAccessActive = didStartAccess
        }
        storeBookmark(for: url, key: destinationBookmarkKey)
        return true
    }

    private func prepareProjectFolders(at projectURL: URL) throws {
        let fileManager = FileManager.default
        let brollURL = projectURL.appendingPathComponent("B-roll", isDirectory: true)
        let aRollURL = projectURL.appendingPathComponent("A-roll", isDirectory: true)
        try fileManager.createDirectory(at: brollURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: aRollURL, withIntermediateDirectories: true)

        var legacyAssetNames = Set(assignments.values.flatMap { $0.map(\.outputName) })
        let rootManifestURL = projectURL.appendingPathComponent("broll-manifest.json")
        if let data = try? Data(contentsOf: rootManifestURL),
           let manifest = try? JSONDecoder().decode(BrollManifest.self, from: data) {
            legacyAssetNames.formUnion(manifest.placements.flatMap(\.files))
        }
        legacyAssetNames.formUnion(try ArchiveCleaner.discoverCopies(
            in: projectURL,
            mediaExtensions: Self.videoExtensions.union(Self.imageExtensions)
        ))

        let configNames = ["broll-for-codex.json", "broll-manifest.json"]
        let assetURLs = legacyAssetNames
            .filter { !$0.isEmpty && $0 == ($0 as NSString).lastPathComponent && $0 != "." && $0 != ".." }
            .map { projectURL.appendingPathComponent($0) }
        for sourceURL in assetURLs + configNames.map({ projectURL.appendingPathComponent($0) })
        where fileManager.fileExists(atPath: sourceURL.path) {
            let destinationURL = brollURL.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                guard fileManager.contentsEqual(atPath: sourceURL.path, andPath: destinationURL.path) else {
                    throw NSError(
                        domain: "BrollNamer.ProjectFolders",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "B-roll 中已存在同名文件，但内容不同：\(sourceURL.lastPathComponent)"]
                    )
                }
                try fileManager.removeItem(at: sourceURL)
            } else {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
        }
    }

    private func loadProjectState(at projectURL: URL) -> Bool {
        guard let settingsURL = projectSettingsURL,
              let brollDirectoryURL else { return false }
        let fileManager = FileManager.default
        let settings: BrollProjectSettings

        if fileManager.fileExists(atPath: settingsURL.path) {
            do {
                settings = try JSONDecoder().decode(
                    BrollProjectSettings.self,
                    from: Data(contentsOf: settingsURL)
                )
                guard (1...4).contains(settings.formatVersion) else {
                    throw NSError(
                        domain: "BrollNamer.ProjectSettings",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "不支持的项目设置格式：\(settings.formatVersion)"]
                    )
                }
            } catch {
                showError(title: "无法读取项目设置", message: error.localizedDescription)
                return false
            }
        } else {
            settings = legacyProjectSettings(in: brollDirectoryURL)
        }

        let script: String
        do {
            script = try loadProjectScript(in: projectURL)
        } catch {
            showError(title: "无法读取正确文案", message: error.localizedDescription)
            return false
        }

        discardUndoActions()
        projectID = settings.projectID
        prefix = settings.prefix
        splitMode = settings.splitMode
        preservesEmptyAnchors = settings.preservesEmptyAnchors
        anchorNotes = settings.anchorNotes
        rollTypeOverrides = settings.rollTypeOverrides
        capturedBrollRowIDs = Set(settings.capturedBrollRowIDs)
        arollProductionMethods = settings.arollProductionMethods
        arollShootingDevices = settings.arollShootingDevices.mapValues { saved -> ShootingDevice? in
            guard let saved else { return nil }
            return shootingDevices.first(where: { $0.id == saved.id }) ?? saved
        }
        brollProductionMethods = settings.brollProductionMethods
        cancelAnimationAnalysis()
        animationFeedback = ""
        animationTasks = settings.animationTasks
        brollPreparationStatuses = settings.brollPreparationStatuses.filter { $0.value != .bound }
        for rowID in capturedBrollRowIDs where brollPreparationStatuses[rowID] == nil {
            brollPreparationStatuses[rowID] = .ready
        }
        assignments = migratingLegacyAssignments(settings.assignments, to: settings.sourceDirectories)
        scriptText = script
        rows = []
        rebuildAssignmentIndexes()
        parseScript(persist: false)

        clearSourceDirectories()
        sourceDirectories = settings.sourceDirectories
        for reference in settings.sourceDirectories {
            if let sourceURL = resolveProjectSourceDirectory(reference) {
                activateSourceDirectory(sourceURL, reference: reference, persistProjectSettings: false, refresh: false)
            }
        }

        restoreManifestFromDestination()
        _ = migrateAnimationReasonsToNotes()
        persistPreferences()
        return true
    }

    private func updateProjectRestoreStatus(for projectURL: URL) {
        if sourceDirectories.isEmpty {
            statusMessage = "项目已连接，但尚未记录素材来源目录。请选择素材目录，之后会随项目自动恢复。"
        } else {
            let unavailable = sourceDirectories.filter { sourceDirectoryURLs[$0.id] == nil }
            if !unavailable.isEmpty {
                statusMessage = "项目已连接；以下素材目录当前不可用，插入磁盘后会自动恢复：\(unavailable.map(\.path).joined(separator: "、"))"
                return
            }
            statusMessage = "已恢复剪辑项目：\(projectURL.lastPathComponent)，已连接 \(sourceDirectories.count) 个素材目录"
        }
    }

    private func migratingLegacyAssignments(
        _ assignments: [String: [BrollAsset]],
        to directories: [ProjectSourceDirectory]
    ) -> [String: [BrollAsset]] {
        guard directories.count == 1 else { return assignments }
        let directory = directories[0]
        return assignments.mapValues { assets in
            assets.map { asset in
                guard asset.sourceDirectoryID == nil else { return asset }
                return BrollAsset(
                    id: asset.id,
                    anchorKey: asset.anchorKey,
                    anchorIndex: asset.anchorIndex,
                    anchorText: asset.anchorText,
                    sourceName: asset.sourceName,
                    sourceDirectoryID: directory.id,
                    sourceRelativePath: asset.sourceName,
                    outputName: asset.outputName,
                    mode: asset.mode,
                    targetTrack: asset.targetTrack,
                    audio: asset.audio,
                    copiedAt: asset.copiedAt
                )
            }
        }
    }

    private func loadProjectScript(in projectURL: URL) throws -> String {
        let fileManager = FileManager.default
        let currentURL = projectURL
            .appendingPathComponent("A-roll", isDirectory: true)
            .appendingPathComponent("正确文案.txt")
        if fileManager.fileExists(atPath: currentURL.path) {
            return try String(contentsOf: currentURL, encoding: .utf8)
        }

        let legacyURL = projectURL.appendingPathComponent("正确文案.txt")
        guard fileManager.fileExists(atPath: legacyURL.path) else { return "" }
        let text = try String(contentsOf: legacyURL, encoding: .utf8)
        try? fileManager.moveItem(at: legacyURL, to: currentURL)
        return text
    }

    private func legacyProjectSettings(in brollURL: URL) -> BrollProjectSettings {
        BrollProjectSettings(
            prefix: inferredLegacyPrefix(in: brollURL),
            splitMode: .line,
            preservesEmptyAnchors: true
        )
    }

    private func inferredLegacyPrefix(in brollURL: URL) -> String {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: brollURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ), let expression = try? NSRegularExpression(pattern: #"^(.+)_BR[0-9]{3,}_"#) else {
            return ""
        }

        let prefixes = Set(urls.compactMap { url -> String? in
            let name = url.lastPathComponent
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            guard let match = expression.firstMatch(in: name, range: range),
                  let prefixRange = Range(match.range(at: 1), in: name) else { return nil }
            return String(name[prefixRange])
        })
        return prefixes.count == 1 ? prefixes.first ?? "" : ""
    }

    private func makeProjectSourceDirectory(for url: URL, id: String? = nil) -> ProjectSourceDirectory {
        let bookmarkData = (try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ))
        return ProjectSourceDirectory(
            id: id ?? UUID().uuidString.lowercased(),
            name: url.lastPathComponent,
            path: url.standardizedFileURL.path,
            bookmarkData: bookmarkData
        )
    }

    private func resolveProjectSourceDirectory(_ reference: ProjectSourceDirectory) -> URL? {
        if let bookmarkData = reference.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let isReachable = isDirectoryReachable(url)
                if isStale, isReachable {
                    storeBookmark(for: url, key: sourceBookmarkKey)
                    if let index = sourceDirectories.firstIndex(where: { $0.id == reference.id }) {
                        sourceDirectories[index] = makeProjectSourceDirectory(for: url, id: reference.id)
                    }
                }
                return isReachable ? url : nil
            }
        }

        let pathURL = URL(fileURLWithPath: reference.path, isDirectory: true)
        return isDirectoryReachable(pathURL) ? pathURL : nil
    }

    private func clearSourceDirectories() {
        sourceScanTask?.cancel()
        sourceScanTask = nil
        sourceScanGeneration = UUID()
        sourceDirectoryWatchers.values.forEach { $0.stop() }
        sourceDirectoryWatchers.removeAll()
        sourceRefreshWorkItem?.cancel()
        sourceRefreshWorkItem = nil
        for (id, wasStarted) in sourceAccessActive where wasStarted {
            sourceDirectoryURLs[id]?.stopAccessingSecurityScopedResource()
        }
        sourceAccessActive.removeAll()
        sourceDirectoryURLs.removeAll()
        sourceDirectoryReadFailures.removeAll()
        sourceDirectories.removeAll()
        sourceDirectoryURL = nil
        selectedSourceDirectoryID = nil
        selectedSourceFileURL = nil
        installSourceFiles([])
    }

    private func saveProjectSettings() {
        guard let projectSettingsURL else { return }

        let settings = BrollProjectSettings(
            projectID: projectID,
            prefix: prefix,
            sourceDirectories: sourceDirectories,
            splitMode: splitMode,
            preservesEmptyAnchors: preservesEmptyAnchors,
            anchorNotes: anchorNotes,
            rollTypeOverrides: rollTypeOverrides,
            capturedBrollRowIDs: capturedBrollRowIDs.sorted(),
            arollProductionMethods: arollProductionMethods,
            arollShootingDevices: arollShootingDevices.mapValues { saved -> ShootingDevice? in
                guard let saved else { return nil }
                return shootingDevices.first(where: { $0.id == saved.id }) ?? saved
            },
            brollProductionMethods: brollProductionMethods,
            brollPreparationStatuses: brollPreparationStatuses,
            assignments: assignments,
            animationTasks: animationTasks
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: projectSettingsURL, options: .atomic)
        } catch {
            statusMessage = "无法保存 B-roll/project-settings.json：\(error.localizedDescription)"
        }
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

private final class SourceDirectoryWatcher {
    private let directoryURL: URL
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var isRunning = false

    init(directoryURL: URL, onChange: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, clientInfo, _, _, _, _ in
            guard let clientInfo else { return }
            let watcher = Unmanaged<SourceDirectoryWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            watcher.onChange()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [directoryURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.35,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            stop()
            return
        }
        isRunning = true
    }

    func stop() {
        guard let stream else { return }
        if isRunning {
            FSEventStreamStop(stream)
        }
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        isRunning = false
    }

    deinit {
        stop()
    }
}

@MainActor
private enum FinderItemOpener {
    static func reveal(_ url: URL) throws {
        let targetURL = url.standardizedFileURL
        let isDirectory = (try? targetURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

        if isDirectory {
            guard NSWorkspace.shared.open(targetURL) else {
                throw FinderItemError.couldNotOpen
            }
        } else {
            let parentURL = targetURL.deletingLastPathComponent()
            guard NSWorkspace.shared.selectFile(
                targetURL.path,
                inFileViewerRootedAtPath: parentURL.path
            ) else {
                throw FinderItemError.couldNotOpen
            }
        }
    }
}

private enum FinderItemError: LocalizedError {
    case couldNotOpen

    var errorDescription: String? {
        "系统未能打开 Finder 或定位目标，请确认该文件或文件夹仍然存在。"
    }
}

extension AppModel {
    var animationScriptRowCount: Int {
        rows.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var activeAnimationTasks: [AnimationTask] {
        var reserved = Set(animationTasks.map(\.outputFilename))
        return rows.compactMap { row in
            guard rollType(for: row.id) == .bRoll, brollProductionMethod(for: row.id) == .animation,
                  !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            if let task = animationTasks.first(where: { $0.rowID == row.id && $0.text == row.text }) {
                return task
            }
            // Manually tagged and edited animation rows can use the same prompt workflow without AI analysis.
            let filename = AnimationWorkflow.filename(for: row.text, reserved: reserved)
            reserved.insert(filename)
            return AnimationTask(id: "manual-animation-" + row.id, rowID: row.id, text: row.text,
                                 reason: note(for: row.id), outputFilename: filename, reasonAddedToNotes: true)
        }
    }

    func animationTask(for rowID: String) -> AnimationTask? {
        activeAnimationTasks.first { $0.rowID == rowID }
    }

    func openAnimationPanel() {
        do { deepSeekKeyDraft = try DeepSeekKeychain.read() }
        catch { animationFeedback = error.localizedDescription }
        isAnimationPanelPresented = true
    }

    @discardableResult
    func setAnimationCharacterImage(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else {
            animationFeedback = "请选择或拖入可读取的图片文件。"
            return false
        }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            // Read all bytes while access is active; NSImage(contentsOf:) can defer file reads.
            guard let image = NSImage(data: try Data(contentsOf: url)) else {
                animationFeedback = "请选择或拖入可读取的图片文件。"
                return false
            }
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: animationCharacterBookmarkKey)
            animationCharacterPath = url.path
            animationCharacterImage = image
            defaults.set(animationCharacterPath, forKey: animationCharacterKey)
            animationFeedback = "角色参考图已保存，复制提示词时会带上角色替换说明。"
            return true
        } catch {
            animationFeedback = "角色参考图保存失败，请重新选择图片：\(error.localizedDescription)"
            return false
        }
    }

    private func restoreAnimationCharacterImage() {
        guard !animationCharacterPath.isEmpty else { return }
        if let bookmark = defaults.data(forKey: animationCharacterBookmarkKey) {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                  relativeTo: nil, bookmarkDataIsStale: &isStale)
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
                guard let image = NSImage(data: try Data(contentsOf: url)) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                if isStale {
                    let renewed = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                       includingResourceValuesForKeys: nil, relativeTo: nil)
                    defaults.set(renewed, forKey: animationCharacterBookmarkKey)
                }
                if URL(fileURLWithPath: animationCharacterPath).resolvingSymlinksInPath() != url.resolvingSymlinksInPath() {
                    animationCharacterPath = url.path
                }
                animationCharacterImage = image
                defaults.set(animationCharacterPath, forKey: animationCharacterKey)
                return
            } catch {
                // Keep the saved path so an unavailable file can be reselected.
            }
        } else if setAnimationCharacterImage(URL(fileURLWithPath: animationCharacterPath)) {
            // Migrate old path-only settings when access is still available.
            animationFeedback = ""
            return
        }
        animationFeedback = "无法读取已保存的角色参考图，请重新选择图片以恢复预览和访问权限。"
    }

    func removeAnimationCharacterImage() {
        animationCharacterPath = ""
        animationCharacterImage = nil
        defaults.removeObject(forKey: animationCharacterKey)
        defaults.removeObject(forKey: animationCharacterBookmarkKey)
        animationFeedback = "已移除角色参考图，提示词会保留使用你提供的角色参考图的说明。"
    }

    @discardableResult
    func saveAnimationConfiguration(saveAPIKey: Bool = true) -> Bool {
        guard !animationRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !animationTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            animationFeedback = "判断规则和制作模板不能为空。"
            return false
        }
        do {
            if saveAPIKey {
                try DeepSeekKeychain.save(deepSeekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            defaults.set(animationRules, forKey: animationRulesKey)
            defaults.set(animationTemplate, forKey: animationTemplateKey)
            defaults.set(animationCharacterPath.trimmingCharacters(in: .whitespacesAndNewlines), forKey: animationCharacterKey)
            animationOutputDirectoryPath = animationOutputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(animationOutputDirectoryPath, forKey: animationOutputDirectoryKey)
            animationFeedback = saveAPIKey ? "设置已保存；API Key 存放在本机钥匙串。" : "设置已保存。"
            return true
        } catch {
            animationFeedback = error.localizedDescription
            return false
        }
    }

    func testDeepSeekConnection() async {
        guard !isTestingDeepSeek, !isAnalyzingAnimations, saveAnimationConfiguration() else { return }
        isTestingDeepSeek = true
        defer { isTestingDeepSeek = false }
        do {
            try await DeepSeekClient(apiKey: deepSeekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)).testConnection()
            animationFeedback = "连接成功，deepseek-flash 可用。"
        } catch { animationFeedback = error.localizedDescription }
    }

    func startAnimationAnalysis() {
        guard !isAnalyzingAnimations, !isTestingDeepSeek, !isBusy else { return }
        guard animationScriptRowCount > 0 else { animationFeedback = "请先导入文案。"; return }
        guard !deepSeekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            animationFeedback = "请先填写 DeepSeek API Key。"
            return
        }
        guard saveAnimationConfiguration() else { return }
        discardAnimationReview()
        let before = makeUndoSnapshot()
        let sourceRows = rows
        let expectedProject = projectID
        let requestID = UUID()
        animationRequestID = requestID
        let client = DeepSeekClient(apiKey: deepSeekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        let rules = animationRules
        isAnalyzingAnimations = true
        animationFeedback = "正在分析全文，所有有文字的条目都参与动画判断。"
        animationRequest = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.animationRequestID == requestID {
                    self.isAnalyzingAnimations = false
                    self.animationRequest = nil
                }
            }
            do {
                let candidates = try await client.analyze(rows: sourceRows, rules: rules)
                try Task.checkCancellation()
                guard self.animationRequestID == requestID else { return }
                guard self.projectID == expectedProject, self.makeUndoSnapshot() == before, !self.isBusy else {
                    self.animationFeedback = "分析期间文案、条目设置或项目发生变化，结果未应用，请重新分析。"
                    return
                }
                try self.stageAnimationReview(candidates)
            } catch {
                if self.animationRequestID == requestID {
                    self.animationFeedback = Task.isCancelled ? "已取消分析，文案未修改。" : error.localizedDescription
                }
            }
        }
    }

    /// Keep independently valid suggestions even if another AI suggestion cannot be safely located.
    func stageAnimationReview(_ candidates: [AnimationCandidate]) throws {
        discardAnimationReview()
        guard !candidates.isEmpty else {
            animationFeedback = "这段文案没有明显需要示意动画的部分，文案未修改。"
            return
        }
        var valid: [AnimationCandidate] = []
        var issues: [String] = []
        for (index, candidate) in candidates.enumerated() {
            do {
                let resolved = try AnimationWorkflow.resolveCandidate(candidate, rows: rows)
                _ = try AnimationWorkflow.split(rows: rows, candidates: valid + [resolved])
                valid.append(resolved)
            } catch {
                let reason = error.localizedDescription.replacingOccurrences(of: "，本次未修改文案。", with: "")
                issues.append("第 \(index + 1) 段：\(reason)")
            }
        }
        guard !valid.isEmpty else {
            animationFeedback = "AI 返回的 \(candidates.count) 段建议均未通过原文校验，请重新分析。\(issues.first ?? "")；文案未修改。"
            return
        }
        let numbers = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.index) })
        animationReviewItems = valid.map {
            AnimationReviewItem(candidate: $0, rowNumbers: $0.sourceRowIDs.compactMap { numbers[$0] })
        }
        animationReviewBaseline = (projectID, makeUndoSnapshot())
        animationFeedback = "DeepSeek 推荐了 \(valid.count) 段，确认后才会拆分文案。"
        if !issues.isEmpty {
            animationFeedback += "跳过 \(issues.count) 段未通过校验的建议（\(issues[0])）。"
        }
    }

    func applyAnimationReview() {
        let selected = animationReviewItems.filter(\.isSelected).map(\.candidate)
        guard !selected.isEmpty else { animationFeedback = "请至少勾选一段。"; return }
        guard let baseline = animationReviewBaseline, baseline.project == projectID,
              baseline.snapshot == makeUndoSnapshot(), !isBusy else {
            discardAnimationReview()
            animationFeedback = "文案或条目设置已变化，推荐结果已失效，请重新分析。"
            return
        }
        do {
            try applyAnimationCandidates(selected)
            discardAnimationReview()
            isAnimationPanelPresented = false
        } catch {
            animationFeedback = error.localizedDescription
        }
    }

    func discardAnimationReview() {
        animationReviewItems = []
        animationReviewBaseline = nil
    }

    func cancelAnimationAnalysis() {
        discardAnimationReview()
        animationRequestID = UUID()
        animationRequest?.cancel()
        animationRequest = nil
        isAnalyzingAnimations = false
        animationFeedback = "已取消分析，文案未修改。"
    }

    /// Shared by the network path and deterministic workflow verification.
    func applyAnimationCandidates(_ candidates: [AnimationCandidate]) throws {
        let pieces = try AnimationWorkflow.split(rows: rows, candidates: candidates)
        guard !candidates.isEmpty else {
            animationFeedback = "这段文案没有明显需要示意动画的部分，文案未修改。"
            return
        }
        let before = makeUndoSnapshot()
        applyInlineRows(pieces.map(\.text), sourceIndices: pieces.map(\.sourceIndices))
        var reserved = Set(animationTasks.map(\.outputFilename))
        var addedCount = 0
        var updatedCount = 0
        for index in pieces.indices {
            guard let candidate = pieces[index].candidate else { continue }
            let row = rows[index]
            let previousReason = animationTasks.first { $0.rowID == row.id && $0.text == row.text }?.reason
            addAnimationReasonToNote(candidate.reason, for: row.id, replacing: previousReason)
            if let taskIndex = animationTasks.firstIndex(where: { $0.rowID == row.id && $0.text == row.text }) {
                animationTasks[taskIndex].reason = candidate.reason
                animationTasks[taskIndex].reasonAddedToNotes = true
                updatedCount += 1
            } else {
                let filename = AnimationWorkflow.filename(for: row.text, reserved: reserved)
                reserved.insert(filename)
                animationTasks.append(AnimationTask(id: UUID().uuidString.lowercased(), rowID: row.id, text: row.text,
                                                    reason: candidate.reason, outputFilename: filename, reasonAddedToNotes: true))
                brollPreparationStatuses[row.id] = .pending
                capturedBrollRowIDs.remove(row.id)
                addedCount += 1
            }
            rollTypeOverrides[row.id] = .bRoll
            brollProductionMethods[row.id] = .animation
        }
        persistPreferences()
        registerUndo(named: "AI 分析并拆分动画文案", restoring: before)
        animationFeedback = "已新增 \(addedCount) 条、更新 \(updatedCount) 条动画文案；在文案列表筛选“动画 + 待准备”查看制作清单，可使用 ⌘Z 撤销。"
        statusMessage = animationFeedback
    }

    /// Migrate once so editing or clearing a note never resurrects the old AI reason.
    @discardableResult
    private func migrateAnimationReasonsToNotes() -> Bool {
        var changed = false
        for index in animationTasks.indices {
            let task = animationTasks[index]
            guard task.reasonAddedToNotes != true,
                  rows.contains(where: { $0.id == task.rowID && $0.text == task.text }) else { continue }
            addAnimationReasonToNote(task.reason, for: task.rowID)
            animationTasks[index].reasonAddedToNotes = true
            changed = true
        }
        return changed
    }

    private func addAnimationReasonToNote(_ reason: String, for rowID: String, replacing previous: String? = nil) {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        let existing = anchorNotes[rowID] ?? ""
        if let previous, !previous.isEmpty, existing == previous {
            anchorNotes[rowID] = reason
        } else if let previous, !previous.isEmpty, existing.hasSuffix("\n\n" + previous) {
            anchorNotes[rowID] = String(existing.dropLast(previous.count)) + reason
        } else if !existing.contains(reason) {
            anchorNotes[rowID] = existing.isEmpty ? reason : existing + "\n\n" + reason
        }
    }

    private func animationPromptTask(_ task: AnimationTask) -> AnimationTask {
        var result = task
        // The editable production note is the source of the exported expression focus.
        result.reason = note(for: task.rowID)
        return result
    }

    @discardableResult
    func copyAnimationPrompt(_ task: AnimationTask) -> Bool {
        NSPasteboard.general.clearContents()
        let didCopy = NSPasteboard.general.setString(AnimationWorkflow.prompt(for: animationPromptTask(task), template: animationTemplate, character: animationCharacterPath, outputDirectory: animationOutputDirectoryPath), forType: .string)
        animationFeedback = didCopy ? "已复制完整制作提示词。" : "复制失败，请重试。"
        return didCopy
    }

    @discardableResult
    func copyAllAnimationPrompts() -> Bool {
        let tasks = activeAnimationTasks
        guard !tasks.isEmpty else { animationFeedback = "没有可复制的动画任务。"; return false }
        NSPasteboard.general.clearContents()
        let didCopy = NSPasteboard.general.setString(AnimationWorkflow.prompts(for: tasks.map { animationPromptTask($0) }, template: animationTemplate, character: animationCharacterPath, outputDirectory: animationOutputDirectoryPath), forType: .string)
        animationFeedback = didCopy ? "已复制 \(tasks.count) 条完整制作提示词，可直接粘贴给制作动画的 AI。" : "复制失败，请重试。"
        return didCopy
    }
}
