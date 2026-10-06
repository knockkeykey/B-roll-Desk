import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
private func rejects(_ message: String, _ work: () throws -> Void) {
    do { try work(); fatalError("Expected rejection: " + message) }
    catch { print("PASS rejection: " + message) }
}
@MainActor private func event(_ model: AppModel, _ work: () throws -> Void) rethrows {
    model.undoManager.beginUndoGrouping()
    defer { model.undoManager.endUndoGrouping() }
    try work()
}
private final class PreflightMockProtocol: URLProtocol {
    static var body = ""
    static var lastBody: [String: Any] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let data = request.httpBody { Self.lastBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096); var data = Data()
            while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
            Self.lastBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ShootingPreflightTests {
    @MainActor static func main() async throws {
        let rows = [AnchorRow(id: "1", index: 1, text: "开始操作。"), AnchorRow(id: "2", index: 2, text: "展示结果。")]
        let segments = [SpokenSegment(text: "开始操作", start: 0, end: 4), SpokenSegment(text: "展示结果", start: 4, end: 8)]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PreflightMockProtocol.self]
        let candidateJSON: [String: Any] = ["candidates": [["source_row_ids": ["1"], "text": "开始操作。", "reason": "操作", "visual_hint": "展示操作界面"]]]
        let completionJSON: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": String(decoding: try JSONSerialization.data(withJSONObject: candidateJSON), as: UTF8.self)]]]]
        PreflightMockProtocol.body = String(decoding: try JSONSerialization.data(withJSONObject: completionJSON), as: UTF8.self)
        let ai = try await DeepSeekClient(apiKey: "test-key", session: URLSession(configuration: config)).analyzeContentGaps(rows: rows, arrangements: [["roll": "aRoll", "method": "未确定"], ["roll": "bRoll", "method": "屏幕录制"]])
        expect(ai.first?.sourceRowIDs == ["1"] && ai.first?.visualHint == "展示操作界面", "Independent content schema decodes and maps row IDs")
        let messages = PreflightMockProtocol.lastBody["messages"] as? [[String: String]] ?? []
        expect(messages.first?["content"]?.contains("visual_hint") == true && messages.last?["content"]?.contains("屏幕录制") == true, "Content analysis sends existing arrangements and independent visual hints")
        expect(messages.last?["content"]?.contains("timestamp") != true, "AI is not asked to calculate time")
        let times = SpeechTiming.align(rows: rows, segments: segments)
        expect(times.count == 2 && times["2"]?.duration == 4, "Exact transcript boundaries yield actual durations")
        expect(SpeechTiming.align(rows: rows, segments: segments + segments).isEmpty, "Repeated speech cannot invent an exact location")
        expect(SpeechTiming.align(rows: rows, segments: [.init(text: "开始操作展示结果", start: 0, end: 8)]).isEmpty, "A subtitle spanning two rows cannot infer subphrase times")
        expect(SpeechTiming.align(rows: rows, segments: [.init(text: "开始操作", start: 0, end: 4, confidence: 0.1)]).isEmpty, "Low confidence remains unconfirmed")
        let parsed = try SpeechTiming.parseSRT("1\n00:00:00,000 --> 00:00:04,000\n开始操作。\n\n2\n00:00:04,000 --> 00:00:08,000\n展示结果。\n")
        expect(SpeechTiming.align(rows: rows, segments: parsed) == times, "SRT is evidence for sentence boundaries")
        rejects("overlapping SRT") { _ = try SpeechTiming.parseSRT("1\n00:00:00,000 --> 00:00:05,000\n开始\n\n2\n00:00:04,000 --> 00:00:08,000\n结果") }
        let issues = PreflightRhythm.issues(rows: rows, timings: times, rate: 350, sameEnabled: true, sameSeconds: 5, continuousEnabled: true, continuousSeconds: 5, roll: { _ in .aRoll }, device: { _ in "sony" })
        expect(issues.count == 1 && issues[0].rules.count == 2 && issues[0].seconds == 8 && !issues[0].estimated, "Coincident reminders combine with actual time")
        let switched = PreflightRhythm.issues(rows: rows, timings: times, rate: 350, sameEnabled: true, sameSeconds: 5, continuousEnabled: true, continuousSeconds: 5, roll: { _ in .aRoll }, device: { $0 == "1" ? "sony" : "dji" })
        expect(switched.count == 1 && switched[0].rules == ["连续 A-roll"], "Device switch interrupts same-device only")
        expect(PreflightRhythm.issues(rows: rows, timings: times, rate: 350, sameEnabled: true, sameSeconds: 5, continuousEnabled: true, continuousSeconds: 5, roll: { $0 == "2" ? .bRoll : .aRoll }, device: { _ in "sony" }).isEmpty, "B-roll breaks both runs")
        let paused = SpeechTiming.align(rows: rows, segments: [.init(text: "开始操作", start: 0, end: 3), .init(text: "展示结果", start: 5, end: 9)])
        expect(paused["1"]?.duration == 5, "Actual picture time includes between-sentence pauses")
        let longer = rows + [AnchorRow(id: "3", index: 3, text: "辅设备片段")]
        let overlapIssues = PreflightRhythm.issues(rows: longer, timings: ["1": .init(start: 0, end: 4), "2": .init(start: 4, end: 8), "3": .init(start: 8, end: 12)], rate: 350, sameEnabled: true, sameSeconds: 5, continuousEnabled: true, continuousSeconds: 5, roll: { _ in .aRoll }, device: { $0 == "3" ? "dji" : "sony" })
        expect(overlapIssues.count == 1 && overlapIssues[0].details.count == 2, "Overlapping same-device and continuous reminders share one card while preserving separate durations")
        let suite = "preflight-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("前言。把视频拖入软件，就能生成字幕。结尾。\n个人感受。", forKey: "broll-namer-script")
        let model = AppModel(defaults: defaults)
        model.undoManager.groupsByEvent = false
        let original = model.rows.map(\.text).joined()
        let first = model.rows[0]
        event(model) { model.setShootingDevice(model.shootingDevices[1], for: first.id) }
        event(model) { model.setNote("原来的备注", for: first.id) }
        let candidate = ContentGapCandidate(sourceRowIDs: [first.id], text: "把视频拖入软件，就能生成字幕。", reason: "操作结果需要展示", visualHint: "展示拖入视频与生成的字幕")
        try model.stageContentGapCandidates([candidate])
        expect(model.rows.count == 2 && model.contentGapCandidates.count == 1, "Three-second candidates are independent of thresholds and don't mutate script")
        try event(model) { try model.applyContentGapCandidate(candidate) }
        expect(model.rows.map(\.text).joined() == original && model.rows.count == 4, "Split preserves every original word")
        let broll = model.rows[1]
        expect(model.rollType(for: broll.id) == .bRoll && model.brollProductionMethod(for: broll.id) == .undecided, "System defaults are undecided")
        expect(!model.physicalShootingRows.contains(where: { $0.id == broll.id }), "Undecided is not a physical task")
        expect(model.shootingDevice(for: model.rows[0].id)?.id == "dji" && model.shootingDevice(for: model.rows[2].id)?.id == "dji", "Uninvolved fragments inherit devices")
        expect(model.note(for: model.rows[0].id) == "原来的备注", "Splitting preserves notes")
        rejects("stale candidate") { try model.applyContentGapCandidate(candidate) }
        model.undo()
        expect(model.rows.count == 2 && model.rows[0].id == first.id && model.rollType(for: first.id) == .aRoll, "One undo restores split and tags")
        model.redo()
        expect(model.rows.count == 4 && model.brollProductionMethod(for: model.rows[1].id) == .undecided, "Redo restores complete operation")
        event(model) { model.setBrollProductionMethod(.liveAction, for: broll.id) }
        expect(model.physicalShootingRows.contains(where: { $0.id == broll.id }), "Explicit live action enters physical list")
        event(model) { model.togglePhysicalTask(broll) }
        expect(model.isPhysicalTaskCompleted(broll), "B-roll completion needs no bound file")
        model.undo()
        expect(!model.isPhysicalTaskCompleted(broll), "B-roll completion can undo")
        let aux = model.rows[0]
        event(model) { model.togglePhysicalTask(aux) }
        expect(model.isPhysicalTaskCompleted(aux), "Auxiliary completion needs no file or notes")
        model.undo()
        expect(!model.isPhysicalTaskCompleted(aux), "Auxiliary completion is undoable")
        let prior = model.preflight
        event(model) { model.updatePreflightDevices(main: "sony", auxiliary: "sony") }
        expect(model.preflight == prior, "Main and auxiliary cannot coincide")
        event(model) { model.updatePreflightDevices(main: "dji", auxiliary: "sony") }
        expect(model.preflight.mainDeviceID == "dji" && model.preflight.auxiliaryDeviceID == "sony", "Role swaps apply atomically")
        model.undo()
        expect(model.preflight == prior, "Role swaps undo as one operation")
        let snapshot = model.preflightSnapshot
        expect(model.updateShootingDevices([.init(id: "sony", name: "索尼改名"), .init(id: "dji", name: "大疆")]), "Rename succeeds")
        expect(snapshot == model.preflightSnapshot, "Renaming doesn't invalidate timing or conclusions")
        let current = model.rows[0]
        let invalid = ContentGapCandidate(sourceRowIDs: [current.id], text: "不存在", reason: "r", visualHint: "v")
        rejects("rewritten quote") { try model.stageContentGapCandidates([invalid]) }
        rejects("invalid ID") { try model.stageContentGapCandidates([.init(sourceRowIDs: ["invalid"], text: current.text, reason: "r", visualHint: "v")]) }
        let valid = ContentGapCandidate(sourceRowIDs: [current.id], text: current.text, reason: "r", visualHint: "v")
        rejects("overlap") { try model.stageContentGapCandidates([valid, valid]) }
        try model.stageContentGapCandidates([valid])
        event(model) { model.retainPreflightIssue(valid.id) }
        expect(model.contentGapCandidates.isEmpty, "Retain suppresses same candidate")
        model.undo()
        expect(model.contentGapCandidates.count == 1, "Undo restores retained candidate")
        event(model) { model.setShootingDevice(model.shootingDevices[0], for: current.id) }
        rejects("arrangement changed") { try model.applyContentGapCandidate(valid) }
        let state = try JSONDecoder().decode(ShootingPreflightState.self, from: JSONEncoder().encode(model.preflight))
        expect(state == model.preflight, "All preflight state roundtrips")
        let legacy = try JSONDecoder().decode(BrollProjectSettings.self, from: Data("{}".utf8))
        expect(legacy.preflight.mainDeviceID == "sony", "Legacy projects get safe defaults")
        let project = FileManager.default.temporaryDirectory.appendingPathComponent("preflight-project-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: project) }
        model.clearDestinationDirectory()
        model.acceptDestinationDirectoryDrop(project)
        model.scriptText = "开始操作。\n展示结果。"
        model.confirmScript()
        try FileManager.default.createDirectory(at: project.appendingPathComponent("A-roll"), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: project.appendingPathComponent("A-roll/A-roll.mov"))
        try event(model) { try model.setSpokenSegments(segments) }
        expect(model.spokenTimings.count == 2, "Model uses saved source timings")
        event(model) { model.updatePreflightRhythm(sameEnabled: true, sameSeconds: 5, continuousEnabled: true, continuousSeconds: 5) }
        let actualIssues = model.rhythmIssues
        expect(actualIssues.count == 1 && actualIssues[0].seconds == 8, "Model uses actual durations for reminders")
        event(model) { model.retainPreflightIssue(actualIssues[0].id) }
        expect(model.rhythmIssues.isEmpty, "Rhythm retain persists")
        model.undo()
        expect(model.rhythmIssues.count == 1, "Undo restores rhythm issue")
        try model.stageContentGapCandidates([])
        model.startContentGapCheck()
        expect(model.preflightStatus == "有待确认项", "Complete check still requires rhythm conclusions")
        event(model) { model.retainPreflightIssue(model.rhythmIssues[0].id) }
        expect(model.preflightStatus == "检查完成", "Check complete only after all issues concluded")
        let saved = try JSONDecoder().decode(BrollProjectSettings.self, from: Data(contentsOf: project.appendingPathComponent("B-roll/project-settings.json")))
        expect(saved.preflight == model.preflight, "Project saves timings, roles and conclusions")
        model.clearDestinationDirectory()
        model.acceptDestinationDirectoryDrop(project)
        expect(model.spokenTimings.count == 2 && model.preflightStatus == "检查完成", "Reopen restores source timing and check status")
        event(model) { model.setShootingDevice(model.shootingDevices[1], for: model.rows[1].id) }
        let auxiliaryRow = model.rows[1]
        let auxPath = "A-roll/auxiliary.mov"
        try Data("auxiliary fixture".utf8).write(to: project.appendingPathComponent(auxPath))
        event(model) { model.recordAuxiliarySpokenClip(.init(relativePath: auxPath, duration: 6, text: auxiliaryRow.text), for: auxiliaryRow.id) }
        expect(model.preflightDuration(auxiliaryRow) == 6 && !model.spokenTimingLabel(auxiliaryRow).contains("待定"), "Actual auxiliary recording replaces the planning duration")
        expect(model.isPhysicalTaskCompleted(auxiliaryRow), "Imported auxiliary clip is prepared without an extra task")
        expect(model.rhythmIssues.first?.seconds == 10 && model.spokenTimings[auxiliaryRow.id]?.duration == 4, "Auxiliary rerecord changes rhythm while main reference playback retains original time")
        model.undo()
        expect(model.preflightDuration(auxiliaryRow) == 4 && !model.isPhysicalTaskCompleted(auxiliaryRow), "One undo restores auxiliary duration and completion")
        try Data("replaced fixture".utf8).write(to: project.appendingPathComponent("A-roll/A-roll.mov"))
        expect(model.spokenTimings.isEmpty && model.preflightStatus == "待检查", "External source replacement invalidates old actual timing")
        print("PASS shooting preflight: exact timing, rhythm, safe AI quotes, split/undo, preservation, physical tasks, status and persistence")
    }
}
