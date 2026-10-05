import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

private func close(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.000001 }

@main
struct ScriptTimelineTests {
    static func main() {
        let middle = ScriptTimelineViewport(start: 0.3, end: 0.5)
        let zoomed = middle.zoomed(by: 2)
        expect(close(zoomed.center, middle.center) && close(zoomed.span, 0.1),
               "Zoom keeps the user's location centered")
        expect(middle.zoomed(by: 0.01) == .full, "Zooming out fits the complete script")
        expect(close(middle.zoomed(by: 1000).span, ScriptTimelineViewport.minimumSpan),
               "Zooming in has a usable lower bound")
        expect(middle.zoomed(by: .nan) == middle, "Invalid zoom factors do not corrupt the viewport")
        let left = middle.moved(by: -10)
        let right = middle.moved(by: 10)
        expect(close(left.start, 0) && close(left.span, middle.span), "Panning stops at the beginning")
        expect(close(right.end, 1) && close(right.span, middle.span), "Panning stops at the end")
        expect(close(middle.resizingStart(to: 0.49).end, middle.end)
               && close(middle.resizingStart(to: 0.49).span, ScriptTimelineViewport.minimumSpan),
               "The left handle cannot cross the fixed right handle")
        expect(close(middle.resizingEnd(to: 0.1).start, middle.start)
               && close(middle.resizingEnd(to: 0.1).span, ScriptTimelineViewport.minimumSpan),
               "The right handle cannot cross the fixed left handle")
        expect(close(middle.resizingStart(to: -1).start, 0)
               && close(middle.resizingEnd(to: 2).end, 1), "Handles stay inside the complete script")
        expect(ScriptTimelineViewport(start: .nan, end: .infinity) == .full,
               "Invalid bounds safely show the complete script")

        let rows = (1...100).map { AnchorRow(id: "row-\($0)", index: $0, text: "等长文案") }
        let distribution = ScriptDistribution(rows: rows) { _ in .aRoll }
        func visible(_ id: String, _ start: Double = 0, _ end: Double = 1) -> VisibleScriptRow {
            VisibleScriptRow(id: id, startFraction: start, endFraction: end)
        }
        let savedSpan = 0.1
        let beginning = ScriptTimelineViewport.following([visible("row-1"), visible("row-2")], in: distribution,
                                                        preservingSpan: savedSpan)!
        let ending = ScriptTimelineViewport.following([visible("row-99"), visible("row-100")], in: distribution,
                                                     preservingSpan: savedSpan)!
        expect(close(beginning.start, 0) && close(beginning.span, savedSpan), "Follow keeps zoom at the head")
        expect(close(ending.end, 1) && close(ending.span, savedSpan), "Follow keeps zoom at the tail")
        let filtered = ScriptTimelineViewport.following([visible("row-20"), visible("row-80")], in: distribution,
                                                       preservingSpan: savedSpan)!
        expect(close(filtered.center, 0.495) && close(filtered.span, savedSpan),
               "Sparse search results move the viewport without changing the user's zoom")
        expect(ScriptTimelineViewport.following([], in: distribution, preservingSpan: savedSpan) == nil
               && ScriptTimelineViewport.following([visible("deleted")], in: distribution, preservingSpan: savedSpan) == nil,
               "An empty result or a removed row cannot follow a stale position")
        let short = ScriptDistribution(rows: Array(rows.prefix(2))) { _ in .aRoll }
        expect(close(ScriptTimelineViewport.following([visible("row-1"), visible("row-2")], in: short,
                                                     preservingSpan: savedSpan)!.span, savedSpan),
               "A short script cannot override the user's zoom")

        let longRows = [50, 100, 350].enumerated().map {
            AnchorRow(id: "long-\($0.offset)", index: $0.offset + 1, text: String(repeating: "字", count: $0.element))
        }
        let weighted = ScriptDistribution(rows: longRows) { _ in .bRoll }
        let partial = ScriptTimelineViewport.following([visible("long-1", 0.25, 0.75)], in: weighted,
                                                      preservingSpan: savedSpan)!
        expect(close(partial.center, 0.2) && close(partial.span, savedSpan),
               "A partly visible long row changes position while preserving zoom")
        let afterDeletion = ScriptDistribution(rows: Array(rows.dropFirst(50))) { _ in .aRoll }
        let updated = ScriptTimelineViewport.following([visible("row-51")], in: afterDeletion,
                                                      preservingSpan: savedSpan)!
        expect(close(updated.start, 0), "Deleting rows recalculates positions from the new script")
        for span in [0.02, 0.08, 0.4, 1.0] {
            for index in 1...100 {
                let followed = ScriptTimelineViewport.following([visible("row-\(index)")], in: distribution,
                                                               preservingSpan: span)!
                expect(close(followed.span, span), "Scrolling through the whole script never changes zoom")
            }
        }
        print("Script timeline: 18 checks and 400 fixed-zoom scroll positions passed")
    }
}
