import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct ScriptDistributionTests {
    @MainActor static func main() {
        func row(_ index: Int, _ count: Int) -> AnchorRow {
            AnchorRow(id: "row-\(index)", index: index, text: String(repeating: "字", count: count))
        }
        let emptyRows = [row(1, 15), AnchorRow(id: "empty", index: 2, text: ""),
                         AnchorRow(id: "punctuation", index: 3, text: "……！？"), row(4, 15)]
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
        let mixedTextDistribution = ScriptDistribution(rows: [
            AnchorRow(id: "mixed", index: 1, text: "中 文，。\nA1! 🎥"), row(2, 4)
        ]) { _ in .aRoll }
        expect(mixedTextDistribution.segments[0].fraction == 0.5,
               "Punctuation, whitespace and visual symbols do not inflate text distribution")

        let suite = "com.keyknock.BrollNamer.ScriptDistributionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("第一条" + String(repeating: "甲", count: 12) + "\n第二条" + String(repeating: "乙", count: 12)
                     + "\n第三条" + String(repeating: "丙", count: 12), forKey: "broll-namer-script")
        let model = AppModel(defaults: defaults)
        let ids = model.rows.map(\.id)
        func modelDistribution() -> ScriptDistribution {
            ScriptDistribution(rows: model.rows, rollType: { model.rollType(for: $0) })
        }
        let completeDistribution = modelDistribution()
        model.anchorSearchText = "第三条"
        expect(model.filteredRows.count == 1, "Search narrows the visible rows")
        expect(modelDistribution() == completeDistribution,
               "Search cannot alter the complete text distribution")
        model.undoManager.beginUndoGrouping()
        model.toggleRollType(for: ids[1])
        model.undoManager.endUndoGrouping()
        expect(modelDistribution().segments[1].rollType == .bRoll,
               "Changing a roll tag immediately changes its overview segment")
        model.undo()
        expect(modelDistribution() == completeDistribution, "Undo restores the overview too")
        model.redo()
        expect(modelDistribution().segments[1].rollType == .bRoll, "Redo restores the changed overview segment")
        model.undo()
        model.anchorSearchText = ""
        model.undoManager.beginUndoGrouping()
        model.splitInlineRow(at: 0, text: model.rows[0].text, selection: NSRange(location: 5, length: 0))
        model.undoManager.endUndoGrouping()
        expect(abs(modelDistribution().segments.last!.startFraction - completeDistribution.segments.last!.startFraction) < 0.0001,
               "Splitting a row preserves the later script positions")
        print("PASS script distribution: proportions, search, undo/redo and split")
    }
}
