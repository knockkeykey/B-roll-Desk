import Foundation
import AppKit

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

private func rejects(_ message: String, _ work: () throws -> Void) {
    do { try work(); fatalError("Expected rejection: " + message) }
    catch { print("PASS rejection: " + message) }
}

// Explicit groups model separate user events in this headless executable.
@MainActor private func event(_ model: AppModel, _ action: () throws -> Void) rethrows {
    model.undoManager.beginUndoGrouping()
    defer { model.undoManager.endUndoGrouping() }
    try action()
}

private final class MockDeepSeekProtocol: URLProtocol {
    static var status = 200
    static var body = ""
    static var lastBody: [String: Any]?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            Self.lastBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } else if let data = request.httpBody {
            Self.lastBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct AnimationWorkflowTests {
    @MainActor static func main() async throws {
        let savedClipboard = NSPasteboard.general.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            let items = savedClipboard.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(items)
        }
        expect(ScriptParser.split("", mode: .line, preservingEmptyLines: true).isEmpty, "An empty script must not create a phantom row")
        expect(ScriptParser.split("原文\n\n后文", mode: .line, preservingEmptyLines: true) == ["原文", "", "后文"], "Intentional blank anchors must remain intact")
        let rows = [AnchorRow(id: "a", index: 1, text: "前言。把分散的素材"), AnchorRow(id: "b", index: 2, text: "统一放进文件夹。结尾。")]
        let candidate = AnimationCandidate(sourceRowIDs: ["a", "b"], text: "把分散的素材统一放进文件夹。", reason: "汇聚关系")
        let pieces = try AnimationWorkflow.split(rows: rows, candidates: [candidate])
        expect(pieces.map(\.text) == ["前言。", candidate.text, "结尾。"], "Cross-row animation must become one task")
        expect(pieces.map(\.text).joined() == rows.map(\.text).joined(), "Original text must be preserved")
        rejects("overlap") { _ = try AnimationWorkflow.split(rows: rows, candidates: [candidate, candidate]) }
        rejects("rewritten source") {
            _ = try AnimationWorkflow.split(rows: rows, candidates: [AnimationCandidate(sourceRowIDs: ["a"], text: "改写的文案", reason: "理由")])
        }
        rejects("nonconsecutive row IDs") {
            _ = try AnimationWorkflow.split(rows: rows, candidates: [AnimationCandidate(sourceRowIDs: ["b", "a"], text: candidate.text, reason: "理由")])
        }
        rejects("ambiguous repeated phrase") {
            _ = try AnimationWorkflow.split(rows: [AnchorRow(id: "c", index: 1, text: "生成卡片。生成卡片。")], candidates: [AnimationCandidate(sourceRowIDs: ["c"], text: "生成卡片。", reason: "理由")])
        }
        rejects("recovery must not guess a repeated excerpt") {
            _ = try AnimationWorkflow.resolveCandidate(AnimationCandidate(sourceRowIDs: ["missing"], text: "生成卡片。", reason: "理由"),
                                                       rows: [AnchorRow(id: "c", index: 1, text: "生成卡片。生成卡片。")])
        }
        let blankRows = [rows[0], AnchorRow(id: "blank", index: 2, text: ""), rows[1]]
        let recoveredBlank = try AnimationWorkflow.resolveCandidate(candidate, rows: blankRows)
        expect(recoveredBlank.sourceRowIDs == ["a", "blank", "b"], "Unique cross-row excerpts recover omitted intermediate blank rows")
        let blankPieces = try AnimationWorkflow.split(rows: blankRows, candidates: [recoveredBlank])
        expect(blankPieces.map(\.text).joined() == rows.map(\.text).joined(), "Recovery must preserve every source character")
        let spaceRows = [AnchorRow(id: "s", index: 1, text: "Use cards then move them.")]
        let spaces = try AnimationWorkflow.split(rows: spaceRows, candidates: [AnimationCandidate(sourceRowIDs: ["s"], text: "cards", reason: "对象")])
        expect(ScriptParser.split(spaces.map(\.text).joined(separator: "\n"), mode: .line, preservingEmptyLines: true).joined() == spaceRows[0].text, "Spaces must survive the actual line parser")
        let filename = AnimationWorkflow.filename(for: String(repeating: "很长的文案🦀/", count: 50), reserved: [])
        expect(filename.utf8.count <= 255 && !filename.contains("/"), "Filename must be filesystem-safe")
        expect(AnimationWorkflow.filename(for: "句子。", reserved: ["句子。.mp4"]) == "句子。_2.mp4", "Repeated text filenames must be distinct")
        let task = AnimationTask(id: "t", rowID: "a", text: "素材汇聚。", reason: "汇聚", outputFilename: "素材汇聚。.mp4")
        let legacyTaskData = Data("{\"id\":\"t\",\"rowID\":\"a\",\"text\":\"素材汇聚。\",\"reason\":\"汇聚\",\"visualIdea\":\"旧画面创意\",\"outputFilename\":\"素材汇聚。.mp4\"}".utf8)
        let legacyTask = try JSONDecoder().decode(AnimationTask.self, from: legacyTaskData)
        expect(legacyTask == task, "Saved tasks with obsolete visual ideas remain readable")
        let encodedTask = String(decoding: try JSONEncoder().encode(legacyTask), as: UTF8.self)
        expect(!encodedTask.contains("visualIdea"), "Saved tasks no longer write visual ideas")
        let secondTask = AnimationTask(id: "second", rowID: "b", text: "按顺序连接节点。", reason: "流程", outputFilename: "按顺序连接节点。.mp4")
        let prompt = AnimationWorkflow.prompts(for: [task, secondTask], template: AnimationWorkflow.defaultTemplate, character: "/tmp/角色设定图.png")
        expect(prompt.contains(task.text) && prompt.contains("文案：" + task.text) && prompt.contains("PDoomVideo") && prompt.contains("角色设定图.png") && prompt.contains("不要 BGM") && !prompt.contains("{{text}}"), "Copied prompts must be actionable without extra instructions")
        expect(prompt.contains("制作以下 2 个独立动画视频") && prompt.contains("【动画 1】") && prompt.contains(secondTask.text) && prompt.contains("表达重点：" + secondTask.reason), "Batch prompts must retain each task and its output requirements")
        expect(prompt.components(separatedBy: "PDoomVideo").count == 2 && prompt.components(separatedBy: "不要 BGM").count == 2 && prompt.components(separatedBy: "/tmp/角色设定图.png").count == 2, "Shared style, audio and character requirements must appear only once")
        let customBatch = AnimationWorkflow.prompts(for: [task, secondTask], template: "白底动画：{{text}}，保持文字原样。", character: "/tmp/c.png")
        expect(customBatch.contains("白底动画：下方任务中的对应文案，保持文字原样。") && customBatch.contains("角色参考图：/tmp/c.png"), "Batch must retain custom template requirements")
        expect(!prompt.contains("画面思路：") && !prompt.contains("推荐理由：") && !prompt.contains("原文：") && !prompt.contains("文件名："), "Batch must use production language without per-task filenames or visual ideas")
        expect(prompt.contains("【统一制作要求】") && prompt.contains("视频文件名与对应文案一致"), "Naming belongs in shared requirements")
        let singlePrompt = AnimationWorkflow.prompt(for: task, template: AnimationWorkflow.defaultTemplate)
        expect(singlePrompt.contains("表达重点：汇聚") && !singlePrompt.contains("画面思路：") && singlePrompt.contains("视频文件的命名需要是文案。"), "Single copy retains template naming and expression focus")
        let noCharacter = AnimationWorkflow.prompt(for: task, template: AnimationWorkflow.defaultTemplate)
        expect(!noCharacter.contains("{{character}}") && noCharacter.contains("小螃蟹角色换成 你提供的角色参考图") && noCharacter.contains(task.text), "Unset character preserves the replacement instruction without an unresolved placeholder")
        let noCharacterBatch = AnimationWorkflow.prompts(for: [task, secondTask], template: AnimationWorkflow.defaultTemplate)
        expect(noCharacterBatch.components(separatedBy: "小螃蟹角色换成 你提供的角色参考图").count == 2, "Batch preserves the unset reference instruction once")
        expect(AnimationWorkflow.prompt(for: task, template: "角色：{{character}}；文案：{{text}}", character: " \n").contains(task.text), "Unset character must not remove text sharing the same template line")
        expect(!noCharacter.contains("【统一制作要求】") && !noCharacter.contains("所有成品放在同一个输出目录") && noCharacter.hasSuffix("表达重点：" + task.reason), "Single prompts omit the entire shared requirements block")
        expect(AnimationWorkflow.prompt(for: task, template: "做动画：{{text}}", character: "/tmp/c.png").contains("角色参考图：/tmp/c.png"), "Character appends without placeholder")
        expect(!singlePrompt.contains("目录") && !prompt.contains("目录"), "Single and batch prompts do not prescribe an output directory")
        var blankFocus = task
        blankFocus.reason = " \t\n"
        let blankPrompt = AnimationWorkflow.prompt(for: blankFocus, template: AnimationWorkflow.defaultTemplate)
        expect(!blankPrompt.contains("表达重点：") && blankPrompt.contains(task.text), "Whitespace focus is omitted while preserving the script")
        blankFocus.reason = ""
        expect(!AnimationWorkflow.prompt(for: blankFocus, template: AnimationWorkflow.defaultTemplate).contains("表达重点："), "Empty focus is omitted")
        let mixedBatch = AnimationWorkflow.prompts(for: [blankFocus, secondTask], template: AnimationWorkflow.defaultTemplate)
        expect(mixedBatch.components(separatedBy: "表达重点：").count == 2 && mixedBatch.contains("表达重点：" + secondTask.reason), "Batch omits only the empty task focus")
        print("PASS segmentation, source integrity, filenames, complete prompts and character handling")

        let suite = "BrollAnimationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let assignmentCacheURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(suite).appendingPathComponent("assignments.json")
        defer { try? FileManager.default.removeItem(at: assignmentCacheURL.deletingLastPathComponent()) }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project", isDirectory: true)
        let outputs = root.appendingPathComponent("outputs", isDirectory: true)
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
        defaults.set(AnimationWorkflow.legacyTemplate, forKey: "broll-namer-animation-template")
        let legacyRules = AnimationWorkflow.defaultRules
            .replacingOccurrences(of: "| 序号 | 适合动画的原文段落 | 推荐理由 |\n|---|---|---|", with: "| 序号 | 适合动画的原文段落 | 推荐理由 | 一句话画面思路 |\n|---|---|---|---|")
            .replacingOccurrences(of: "如果没有符合标准的段落", with: "画面思路要说明“什么对象发生什么变化”，不要只写“做一个生动的动画”，也不要用整段字幕出现代替动画。\n如果没有符合标准的段落")
        defaults.set(legacyRules, forKey: "broll-namer-animation-rules")
        defaults.set(true, forKey: "broll-namer-preserves-empty-anchors")
        // A directory saved by older versions must no longer affect copied prompts.
        defaults.set(outputs.path, forKey: "broll-namer-animation-output-directory")
        let model = AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL)
        defer { model.flushPendingInlineSaves() }
        expect(model.animationRules == AnimationWorkflow.defaultRules && defaults.string(forKey: "broll-namer-animation-rules") == AnimationWorkflow.defaultRules, "Saved default rules migrate and persist without creative output")
        expect(AnimationWorkflow.rulesWithoutVisualIdea("我的自定义判断规则") == "我的自定义判断规则", "Unrelated custom rules remain intact")
        expect(model.rows.isEmpty && model.animationScriptRowCount == 0, "No imported script must show zero analysis rows")
        defaults.set(" \t\n待分析\n已整理", forKey: "broll-namer-script")
        model.scriptText = " \t\n待分析\n已整理"
        model.parseScript(persist: false)
        event(model) { model.toggleRollType(for: model.rows[2].id) }
        expect(model.animationScriptRowCount == 2, "All nonblank rows participate, including manually classified rows")
        event(model) { model.toggleRollType(for: model.rows[2].id) }
        expect(model.rollType(for: model.rows[2].id) == .aRoll && model.animationScriptRowCount == 2, "Explicit A-roll labels still participate")
        model.deepSeekKeyDraft = ""
        model.startAnimationAnalysis()
        expect(model.animationFeedback == "请先填写 DeepSeek API Key。", "Existing classification must not block starting full-script analysis")
        model.undo()
        model.undo()
        model.scriptText = ""
        model.parseScript(persist: false)
        expect(model.animationTemplate == AnimationWorkflow.defaultTemplate && model.animationCharacterPath == AnimationWorkflow.legacyCharacterPath, "Legacy template migrates character path")
        expect(model.saveAnimationConfiguration(saveAPIKey: false), "Animation configuration saves without API key access")
        let characterURL = outputs.appendingPathComponent("角色参考图.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: characterURL)
        let droppedProvider = NSItemProvider(contentsOf: characterURL)!
        let droppedURLs = await FileURLDropLoader.urls(from: [droppedProvider])
        expect(model.setAnimationCharacterImage(droppedURLs.first), "Dropped image file payload resolves to a readable reference")
        expect(model.setAnimationCharacterImage(characterURL), "Inline selection accepts a readable image")
        expect(defaults.data(forKey: "broll-namer-animation-character-bookmark") != nil,
               "Reference selection must persist a security-scoped bookmark, not only the path")
        var characterBookmarkIsStale = false
        let characterBookmarkURL = try URL(resolvingBookmarkData: defaults.data(forKey: "broll-namer-animation-character-bookmark")!,
                                          options: [.withSecurityScope], relativeTo: nil,
                                          bookmarkDataIsStale: &characterBookmarkIsStale)
        let characterAccess = characterBookmarkURL.startAccessingSecurityScopedResource()
        let restoredCharacterData = try Data(contentsOf: characterBookmarkURL)
        expect(NSImage(data: restoredCharacterData) != nil,
               "Persisted reference bookmark must restore readable image bytes")
        if characterAccess { characterBookmarkURL.stopAccessingSecurityScopedResource() }
        expect(AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).animationCharacterPath == characterURL.path, "Reference image saves immediately without closing a settings sheet")
        expect(!model.setAnimationCharacterImage(outputs) && model.animationCharacterPath == characterURL.path, "Invalid drop must preserve the current reference")
        let previousBookmark = defaults.data(forKey: "broll-namer-animation-character-bookmark")
        expect(!model.setAnimationCharacterImage(outputs.appendingPathComponent("missing.png"))
               && defaults.data(forKey: "broll-namer-animation-character-bookmark") == previousBookmark,
               "Unreadable reference must preserve the previous bookmark")
        await Task.yield()
        model.undoManager.groupsByEvent = false
        await Task.yield()
        model.acceptDestinationDirectoryDrop(project)
        model.scriptText = "前言。把分散的素材\n统一放进文件夹。结尾。\n手工录屏。"
        model.confirmScript()
        let originalText = model.rows.map(\.text).joined()
        let manualRow = model.rows[2]
        event(model) { model.toggleRollType(for: manualRow.id) }
        event(model) { model.setBrollProductionMethod(.screenRecording, for: manualRow.id) }
        event(model) { model.setNote("保留这条备注", for: manualRow.id) }
        event(model) { model.setBrollPreparationStatus(.ready, for: manualRow.id) }
        event(model) { model.setBrollProductionMethod(.animation, for: manualRow.id) }
        let manualTask = model.animationTask(for: manualRow.id)!
        expect(model.animationTasks.isEmpty && model.activeAnimationTasks.count == 1,
               "Manually tagged animation rows are available without an AI task")
        expect(model.animationTask(for: manualRow.id)?.id == manualTask.id, "Manual task identity is stable")
        expect(model.copyAnimationPrompt(manualTask), "Manual animation prompt copies")
        let manualPrompt = NSPasteboard.general.string(forType: .string) ?? ""
        expect(manualPrompt.contains(manualRow.text) && manualPrompt.contains("保留这条备注"),
               "Manual prompt contains the current script and editable note")
        expect(manualPrompt.contains("小螃蟹角色换成 " + characterURL.path), "Row clipboard includes the saved character replacement")
        expect(model.copyAllAnimationPrompts() && (NSPasteboard.general.string(forType: .string) ?? "").contains(manualRow.text),
               "Bulk copy includes manual animation rows")
        expect((NSPasteboard.general.string(forType: .string) ?? "").contains("小螃蟹角色换成 " + characterURL.path), "Bulk clipboard includes the saved character replacement")
        model.removeAnimationCharacterImage()
        expect(defaults.data(forKey: "broll-namer-animation-character-bookmark") == nil,
               "Removing the reference must also remove its persistent file access")
        expect(AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).animationCharacterPath.isEmpty, "Removing the reference saves immediately")
        expect(model.copyAnimationPrompt(manualTask) && (NSPasteboard.general.string(forType: .string) ?? "").contains("小螃蟹角色换成 你提供的角色参考图"), "Row clipboard retains replacement instructions after removing the reference")
        event(model) { model.setBrollProductionMethod(.screenRecording, for: manualRow.id) }
        expect(model.animationTask(for: manualRow.id) == nil, "Other production methods have no animation prompt")
        model.undo()
        expect(model.animationTask(for: manualRow.id)?.id == manualTask.id, "Undo restores the manual prompt")
        model.undo()
        expect(model.activeAnimationTasks.isEmpty && model.brollProductionMethod(for: manualRow.id) == .screenRecording,
               "Undo tagging restores the original production method")
        let manualCandidate = AnimationCandidate(sourceRowIDs: [manualRow.id], text: manualRow.text, reason: "操作过程")
        try model.stageAnimationReview([manualCandidate])
        expect(model.animationTasks.isEmpty && model.brollProductionMethod(for: manualRow.id) == .screenRecording, "Analysis can recommend an organized row without changing its settings")
        event(model) { model.applyAnimationReview() }
        expect(model.activeAnimationTasks.count == 1 && model.brollProductionMethod(for: manualRow.id) == .animation && model.brollPreparationStatus(for: manualRow.id) == .pending, "Confirmed recommendation can change an organized row to an animation task")
        expect(model.note(for: manualRow.id) == "保留这条备注\n\n操作过程", "Recommendation must add its reason to the note while preserving manual content")
        model.undo()
        expect(model.animationTasks.isEmpty && model.brollProductionMethod(for: manualRow.id) == .screenRecording && model.brollPreparationStatus(for: manualRow.id) == .ready, "Undo restores preexisting settings and readiness")
        let crossManual = AnimationCandidate(sourceRowIDs: [model.rows[1].id, manualRow.id], text: "结尾。手工录屏。", reason: "流程")
        try model.stageAnimationReview([crossManual])
        expect(model.animationReviewItems.count == 1, "Recommendations can cross manually configured rows")
        model.discardAnimationReview()
        let selected = AnimationCandidate(sourceRowIDs: [model.rows[0].id, model.rows[1].id], text: candidate.text, reason: candidate.reason)
        let ending = AnimationCandidate(sourceRowIDs: [model.rows[1].id], text: "结尾。", reason: "r")
        let wrongIDs = AnimationCandidate(sourceRowIDs: ["不存在的编号"], text: selected.text, reason: selected.reason)
        let rewritten = AnimationCandidate(sourceRowIDs: [model.rows[1].id], text: "AI 改写的内容。", reason: "r")
        try model.stageAnimationReview([wrongIDs, rewritten, ending])
        expect(model.animationReviewItems.map(\.candidate) == [selected, ending], "Unique exact source recovers wrong IDs; invalid suggestions must not discard valid ones")
        expect(model.animationFeedback.contains("跳过 1 段") && model.rows.map(\.text).joined() == originalText, "Partial review explains skipped suggestions without changing the script")
        model.discardAnimationReview()
        try model.stageAnimationReview([selected, selected, ending])
        expect(model.animationReviewItems.count == 2 && model.animationFeedback.contains("跳过 1 段"), "Overlapping suggestions must not block independent ones")
        model.discardAnimationReview()
        try model.stageAnimationReview([rewritten])
        expect(model.animationReviewItems.isEmpty && model.animationFeedback.contains("重新分析"), "An entirely invalid response explains how to retry")
        try model.stageAnimationReview([selected, ending])
        expect(model.animationReviewItems.count == 2 && model.rows.map(\.text).joined() == originalText && model.animationTasks.isEmpty, "Review must not touch the script")
        model.animationReviewItems[1].isSelected = false
        event(model) { model.applyAnimationReview() }
        expect(model.animationReviewItems.isEmpty && model.activeAnimationTasks.count == 1 && model.activeAnimationTasks[0].text == selected.text, "Only checked candidates apply")
        expect(!model.isAnimationPanelPresented, "Applying review returns to the script list")
        expect(model.note(for: model.activeAnimationTasks[0].rowID) == selected.reason, "Animation reason becomes the editable production note")
        model.undo()
        expect(model.animationTasks.isEmpty && model.rows.count == 3, "Applied review undoes as one step")
        try model.stageAnimationReview([selected])
        event(model) { model.setNote("期间改了备注", for: model.rows[0].id) }
        event(model) { model.applyAnimationReview() }
        expect(model.animationTasks.isEmpty && model.animationReviewItems.isEmpty, "Stale review must be rejected")
        model.undo()
        try event(model) { try model.applyAnimationCandidates([selected]) }
        expect(model.rows.map(\.text).joined() == originalText && model.activeAnimationTasks.count == 1, "Model application should preserve text")
        expect(model.brollProductionMethod(for: manualRow.id) == .screenRecording && model.note(for: manualRow.id) == "保留这条备注", "Manual state must survive")
        expect(model.rollType(for: model.activeAnimationTasks[0].rowID) == .bRoll && model.brollProductionMethod(for: model.activeAnimationTasks[0].rowID) == .animation, "AI task must be marked animation")
        model.undo()
        expect(model.rows.count == 3 && model.animationTasks.isEmpty, "One undo must restore script and tasks together")
        model.redo()
        expect(model.activeAnimationTasks.count == 1 && model.rows.count == 4, "Redo must restore the exact split and task")
        let originalTask = model.activeAnimationTasks[0]
        expect(model.copyAnimationPrompt(originalTask), "Single prompt copies from the script row")
        expect(NSPasteboard.general.string(forType: .string)?.contains("表达重点：" + model.note(for: originalTask.rowID)) == true, "Clipboard uses the note's expression focus")
        expect(NSPasteboard.general.string(forType: .string)?.contains("【统一制作要求】") == false, "Single-row clipboard omits shared requirements")
        let singleClipboard = NSPasteboard.general.string(forType: .string) ?? ""
        expect(!singleClipboard.contains("目录") && !singleClipboard.contains(outputs.path), "Single clipboard ignores the legacy output directory")
        event(model) { model.setNote("", for: originalTask.rowID) }
        expect(model.copyAnimationPrompt(originalTask), "Prompt copies with cleared note")
        expect(NSPasteboard.general.string(forType: .string)?.contains("表达重点：") == false, "Cleared note omits focus instead of restoring AI reason")
        expect(model.copyAllAnimationPrompts(), "Batch copies with cleared note")
        expect(NSPasteboard.general.string(forType: .string)?.contains("表达重点：") == false, "Batch also omits cleared note focus")
        model.undo()
        event(model) { model.setNote("自定义表达重点", for: originalTask.rowID) }
        expect(model.copyAllAnimationPrompts(), "Batch prompt copies")
        expect(NSPasteboard.general.string(forType: .string)?.contains("表达重点：自定义表达重点") == true, "Edited note drives batch production prompts")
        let batchClipboard = NSPasteboard.general.string(forType: .string) ?? ""
        expect(!batchClipboard.contains("目录") && !batchClipboard.contains(outputs.path), "Batch clipboard ignores the legacy directory and omits shared directory requirements")
        model.undo()
        let settingsURL = project.appendingPathComponent("B-roll/project-settings.json")
        var settings = try JSONDecoder().decode(BrollProjectSettings.self, from: Data(contentsOf: settingsURL))
        expect(settings.animationTasks == model.animationTasks && settings.formatVersion == 4, "Project persists tasks")
        let legacyData = Data("{\"formatVersion\":3}".utf8)
        let legacySettings = try JSONDecoder().decode(BrollProjectSettings.self, from: legacyData)
        expect(legacySettings.animationTasks.isEmpty, "Legacy projects remain readable")
        settings.animationTasks[0].reasonAddedToNotes = nil
        settings.anchorNotes[originalTask.rowID] = "原有手写备注"
        model.clearDestinationDirectory()
        // Reopen a legacy fixture after current state has been persisted.
        try JSONEncoder().encode(settings).write(to: settingsURL)
        expect(model.animationTasks.isEmpty && model.rows.isEmpty, "Deselect clears project UI state")
        model.acceptDestinationDirectoryDrop(project)
        expect(model.activeAnimationTasks.first?.id == originalTask.id, "Reconnect restores stable task ID")
        expect(model.note(for: originalTask.rowID) == "原有手写备注\n\n" + originalTask.reason && model.activeAnimationTasks[0].reasonAddedToNotes == true, "Legacy task reasons migrate into notes alongside existing manual content")
        expect(model.animationScriptRowCount == model.rows.count, "Existing tasks do not exclude nonblank script rows from analysis")
        let repeated = AnimationCandidate(sourceRowIDs: [originalTask.rowID], text: originalTask.text, reason: "更新理由")
        try model.stageAnimationReview([repeated])
        event(model) { model.applyAnimationReview() }
        expect(model.animationTasks.count == 1 && model.activeAnimationTasks[0].id == originalTask.id && model.activeAnimationTasks[0].outputFilename == originalTask.outputFilename, "Reanalysis updates an existing task without duplicating it or changing its identity")
        expect(model.activeAnimationTasks[0].reason == "更新理由", "Reanalysis updates the existing recommendation")
        model.undo()
        expect(model.activeAnimationTasks[0] == originalTask, "Undo restores the previous animation recommendation")
        settings = try JSONDecoder().decode(BrollProjectSettings.self, from: Data(contentsOf: settingsURL))
        expect(settings.animationTasks.first?.id == originalTask.id, "Project retains animation task identity")
        event(model) { model.replaceInlineRow(at: 1, with: "已经修改的文案。") }
        expect(model.activeAnimationTasks.count == 1 && model.animationTasks.count == 1, "Edited animation rows still have a prompt without overwriting the saved AI task")
        expect(model.activeAnimationTasks[0].text == "已经修改的文案。" && model.activeAnimationTasks[0].id != originalTask.id,
               "Edited animation prompts use the current text and exclude the stale AI task")
        model.undo()
        expect(model.activeAnimationTasks.count == 1, "Undo edit restores task validity")
        event(model) { model.setNote("", for: originalTask.rowID) }
        model.clearDestinationDirectory()
        model.acceptDestinationDirectoryDrop(project)
        expect(model.note(for: originalTask.rowID).isEmpty, "Cleared production note stays empty after reopening")
        model.undoManager.removeAllActions()
        print("PASS actual model: full-script review, existing settings, repeated task update, undo/redo, project restore and edited task handling")

        model.clearDestinationDirectory()
        model.scriptText = "重复的流程。\n重复的流程。"
        model.parseScript()
        let duplicateID = model.rows[1].id
        try event(model) { try model.applyAnimationCandidates([AnimationCandidate(sourceRowIDs: [duplicateID], text: "重复的流程。", reason: "流程")]) }
        let duplicateTaskID = model.activeAnimationTasks[0].id
        event(model) { model.deleteInlineRow(at: 0) }
        expect(model.activeAnimationTasks.first?.id == duplicateTaskID && model.activeAnimationTasks.first?.rowID == model.rows[0].id, "Deleting another duplicate must migrate task to its original row")
        model.undo()
        expect(model.activeAnimationTasks.first?.rowID == duplicateID, "Duplicate identity migration must undo correctly")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDeepSeekProtocol.self]
        let client = DeepSeekClient(apiKey: "offline-test-key", session: URLSession(configuration: configuration))
        MockDeepSeekProtocol.body = "{\"data\":[{\"id\":\"deepseek-flash\"}]}"
        try await client.testConnection()
        MockDeepSeekProtocol.body = "{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":\"{\\\"candidates\\\":[]}\"}}]}"
        let noCandidates = try await client.analyze(rows: rows, rules: AnimationWorkflow.defaultRules)
        expect(noCandidates.isEmpty, "Empty classification must be valid")
        expect(MockDeepSeekProtocol.lastBody?["model"] as? String == "deepseek-flash", "Correct model must be sent")
        let messages = MockDeepSeekProtocol.lastBody?["messages"] as! [[String: String]]
        expect(!messages[0]["content"]!.contains("visual_idea") && !messages[0]["content"]!.contains("一句话画面思路") && messages[0]["content"]!.contains("不输出拍摄创意"), "DeepSeek only requests excerpts, reasons and source references")
        expect(messages[0]["content"]!.lowercased().contains("json") && messages[0]["content"]!.contains("所有有文字的条目都要参与判断") && !messages[1]["content"]!.contains("protected"), "Structured output must request full-script classification without protected rows")
        let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: [[String: String]]]
        expect(input["rows"]!.map { $0["row_id"]! } == ["1", "2"], "AI input uses short request-local references")
        let wireCandidate: [String: Any] = ["candidates": [["source_row_ids": ["1", "2"], "text": candidate.text, "reason": candidate.reason]]]
        let wireContent = String(decoding: try JSONSerialization.data(withJSONObject: wireCandidate), as: UTF8.self)
        MockDeepSeekProtocol.body = String(decoding: try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": wireContent]]]]), as: UTF8.self)
        let mapped = try await client.analyze(rows: rows, rules: "规则")
        expect(mapped == [candidate], "Network response references map back to persistent source row IDs")
        _ = try AnimationWorkflow.split(rows: rows, candidates: mapped)
        _ = try await client.analyze(rows: rows, rules: legacyRules)
        let migratedMessages = MockDeepSeekProtocol.lastBody?["messages"] as! [[String: String]]
        expect(!migratedMessages[0]["content"]!.contains("一句话画面思路") && !migratedMessages[0]["content"]!.contains("画面思路要说明"), "Legacy rules cannot reinstate creative output in requests")
        MockDeepSeekProtocol.body = "{\"choices\":[{\"finish_reason\":\"length\",\"message\":{\"content\":\"{}\"}}]}"
        do { _ = try await client.analyze(rows: rows, rules: "规则"); fatalError("Truncated response accepted") }
        catch { print("PASS truncated API response rejected") }
        MockDeepSeekProtocol.status = 401
        do { try await client.testConnection(); fatalError("Unauthorized response accepted") }
        catch { expect(!error.localizedDescription.contains("offline-test-key"), "Errors must not expose key") }
        print("PASS DeepSeek request, structured response, connection, truncation, HTTP failure (offline mock)")
        model.clearDestinationDirectory()
        print("ALL ANIMATION WORKFLOW TESTS PASSED")
    }
}
