import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct ARollPacingTests {
    @MainActor static func main() {
        func row(_ index: Int, _ count: Int) -> AnchorRow {
            AnchorRow(id: "row-\(index)", index: index, text: String(repeating: "字", count: count))
        }
        let boundaryRows = [row(1, 29), row(2, 1), row(3, 10)]
        let hints = ARollPacing.hints(for: boundaryRows) { _ in .aRoll }
        expect(hints["row-1"] == nil, "29 characters remain below five seconds")
        expect(hints["row-2"]?.cumulativeCharacterCount == 30, "The thirtieth character crosses five seconds")
        expect(hints["row-3"]?.cumulativeCharacterCount == 40, "Short consecutive rows accumulate")
        expect(hints["row-2"]?.startRowIndex == 1 && hints["row-2"]?.endRowIndex == 3,
               "Each reminder retains the complete run range")
        expect(hints["row-2"]?.totalCharacterCount == 40, "Whole-run duration includes later A-roll")
        expect(abs(ARollPacing.seconds(for: 350) - 60) < 0.0001, "Reading rate is 350 characters per minute")
        expect(ARollPacing.spokenCharacterCount(in: "中 文，。\nA1! 🎥") == 4,
               "Punctuation, whitespace and visual symbols do not inflate speech estimates")

        let interruptedRows = [row(1, 29), row(2, 10), row(3, 29), row(4, 1)]
        let interrupted = ARollPacing.hints(for: interruptedRows) { $0 == "row-2" ? .bRoll : .aRoll }
        expect(interrupted["row-1"] == nil && interrupted["row-2"] == nil && interrupted["row-3"] == nil,
               "B-roll interrupts continuity and never receives an A-roll reminder")
        expect(interrupted["row-4"]?.startRowIndex == 3 && interrupted["row-4"]?.cumulativeCharacterCount == 30,
               "The following A-roll run begins from zero")

        let emptyRows = [row(1, 15), AnchorRow(id: "empty", index: 2, text: ""),
                         AnchorRow(id: "punctuation", index: 3, text: "……！？"), row(4, 15)]
        let acrossBlanks = ARollPacing.hints(for: emptyRows) { $0 == "empty" ? .bRoll : .aRoll }
        expect(acrossBlanks["row-4"]?.cumulativeCharacterCount == 30,
               "An empty B-roll marker cannot falsely clear a continuous run")
        expect(acrossBlanks["empty"] == nil && acrossBlanks["punctuation"] == nil,
               "Empty and punctuation-only anchors never display reminders")
        expect(ARollPacing.hints(for: []) { _ in .aRoll }.isEmpty, "Empty projects have no reminders")
        expect(ARollPacing.hints(for: [row(1, 60)]) { _ in .aRoll }["row-1"] != nil,
               "A single long A-roll row also needs a reminder")

        let custom = ARollPacingSettings(charactersPerMinute: 600, maximumContinuousSeconds: 3)
        let customHints = ARollPacing.hints(for: boundaryRows, settings: custom) { _ in .aRoll }
        expect(customHints["row-2"] == nil && customHints["row-3"]?.cumulativeSeconds == 4,
               "Custom rate and threshold use a strict boundary and update displayed seconds together")
        expect(customHints["row-3"]?.totalSeconds == 4 && customHints["row-3"]?.settings == custom,
               "Reminder details carry the configuration used for the calculation")
        expect(ARollPacing.hints(for: boundaryRows, settings: ARollPacingSettings(remindersEnabled: false)) { _ in .aRoll }.isEmpty,
               "Disabled reminders are absent")
        expect(ARollPacingSettings(charactersPerMinute: 0, maximumContinuousSeconds: .nan) == ARollPacingSettings(),
               "Invalid stored values safely fall back to defaults")

        let distribution = ScriptDistribution(rows: [row(1, 10), row(2, 30)]) {
            $0 == "row-2" ? .bRoll : .aRoll
        }
        expect(distribution.segments[0].fraction == 0.25 && distribution.segments[1].fraction == 0.75,
               "The overview represents text length instead of treating every sentence as equally long")
        expect(distribution.segments[0].startFraction == 0 && distribution.segments[1].endFraction == 1
               && distribution.segments[0].endFraction == distribution.segments[1].startFraction,
               "The complete script spans the strip without gaps or overlap")
        expect(distribution.segments.map(\.id) == ["row-1", "row-2"]
               && distribution.segments[1].rollType == .bRoll,
               "Segments preserve the original row identity, order and roll tag for navigation")
        expect(ScriptDistribution(rows: []) { _ in .aRoll }.segments.isEmpty,
               "An empty script does not produce invalid fractions")
        expect(ScriptDistribution(rows: emptyRows) { _ in .aRoll }.segments.map(\.id) == ["row-1", "row-4"],
               "Blank and punctuation-only rows do not inflate the overview")

        let suite = "com.keyknock.BrollNamer.PacingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let assignmentCacheURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(suite).appendingPathComponent("assignments.json")
        defer { try? FileManager.default.removeItem(at: assignmentCacheURL.deletingLastPathComponent()) }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("第一条" + String(repeating: "甲", count: 12) + "\n第二条" + String(repeating: "乙", count: 12)
                     + "\n第三条" + String(repeating: "丙", count: 12), forKey: "broll-namer-script")
        let model = AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL)
        defer { model.flushPendingInlineSaves() }
        let ids = model.rows.map(\.id)
        func modelDistribution() -> ScriptDistribution {
            model.scriptDistribution
        }
        let completeDistribution = modelDistribution()
        expect(model.pacingSettings == ARollPacingSettings(), "Existing users keep the original defaults")
        model.updatePacingSettings(custom)
        expect(model.aRollPacingHints[ids[1]] == nil && model.aRollPacingHints[ids[2]]?.cumulativeSeconds == 4.5,
               "Changing preferences immediately recalculates the existing script")
        expect(AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).pacingSettings == custom, "Rate and threshold survive model recreation")
        model.updatePacingSettings(ARollPacingSettings(charactersPerMinute: 600,
                                                     maximumContinuousSeconds: 3, remindersEnabled: false))
        expect(model.aRollPacingHints.isEmpty && !AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL).pacingSettings.remindersEnabled,
               "Disabling reminders persists independently of the numeric settings")
        model.updatePacingSettings(ARollPacingSettings())
        expect(model.aRollPacingHints[ids[1]] != nil, "The model exposes cross-row reminders")
        model.anchorSearchText = "第三条"
        expect(model.filteredRows.count == 1 && model.aRollPacingHints[ids[2]]?.cumulativeCharacterCount == 45,
               "Search visibility cannot change the script's actual continuity")
        expect(modelDistribution() == completeDistribution,
               "Search and reading-rate changes cannot alter the complete text distribution")
        model.undoManager.beginUndoGrouping()
        model.toggleRollType(for: ids[1])
        model.undoManager.endUndoGrouping()
        expect(model.aRollPacingHints.isEmpty, "Marking the middle row B-roll clears both short runs")
        expect(modelDistribution().segments[1].rollType == .bRoll,
               "Changing a roll tag immediately changes its overview segment")
        model.undo()
        expect(model.aRollPacingHints[ids[2]]?.cumulativeCharacterCount == 45,
               "Undo restores the original continuity and reminders")
        expect(modelDistribution() == completeDistribution, "Undo restores the overview too")
        model.redo()
        expect(model.aRollPacingHints.isEmpty, "Redo updates the reminders again")
        model.undo()
        model.anchorSearchText = ""
        model.undoManager.beginUndoGrouping()
        model.splitInlineRow(at: 0, text: model.rows[0].text, selection: NSRange(location: 5, length: 0))
        model.undoManager.endUndoGrouping()
        expect(model.aRollPacingHints[model.rows.last!.id]?.cumulativeCharacterCount == 45,
               "Splitting an A-roll row preserves cumulative timing")
        expect(abs(modelDistribution().segments.last!.startFraction - completeDistribution.segments.last!.startFraction) < 0.0001,
               "Splitting a row preserves the later script positions")
        print("PASS A-roll pacing and script distribution: settings, persistence, boundaries, proportions, search, undo/redo and split")
    }
}
