import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

private func close(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.000001 }

@main
struct ScriptTimelineTests {
    @MainActor
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

        let earlier = middle.panned(byScrollDelta: 1, precise: false, viewportWidth: 1000)
        let later = middle.panned(byScrollDelta: -1, precise: false, viewportWidth: 1000)
        expect(earlier.start < middle.start && close(earlier.span, middle.span),
               "Scrolling up in the main timeline moves earlier without changing zoom")
        expect(later.start > middle.start && close(later.span, middle.span),
               "Scrolling down in the main timeline moves later without changing zoom")
        expect(close(earlier.panned(byScrollDelta: -1, precise: false, viewportWidth: 1000).start, middle.start),
               "Opposite pan steps restore the original position")
        expect(close(middle.panned(byScrollDelta: 100, precise: true, viewportWidth: 1000).start, 0.28),
               "Trackpad panning scales pixels to the visible range")
        expect(middle.panned(byScrollDelta: .infinity, precise: false, viewportWidth: 1000) == middle
               && middle.panned(byScrollDelta: 1, precise: true, viewportWidth: 0) == middle,
               "Invalid pan input leaves the range unchanged")
        let head = ScriptTimelineViewport(start: 0, end: 0.2)
        let tail = ScriptTimelineViewport(start: 0.8, end: 1)
        expect(head.panned(byScrollDelta: 1, precise: false, viewportWidth: 1000) == head
               && tail.panned(byScrollDelta: -1, precise: false, viewportWidth: 1000) == tail,
               "Wheel panning stops at both script boundaries")
        expect(ScriptTimelineViewport.full.panned(byScrollDelta: -1, precise: false, viewportWidth: 1000) == .full,
               "A full-script range cannot pan beyond its boundaries")

        let suite = "broll-timeline-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let embedded = ScriptTimelineState(defaults: defaults)
        let detached = embedded
        embedded.visibleRows = [visible("row-20")]
        embedded.initializeIfNeeded(in: distribution)
        let panned = ScriptTimelineViewport(start: 0.6, end: 0.8)
        embedded.setRange(panned)
        detached.initializeIfNeeded(in: distribution)
        expect(detached.viewport == panned, "Opening or reopening the window preserves manual pan and zoom")
        detached.setRange(detached.viewport.zoomed(by: 1.5))
        expect(embedded.viewport == detached.viewport && embedded.viewport.span < panned.span,
               "A zoom button from either window updates the same live viewport")
        let remembered = embedded.viewport.span
        let beforePan = detached.viewport
        detached.setRange(detached.viewport.panned(byScrollDelta: -1, precise: false, viewportWidth: 1000))
        expect(embedded.viewport.start > beforePan.start && close(embedded.viewport.span, remembered),
               "Main timeline wheel panning updates both windows while preserving zoom")
        detached.toggleFollowMode(in: distribution)
        expect(embedded.viewport == .full && !embedded.followsScript,
               "Global overview is shared between both windows")
        embedded.visibleRows = [visible("row-80")]
        embedded.updateFollowRange(in: distribution)
        expect(detached.viewport == .full, "List scrolling does not leave global overview")
        detached.toggleFollowMode(in: distribution)
        expect(close(embedded.viewport.span, remembered) && close(embedded.viewport.center, 0.795),
               "Adaptive mode restores zoom and follows the main list from either window")
        embedded.selectedRowID = "row-40"
        detached.followSelection(in: distribution)
        expect(detached.selectedRowID == "row-40" && close(embedded.viewport.center, 0.395),
               "Script selection is shared and can move both viewports together")
        detached.requestReveal("row-80")
        let firstRequest = embedded.revealRequest
        detached.requestReveal("row-80")
        expect(embedded.revealRequest?.rowID == "row-80" && embedded.revealRequest != firstRequest,
               "Repeated clicks on the same detached segment can each reveal the main list row")
        let relaunched = ScriptTimelineState(defaults: defaults)
        relaunched.visibleRows = [visible("row-50")]
        relaunched.initializeIfNeeded(in: distribution)
        expect(close(relaunched.viewport.span, remembered), "Shared zoom persists across app launches")
        print("Script timeline: 34 checks and 400 fixed-zoom scroll positions passed")
    }
}
