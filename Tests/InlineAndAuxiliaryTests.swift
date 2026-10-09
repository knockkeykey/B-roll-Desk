import AppKit
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@MainActor private func event(_ model: AppModel, _ action: () -> Void) {
    model.undoManager.beginUndoGrouping()
    defer { model.undoManager.endUndoGrouping() }
    action()
}

@MainActor private func attach(_ model: AppModel, _ url: URL, _ rowID: String) async {
    model.undoManager.beginUndoGrouping()
    defer { model.undoManager.endUndoGrouping() }
    await model.attach(urls: [url], to: rowID)
}

@main struct InlineAndAuxiliaryTests {
    @MainActor static func main() async throws {
        let suite = "BrollInlineAuxiliaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache/assignments.json")
        let model = AppModel(defaults: defaults, assignmentsURL: cache)
        defer { model.flushPendingInlineSaves() }
        model.undoManager.groupsByEvent = false
        let project = root.appendingPathComponent("project", isDirectory: true)
        model.acceptDestinationDirectoryDrop(project)
        let originalText = "当我们安装无线麦后，电脑会出现一个入口。输入后识别成文字。\n下一条的原文完全不同。"
        model.scriptText = originalText
        model.confirmScript()
        let firstID = model.rows[0].id
        let nextID = model.rows[1].id
        let sony = model.shootingDevices[0], dji = model.shootingDevices[1]
        expect(model.mainShootingDevice == sony && model.auxiliaryShootingDevice == dji, "Default global roles")
        expect(!model.updateShootingDevices(model.shootingDevices,
                 roles: ShootingDeviceRoles(mainDeviceID: sony.id, auxiliaryDeviceID: sony.id)), "Roles must differ")
        let swapped = ShootingDeviceRoles(mainDeviceID: dji.id, auxiliaryDeviceID: sony.id)
        expect(model.updateShootingDevices(model.shootingDevices, roles: swapped), "Global roles can be changed")
        expect(model.shootingDevice(for: firstID) == dji, "Unset rows follow the global main device")
        expect(AppModel(defaults: defaults, assignmentsURL: cache).shootingDeviceRoles == swapped, "Roles survive relaunch")
        expect(model.updateShootingDevices(model.shootingDevices, roles: .defaults), "Restore Sony main, DJI auxiliary")

        let originalVideo = root.appendingPathComponent("selfie.mov")
        let brollVideo = root.appendingPathComponent("broll.mp4")
        let primaryVideo = root.appendingPathComponent("primary.mov")
        let selfieBytes = Data("original selfie video and audio".utf8)
        try selfieBytes.write(to: originalVideo)
        try Data("original B-roll video and audio".utf8).write(to: brollVideo)
        try Data("original primary video and audio".utf8).write(to: primaryVideo)
        await model.importARollVideo(from: [primaryVideo])
        await attach(model, brollVideo, nextID)
        let nextAsset = model.assets(for: nextID)[0]
        event(model) { model.setShootingDevice(dji, for: firstID) }
        event(model) { model.toggleRollType(for: firstID) }
        event(model) { model.setNote("保留这个备注", for: firstID) }
        event(model) { model.setBrollProductionMethod(.screenRecording, for: firstID) }
        let splitPoint = 17
        event(model) { model.splitInlineRow(at: 0, text: model.rows[0].text, selection: NSRange(location: splitPoint, length: 0)) }
        expect(model.rows.count == 3, "Enter adds exactly one row")
        let session = UUID()
        let staleEditor = InlineEditTarget(rowID: model.rows[1].id, session: session, resetID: model.inlineEditingResetID)
        let staleDraft = model.rows[1].text
        model.undo()
        expect(!staleEditor.canCommit(session: session, resetID: model.inlineEditingResetID, at: 1, in: model.rows),
               "Undo invalidates a surviving editor before any delayed end-edit callback")
        if staleEditor.canCommit(session: session, resetID: model.inlineEditingResetID, at: 1, in: model.rows) {
            model.replaceInlineRow(at: 1, with: staleDraft)
        }
        expect(model.scriptText == originalText && model.rows.count == 2, "Undo restores the original script without residual rows")
        expect(model.rows[1].id == nextID && model.assets(for: nextID) == [nextAsset], "Next row text and binding remain intact")
        expect(model.note(for: firstID) == "保留这个备注" && model.brollProductionMethod(for: firstID) == .screenRecording,
               "Undo restores row metadata")
        model.redo()
        expect(model.rows.count == 3 && model.rows[2].id == nextID, "Redo restores only the split")
        event(model) { _ = model.mergeInlineRowWithPrevious(at: 1, text: model.rows[1].text) }
        expect(model.scriptText == originalText && model.rows.count == 2, "Backspace merges without changing the next row")
        model.undo()
        expect(model.rows.count == 3, "Merged rows can be restored")
        model.redo()
        model.flushPendingInlineSaves()
        expect((try? String(contentsOf: project.appendingPathComponent("A-roll/正确文案.txt"), encoding: .utf8)) == originalText,
               "Queued saves cannot overwrite the final undo/redo result")

