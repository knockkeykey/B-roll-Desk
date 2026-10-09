import AppKit
import Foundation
import Observation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
@MainActor private func event(_ model: AppModel, _ action: () -> Void) {
    model.undoManager.beginUndoGrouping()
    defer { model.undoManager.endUndoGrouping() }
    action()
}

@main struct InlineOptimizationTests {
    @MainActor static func main() async throws {
        let suite = "InlineOptimization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = root.appendingPathComponent("assignments.json")
        let project = root.appendingPathComponent("project")
        let model = AppModel(defaults: defaults, assignmentsURL: cache)
        await Task.yield()
        defer {
            model.flushPendingInlineSaves()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        model.undoManager.groupsByEvent = false
        model.acceptDestinationDirectoryDrop(project)
        model.scriptText = "相同文案\n相同文案\n保留🙂完整中文与英文ABC。\n最后一行"
        model.confirmScript()
        let original = model.scriptText
        let initialDisplayIDs = model.displayedScriptRows(model.rows).map(\.id)
        let firstID = model.rows[0].id
        let duplicateID = model.rows[1].id
        let image = root.appendingPathComponent("fixture.png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=")!.write(to: image)
        model.undoManager.beginUndoGrouping()
        await model.attach(urls: [image], to: duplicateID)
        model.undoManager.endUndoGrouping()
        let assetID = model.assets(for: duplicateID)[0].id
        _ = model.scriptListAnalysis
        expect(model.scriptListAnalysis.boundRowIDs.contains(duplicateID), "Binding invalidates the cached list")
        event(model) { model.setBrollProductionMethod(.screenRecording, for: duplicateID) }
        expect(model.scriptListAnalysis.attributes[1].brollMethod == .screenRecording, "Method changes invalidate cached filter attributes")
        event(model) { model.toggleRollType(for: duplicateID) }
        _ = model.scriptListAnalysis
        event(model) { model.setShootingDevice(nil, for: duplicateID) }
        expect(model.scriptListAnalysis.attributes[1].shootingDeviceID == nil, "Explicit unset device differs from the default")
        event(model) { model.setNote("重复行自己的备注", for: duplicateID) }
        _ = model.scriptDistribution
        _ = model.scriptListAnalysis
        var sawConsistentCommit = false
        withObservationTracking {
            _ = model.scriptListAnalysis
            _ = model.scriptDistribution
        } onChange: {
            MainActor.assumeIsolated {
                let row = model.rows[2]
                sawConsistentCommit = model.rows.count == 5 && model.assets(for: row.id).first?.id == assetID
                    && model.assets(for: row.id).first?.anchorIndex == row.index
                    && model.note(for: row.id) == "重复行自己的备注"
            }
        }
        event(model) { model.splitInlineRow(at: 0, text: model.rows[0].text, selection: NSRange(location: 2, length: 0)) }
        let splitDisplays = model.displayedScriptRows(model.rows)
        expect(splitDisplays[1].id == initialDisplayIDs[0] && splitDisplays[2].id == initialDisplayIDs[1],
               "The active editor and untouched duplicate retain their display identities")
        expect(sawConsistentCommit, "Derived observers see one complete edit, never rows before migrated bindings")
        expect(model.assets(for: model.rows[2].id).first?.id == assetID, "A later duplicate retains its own asset")
        expect(model.shootingDevice(for: model.rows[2].id) == nil, "Duplicate migration preserves explicit unset")
        expect(model.scriptListAnalysis.attributes == model.rows.map(model.filterAttributes(for:)), "Derived attributes reflect every migrated row")
        model.undo()
        expect(model.scriptText == original && model.rows[0].id == firstID, "Undo retains the original identity rules")
        expect(model.assets(for: duplicateID).first?.id == assetID, "Undo restores the duplicate binding")
        model.redo()
        event(model) { _ = model.mergeInlineRowWithPrevious(at: 1, text: model.rows[1].text) }
        model.flushPendingInlineSaves()
        expect(model.scriptText == original, "Split and merge preserve Unicode text exactly")
        let scriptURL = project.appendingPathComponent("A-roll/正确文案.txt")
        let flushedScript = try String(contentsOf: scriptURL, encoding: .utf8)
        expect(flushedScript == original, "Flush completes the latest script snapshot")
        let settingsURL = project.appendingPathComponent("B-roll/project-settings.json")
        let saved = try JSONDecoder().decode(BrollProjectSettings.self, from: Data(contentsOf: settingsURL))
        expect(saved.arollShootingDevices.keys.contains(duplicateID) && saved.arollShootingDevices[duplicateID]! == nil,
               "Background settings preserve a present nil device")
        let paths = ["B-roll/broll-manifest.json", "B-roll/broll-for-ai.json", "A-roll/aroll-for-codex.json"]
        let background = try paths.map { try Data(contentsOf: project.appendingPathComponent($0)) }
        _ = model.saveManifest(showMessage: false)
        let synchronous = try paths.map { try Data(contentsOf: project.appendingPathComponent($0)) }
        expect(background == synchronous, "Background manifests match existing synchronous export byte for byte")

        // Let one snapshot enter the writer, then supersede it. Its completion cannot win.
        event(model) { model.replaceInlineRow(at: 3, with: "旧快照") }
        try await Task.sleep(for: .milliseconds(140))
        event(model) { model.replaceInlineRow(at: 3, with: "最终快照🙂") }
        model.flushPendingInlineSaves()
        let latest = try String(contentsOf: scriptURL, encoding: .utf8)
        expect(latest == model.scriptText && latest.hasSuffix("最终快照🙂"), "Queued encoding and writes preserve the latest edit")

        // A real file write failure remains visible rather than reporting a successful save.
        let blocked = project.appendingPathComponent("B-roll/broll-for-ai.json")
        try FileManager.default.removeItem(at: blocked)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
        event(model) { model.replaceInlineRow(at: 3, with: "保存失败也保留草稿") }
        model.flushPendingInlineSaves()
        try await Task.sleep(for: .milliseconds(30))
        expect(model.alert != nil && model.scriptText.hasSuffix("保存失败也保留草稿"), "Writer errors surface and keep the current text")
        print("PASS inline optimization: coherent cache invalidation, duplicates, explicit unset, Unicode, byte-identical manifests, queued saves and write failures")
    }
}
