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
struct ProductionMethodTests {
    @MainActor static func main() throws {
        let legacy = try JSONDecoder().decode(BrollProjectSettings.self, from: Data("{}".utf8))
        expect(legacy.arollProductionMethods.isEmpty, "Old project settings must open without A-roll metadata")

        let suite = "com.keyknock.BrollDesk.ProductionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let assignmentCacheURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(suite).appendingPathComponent("assignments.json")
        defer { try? FileManager.default.removeItem(at: assignmentCacheURL.deletingLastPathComponent()) }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }

        defaults.set("第一条文案\n重复文案\n重复文案", forKey: "broll-namer-script")
        let model = AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL)
        defer { model.flushPendingInlineSaves() }
        model.undoManager.groupsByEvent = false
        let firstID = model.rows[0].id
        let duplicateID = model.rows[2].id
        expect(model.arollProductionMethod(for: firstID) == .none, "Existing A-roll defaults to none")
        event(model) { model.setArollProductionMethod(.searchMaterial, for: firstID) }
        expect(model.arollProductionMethod(for: firstID) == .searchMaterial, "A-roll selection changes")
        model.undo()
        expect(model.arollProductionMethod(for: firstID) == .none, "Undo restores the default method")
        model.redo()
        expect(model.arollProductionMethod(for: firstID) == .searchMaterial, "Redo restores the selected method")
        expect(AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).arollProductionMethod(for: firstID) == .searchMaterial,
               "Selection survives model recreation")
        event(model) { model.setArollProductionMethod(.none, for: firstID) }
        expect(AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).arollProductionMethod(for: firstID) == .none,
               "Clearing a selection to none persists")
        model.undo()
        expect(model.arollProductionMethod(for: firstID) == .searchMaterial,
               "Clearing a selection can be undone")

        event(model) { model.toggleRollType(for: firstID) }
        event(model) { model.setBrollProductionMethod(.screenRecording, for: firstID) }
        event(model) { model.setArollProductionMethod(.text, for: firstID) }
        expect(model.arollProductionMethod(for: firstID) == .searchMaterial,
               "The hidden A-roll method cannot be changed while the row is B-roll")
        event(model) { model.toggleRollType(for: firstID) }
        expect(model.arollProductionMethod(for: firstID) == .searchMaterial
               && model.brollProductionMethod(for: firstID) == .screenRecording,
               "A-roll and B-roll choices survive type switches independently")

        event(model) { model.replaceInlineRow(at: 0, with: "修改后的第一条文案") }
        expect(model.arollProductionMethod(for: model.rows[0].id) == .searchMaterial,
               "Inline editing must retain the original row's choice after its ID changes")
        model.undo()
        event(model) { model.setArollProductionMethod(.searchMaterial, for: duplicateID) }
        event(model) { model.deleteInlineRow(at: 1) }
        expect(model.arollProductionMethod(for: model.rows[1].id) == .searchMaterial,
               "Deleting another identical row must not lose or transfer the surviving row's choice")
        model.undo()
        expect(model.arollProductionMethod(for: duplicateID) == .searchMaterial
               && model.arollProductionMethod(for: model.rows[1].id) == .none,
               "Undo restores separate choices for duplicate text")

        event(model) { model.splitInlineRow(at: 0, text: model.rows[0].text, selection: NSRange(location: 3, length: 0)) }
        expect(model.arollProductionMethod(for: model.rows[0].id) == .searchMaterial,
               "Splitting preserves the choice on the retained original row")
        event(model) { _ = model.mergeInlineRowWithPrevious(at: 1, text: model.rows[1].text) }
        expect(model.arollProductionMethod(for: model.rows[0].id) == .searchMaterial,
               "Merging retains the original row's choice")

        let project = root.appendingPathComponent("project", isDirectory: true)
        model.acceptDestinationDirectoryDrop(project)
        let importedScript = root.appendingPathComponent("文案.txt")
        try "项目第一条\n项目第二条".write(to: importedScript, atomically: true, encoding: .utf8)
        model.importScript(from: importedScript)
        model.confirmScript()
        let projectRowID = model.rows[0].id
        event(model) { model.setArollProductionMethod(.searchMaterial, for: projectRowID) }
        let settingsURL = project.appendingPathComponent("B-roll/project-settings.json")
        let saved = try JSONDecoder().decode(BrollProjectSettings.self, from: Data(contentsOf: settingsURL))
        expect(saved.arollProductionMethods[projectRowID] == .searchMaterial,
               "Project file must save the selected A-roll method")
        model.clearDestinationDirectory()
        expect(model.arollProductionMethods.isEmpty, "Clearing the project clears cached A-roll choices")
        model.acceptDestinationDirectoryDrop(project)
        expect(model.arollProductionMethod(for: projectRowID) == .searchMaterial,
               "Reopening the project restores its saved selection")

        let otherProject = root.appendingPathComponent("other-project", isDirectory: true)
        model.clearDestinationDirectory()
        model.acceptDestinationDirectoryDrop(otherProject)
        model.importScript(from: importedScript)
        model.confirmScript()
        expect(model.arollProductionMethod(for: projectRowID) == .none,
               "A different project with identical script must not inherit the previous choice")
        model.clearDestinationDirectory()
        print("PASS production methods: legacy projects, undo/redo, relaunch, type switches, edits, duplicates, split/merge, project save/restore and isolation")
    }
}
