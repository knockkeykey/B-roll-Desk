import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@MainActor private func event(_ model: AppModel, _ action: () -> Void) {
    model.undoManager.beginUndoGrouping()
    defer { model.undoManager.endUndoGrouping() }
    action()
}

@main
struct ShootingDeviceTests {
    @MainActor static func main() throws {
        let legacy = try JSONDecoder().decode(BrollProjectSettings.self, from: Data("{}".utf8))
        expect(legacy.arollShootingDevices.isEmpty, "Old projects start with no selected shooting devices")
        let suite = "com.keyknock.BrollDesk.ShootingDeviceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let assignmentCacheURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(suite).appendingPathComponent("assignments.json")
        defer { try? FileManager.default.removeItem(at: assignmentCacheURL.deletingLastPathComponent()) }
        let otherDefaults = UserDefaults(suiteName: suite + ".other")!
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            otherDefaults.removePersistentDomain(forName: suite + ".other")
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set("第一条文案\n重复文案\n重复文案", forKey: "broll-namer-script")
        let model = AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL)
        defer { model.flushPendingInlineSaves() }
        model.undoManager.groupsByEvent = false
        let firstID = model.rows[0].id
        let duplicateID = model.rows[2].id
        let sony = model.shootingDevices[0]
        let dji = model.shootingDevices[1]
        expect(model.shootingDevices.map(\.name) == ["索尼", "大疆"], "Default options are Sony and DJI")
        expect(model.shootingDevice(for: firstID) == sony, "Rows default to Sony")
        event(model) { model.setShootingDevice(dji, for: firstID) }
        model.undo()
        expect(model.shootingDevice(for: firstID) == sony, "Undo restores the Sony default")
        model.redo()
        expect(AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).shootingDevice(for: firstID) == dji, "A manual selection survives model recreation")
        event(model) { model.setShootingDevice(nil, for: firstID) }
        expect(AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).shootingDevice(for: firstID) == nil, "Clearing the device persists")
        model.undo()
        event(model) { model.setShootingDevice(sony, for: firstID) }

        let renamedSony = ShootingDevice(id: sony.id, name: "索尼 A7")
        let custom = ShootingDevice(name: "手机")
        expect(model.updateShootingDevices([renamedSony, dji, custom]), "Devices can be renamed and added")
        expect(model.shootingDevice(for: firstID) == renamedSony, "Rename follows selected devices by stable identity")
        expect(AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).shootingDevices == [renamedSony, dji, custom], "Custom options persist")
        let savedOptions = model.shootingDevices
        expect(!model.updateShootingDevices([ShootingDevice(name: " ")]), "Blank names are rejected")
        expect(!model.updateShootingDevices([ShootingDevice(name: "手机"), ShootingDevice(name: " 手机 ")]),
               "Duplicate names are rejected after trimming")
        expect(model.shootingDevices == savedOptions, "Invalid edits preserve the saved options")
        expect(model.updateShootingDevices([dji, custom]), "An option can be removed")
        expect(model.shootingDevice(for: firstID) == renamedSony, "Removing an option preserves existing project metadata")
        expect(model.updateShootingDevices(savedOptions), "Removed options can be added back")
        expect(model.updateShootingDevices(savedOptions, roles: .defaults), "Restore the original main and auxiliary roles for row-metadata checks")

        event(model) { model.toggleRollType(for: firstID) }
        event(model) { model.setShootingDevice(dji, for: firstID) }
        event(model) { model.toggleRollType(for: firstID) }
        expect(model.shootingDevice(for: firstID) == renamedSony, "Switching to B-roll hides and preserves the A-roll choice")
        event(model) { model.replaceInlineRow(at: 0, with: "修改第一条文案") }
        expect(model.shootingDevice(for: model.rows[0].id) == renamedSony, "Inline edits retain device selection")
        model.undo()
        event(model) { model.setShootingDevice(dji, for: duplicateID) }
        event(model) { model.deleteInlineRow(at: 1) }
        expect(model.shootingDevice(for: model.rows[1].id) == dji, "Deleting another duplicate preserves the selected original row")
        model.undo()
        expect(model.shootingDevice(for: duplicateID) == dji && model.shootingDevice(for: model.rows[1].id) == renamedSony,
               "Undo restores distinct metadata on duplicate rows")
        event(model) { model.splitInlineRow(at: 0, text: model.rows[0].text, selection: NSRange(location: 3, length: 0)) }
        expect(model.shootingDevice(for: model.rows[0].id) == renamedSony, "Split retains the original row's device")
        event(model) { _ = model.mergeInlineRowWithPrevious(at: 1, text: model.rows[1].text) }
        expect(model.shootingDevice(for: model.rows[0].id) == renamedSony, "Merge retains the original row's device")

        let project = root.appendingPathComponent("project", isDirectory: true)
        model.clearDestinationDirectory()
        model.acceptDestinationDirectoryDrop(project)
        model.scriptText = "项目第一条\n项目第二条"
        model.confirmScript()
        let projectID = model.rows[0].id
        event(model) { model.setShootingDevice(custom, for: projectID) }
        event(model) { model.setShootingDevice(nil, for: model.rows[1].id) }
        event(model) { model.replaceInlineRow(at: 1, with: "项目第二条修改") }
        let clearedRowID = model.rows[1].id
        expect(model.shootingDevice(for: clearedRowID) == nil, "An explicit none selection survives inline edits")
        let settingsURL = project.appendingPathComponent("B-roll/project-settings.json")
        let saved = try JSONDecoder().decode(BrollProjectSettings.self, from: Data(contentsOf: settingsURL))
        expect(saved.arollShootingDevices[projectID] == .some(custom), "Project stores device identity and name")
        model.clearDestinationDirectory()
        expect(model.arollShootingDevices.isEmpty && model.shootingDevices == savedOptions,
               "Clearing a project clears row selections and retains global device options")
        model.acceptDestinationDirectoryDrop(project)
        expect(model.shootingDevice(for: projectID) == custom, "Reopening restores project selections")
        expect(model.shootingDevice(for: clearedRowID) == nil, "Explicit none survives project reopen instead of reverting to Sony")

        let otherModel = AppModel(defaults: otherDefaults, assignmentsURL: assignmentCacheURL.deletingLastPathComponent().appendingPathComponent("other-assignments.json"))
        otherModel.acceptDestinationDirectoryDrop(project)
        expect(otherModel.shootingDevice(for: projectID) == custom,
               "A project remains readable when the current app does not have its custom device option")
        expect(otherModel.shootingDevice(for: clearedRowID) == nil, "Explicit none also survives opening in another app profile")
        otherModel.clearDestinationDirectory()
        model.clearDestinationDirectory()
        model.acceptDestinationDirectoryDrop(root.appendingPathComponent("other-project", isDirectory: true))
        model.scriptText = "项目第一条\n项目第二条"
        model.confirmScript()
        expect(model.shootingDevice(for: projectID) == model.mainShootingDevice, "Another project uses the global main device instead of inheriting the earlier row selection")
        expect(model.updateShootingDevices([]) && AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).shootingDevices.isEmpty,
               "An intentionally empty device list survives recreation")
        model.clearDestinationDirectory()
        print("PASS shooting devices: defaults, settings validation, custom options, rename/removal, persistence, undo/redo, inline edits, project restore and isolation")
    }
}
