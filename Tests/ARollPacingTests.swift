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

        let suite = "com.keyknock.BrollNamer.PacingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("第一条" + String(repeating: "甲", count: 12) + "\n第二条" + String(repeating: "乙", count: 12)
                     + "\n第三条" + String(repeating: "丙", count: 12), forKey: "broll-namer-script")
        let model = AppModel(defaults: defaults)
        let ids = model.rows.map(\.id)
        expect(model.aRollPacingHints[ids[1]] != nil, "The model exposes cross-row reminders")
        model.anchorSearchText = "第三条"
        expect(model.filteredRows.count == 1 && model.aRollPacingHints[ids[2]]?.cumulativeCharacterCount == 45,
               "Search visibility cannot change the script's actual continuity")
        model.undoManager.beginUndoGrouping()
        model.toggleRollType(for: ids[1])
        model.undoManager.endUndoGrouping()
        expect(model.aRollPacingHints.isEmpty, "Marking the middle row B-roll clears both short runs")
        model.undo()
        expect(model.aRollPacingHints[ids[2]]?.cumulativeCharacterCount == 45,
               "Undo restores the original continuity and reminders")
        model.redo()
        expect(model.aRollPacingHints.isEmpty, "Redo updates the reminders again")
        model.undo()
        model.anchorSearchText = ""
        model.undoManager.beginUndoGrouping()
        model.splitInlineRow(at: 0, text: model.rows[0].text, selection: NSRange(location: 5, length: 0))
        model.undoManager.endUndoGrouping()
        expect(model.aRollPacingHints[model.rows.last!.id]?.cumulativeCharacterCount == 45,
               "Splitting an A-roll row preserves cumulative timing")
        print("PASS A-roll pacing: boundaries, interruptions, empty anchors, search, roll changes, undo/redo and split")
    }
}