        event(model) { model.toggleRollType(for: firstID) }
        expect(model.supportsPreparationStatus(for: firstID), "Auxiliary A-roll offers preparation states")
        expect(model.brollPreparationStatus(for: firstID) == .pending, "Auxiliary A-roll starts pending")
        event(model) { model.setBrollPreparationStatus(.ready, for: firstID) }
        expect(model.brollPreparationStatus(for: firstID) == .ready, "Auxiliary A-roll can be marked ready")
        model.undo()
        expect(model.brollPreparationStatus(for: firstID) == .pending, "Auxiliary readiness supports undo")
        model.redo()
        expect(model.brollPreparationStatus(for: firstID) == .ready, "Auxiliary readiness supports redo")
        let readyRestored = AppModel(defaults: defaults, assignmentsURL: cache)
        expect(readyRestored.brollPreparationStatus(for: firstID) == .ready, "Auxiliary readiness survives relaunch")
        var auxiliaryFilter = ScriptRowFilter()
        auxiliaryFilter.showsBroll = false
        auxiliaryFilter.shootingDevices[dji.id] = .include
        let predicted = model.filterAttributesAfterBinding(for: model.rows[0])
        expect(auxiliaryFilter.matches(predicted), "A-roll plus auxiliary-device filter must not schedule a binding exit")
        auxiliaryFilter.showsBroll = true
        expect(auxiliaryFilter.matches(predicted), "Auxiliary-device-only filter retains a bound auxiliary row")
        var pendingFilter = ScriptRowFilter()
        pendingFilter.showsAroll = false
        pendingFilter.preparationStatuses[.pending] = .include
        expect(!pendingFilter.matches(model.filterAttributesAfterBinding(for: model.rows[1])),
               "Pending B-roll still exits after binding")
        await attach(model, originalVideo, firstID)
        expect(model.filterAttributes(for: model.rows[0]) == predicted, "Predicted binding attributes equal the actual result")
        expect(model.brollPreparationStatus(for: firstID) == .bound, "A bound auxiliary row shows the binding state")
        event(model) { model.setBrollPreparationStatus(.pending, for: firstID) }
        expect(model.brollPreparationStatus(for: firstID) == .bound, "Bound auxiliary status cannot be manually cleared")
        let auxiliary = model.assets(for: firstID)[0]
        let sourceDescription = SourceFile(url: originalVideo, byteCount: Int64(selfieBytes.count), kind: .video,
                                           modificationDate: nil, sourceDirectoryID: "direct-drop",
                                           sourceDirectoryName: "test", relativePath: originalVideo.lastPathComponent)
        let auxiliaryURL = project.appendingPathComponent(auxiliary.archiveRelativePath)
        expect(model.isAuxiliaryARoll(for: firstID) && auxiliary.archiveDirectory == .aRoll,
               "Binding auxiliary footage retains A-roll and archives in A-roll")
        expect(auxiliary.audio == "preserve" && FileManager.default.fileExists(atPath: auxiliaryURL.path), "Auxiliary audio and file are preserved")
        expect(model.aRollVideoDisplayName == "A-roll.mov", "Auxiliary footage is not mistaken for the main upload")
        let auxManifest = try JSONDecoder().decode(CodexARollManifest.self,
            from: Data(contentsOf: project.appendingPathComponent("A-roll/aroll-for-codex.json")))
        let bManifest = try JSONDecoder().decode(CodexBrollManifest.self,
            from: Data(contentsOf: project.appendingPathComponent("B-roll/broll-for-codex.json")))
        expect(auxManifest.placements.count == 1 && auxManifest.placements[0].text == model.rows[0].text
               && auxManifest.placements[0].device == dji && auxManifest.placements[0].files == [auxiliary.outputName], "Auxiliary manifest binds exact text, device and files")
        expect(bManifest.placements.count == 1 && bManifest.defaultAudio == "preserve", "B-roll export excludes auxiliary rows and preserves audio")
        var legacyAssetJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(nextAsset)) as! [String: Any]
        legacyAssetJSON.removeValue(forKey: "archiveDirectory")
        legacyAssetJSON.removeValue(forKey: "sourceFilePath")
        legacyAssetJSON.removeValue(forKey: "sourceFileBookmark")
        legacyAssetJSON["audio"] = "mute"
        let legacyAsset = try JSONDecoder().decode(BrollAsset.self, from: JSONSerialization.data(withJSONObject: legacyAssetJSON))
        expect(legacyAsset.archiveDirectory == .bRoll && legacyAsset.audio == "preserve",
               "Legacy bindings default to B-roll and no longer instruct audio deletion")
        let legacyManifest = try JSONDecoder().decode(CodexBrollManifest.self, from: Data("{\"placements\":[]}".utf8))
        expect(legacyManifest.defaultAudio == "preserve", "Codex manifests without an audio field remain readable")
        let restored = AppModel(defaults: defaults, assignmentsURL: root.appendingPathComponent("restored-cache.json"))
        restored.acceptDestinationDirectoryDrop(project)
        expect(restored.assets(for: firstID) == [auxiliary] && restored.isAuxiliaryARoll(for: firstID), "Project reopening retains auxiliary identity and directory")
        restored.clearDestinationDirectory()

        // Moving a binding must be undoable even if the original source goes offline.
        event(model) { model.toggleRollType(for: firstID) }
        let moved = model.assets(for: firstID)[0]
        let movedURL = project.appendingPathComponent(moved.archiveRelativePath)
        expect(moved.archiveDirectory == .bRoll && moved.targetTrack == "V3"
               && !FileManager.default.fileExists(atPath: auxiliaryURL.path), "B-roll conversion moves the project copy and track hint")
        expect(model.assignedAssets(for: sourceDescription) == [moved], "The material list immediately reflects the moved archive")
        try FileManager.default.moveItem(at: originalVideo, to: root.appendingPathComponent("offline.mov"))
        model.undo()
        expect(FileManager.default.fileExists(atPath: auxiliaryURL.path) && !FileManager.default.fileExists(atPath: movedURL.path), "Undo moves the surviving copy back without needing its source")
        model.redo()
        expect(FileManager.default.fileExists(atPath: movedURL.path), "Redo reapplies the move")
        try FileManager.default.moveItem(at: root.appendingPathComponent("offline.mov"), to: originalVideo)
        event(model) { model.toggleRollType(for: firstID) }

        event(model) { model.setShootingDevice(sony, for: firstID) }
        expect(model.pendingShootingDeviceChange != nil && model.assets(for: firstID).count == 1, "Changing away from auxiliary requires confirmation")
        model.cancelShootingDeviceChange()
        expect(model.isAuxiliaryARoll(for: firstID) && FileManager.default.fileExists(atPath: auxiliaryURL.path), "Cancelling leaves device, binding and copy unchanged")
        event(model) { model.setShootingDevice(sony, for: firstID) }
        event(model) { model.confirmShootingDeviceChange() }
        expect(model.shootingDevice(for: firstID) == sony && model.assets(for: firstID).isEmpty
               && !FileManager.default.fileExists(atPath: auxiliaryURL.path), "Confirmation unbinds and deletes only the project copy")
        expect(!model.supportsPreparationStatus(for: firstID), "Main-device A-roll keeps its waveform indicator")
        expect(FileManager.default.fileExists(atPath: originalVideo.path), "Original footage remains untouched")
        model.undo()
        await model.waitForArchiveRestoration()
        expect(model.isAuxiliaryARoll(for: firstID) && model.assets(for: firstID) == [auxiliary], "A single undo restores the device and binding")
        expect((try? Data(contentsOf: auxiliaryURL)) == selfieBytes, "Undo restores the complete project copy from a direct file drop")
        model.redo()
        expect(model.assets(for: firstID).isEmpty && !FileManager.default.fileExists(atPath: auxiliaryURL.path), "Redo removes the auxiliary binding again")

        event(model) { model.setShootingDevice(dji, for: firstID) }
        await attach(model, originalVideo, firstID)
        let collisionURL = project.appendingPathComponent("B-roll/\(model.assets(for: firstID)[0].outputName)")
        let unrelatedBytes = Data("existing file must remain intact".utf8)
        try unrelatedBytes.write(to: collisionURL)
        event(model) { model.toggleRollType(for: firstID) }
        expect(model.assets(for: firstID)[0].outputName != collisionURL.lastPathComponent, "Moving to B-roll avoids existing names")
        expect(model.assignedAssets(for: sourceDescription) == model.assets(for: firstID),
               "Material-list archive names stay current after a collision rename")
        expect((try? Data(contentsOf: collisionURL)) == unrelatedBytes, "A collision never overwrites an existing file")
        model.undo()
        model.clearAssignments()
        for _ in 0..<500 {
            if !model.isBusy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        expect(!model.isBusy && model.assignments.isEmpty, "Clearing handles both archive directories")
        expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("A-roll/A-roll.mov").path)
               && FileManager.default.fileExists(atPath: originalVideo.path), "Clearing preserves the main upload and original footage")
        event(model) { model.replaceInlineRow(at: 0, with: "切换项目前必须保存的最新一句。") }
        let latestScript = model.scriptText
        let otherProject = root.appendingPathComponent("other-project", isDirectory: true)
        try FileManager.default.createDirectory(at: otherProject.appendingPathComponent("A-roll"), withIntermediateDirectories: true)
        let otherScriptURL = otherProject.appendingPathComponent("A-roll/正确文案.txt")
        try "另一个项目的文案。".write(to: otherScriptURL, atomically: true, encoding: .utf8)
        model.acceptDestinationDirectoryDrop(otherProject)
        model.flushPendingInlineSaves()
        expect((try? String(contentsOf: project.appendingPathComponent("A-roll/正确文案.txt"), encoding: .utf8)) == latestScript,
               "Switching projects drains the pending save into the old project")
        expect(model.scriptText == "另一个项目的文案。"
               && (try? String(contentsOf: otherScriptURL, encoding: .utf8)) == model.scriptText,
               "An old inline save cannot overwrite the newly selected project")
        model.clearDestinationDirectory()
        print("PASS inline/auxiliary: stale editor, split/merge undo/redo, exact persistence, global roles, auxiliary binding/export, reopen, safe moves, confirmation/cancel, restore from direct drop, collisions, cleanup and pending-save project switches")
    }
}
