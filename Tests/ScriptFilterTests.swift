import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

private func aRoll(device: String? = "sony", method: ArollProductionMethod = .none,
                   blank: Bool = false, status: BrollPreparationStatus? = nil) -> ScriptRowFilter.Attributes {
    ScriptRowFilter.Attributes(rollType: .aRoll, isBlank: blank, shootingDeviceID: device,
                               arollMethod: method, brollMethod: .undecided, brollStatus: .pending,
                               arollStatus: status)
}

private func bRoll(method: BrollProductionMethod = .undecided,
                   status: BrollPreparationStatus = .pending) -> ScriptRowFilter.Attributes {
    ScriptRowFilter.Attributes(rollType: .bRoll, isBlank: false, shootingDeviceID: "sony",
                               arollMethod: .none, brollMethod: method, brollStatus: status)
}

@main
struct ScriptFilterTests {
    @MainActor static func main() throws {
        // Tri-state cycle.
        expect(ScriptFilterState.next(after: nil) == .include, "First click includes")
        expect(ScriptFilterState.next(after: .include) == .exclude, "Second click excludes")
        expect(ScriptFilterState.next(after: .exclude) == nil, "Third click clears")

        // Empty filter shows everything, including blank rows.
        var filter = ScriptRowFilter()
        expect(!filter.isActive, "Default filter is inactive")
        expect(ScriptPreparationFilter.allCases.map(\.title) == ["待准备", "素材就绪", "待绑定"], "Only three shared preparation choices are offered")
        expect(filter.matches(aRoll(blank: true)), "Blank rows show without filters")
        expect(filter.matches(bRoll()), "B-roll shows without filters")

        // Include values are OR-ed within a facet.
        filter.brollMethods[.animation] = .include
        filter.brollMethods[.aiVideo] = .include
        expect(filter.matches(bRoll(method: .animation)), "Included method shows")
        expect(filter.matches(bRoll(method: .aiVideo)), "Second included method shows")
        expect(!filter.matches(bRoll(method: .liveAction)), "Non-included method hides")
        // B-roll conditions do not affect A-roll.
        expect(filter.matches(aRoll()), "B-roll method filter leaves A-roll visible")
        expect(!filter.matches(aRoll(blank: true)), "Blank rows hide once a filter is active")

        // Exclude-only facet hides just the excluded values.
        filter.reset()
        filter.brollMethods[.undecided] = .exclude
        expect(!filter.matches(bRoll(method: .undecided)), "Excluded method hides")
        expect(filter.matches(bRoll(method: .stockFootage)), "Other methods still show")

        // Facets combine with AND for the same roll type.
        filter.preparationStatuses[.unbound] = .include
        expect(!filter.matches(bRoll(method: .animation, status: .bound)), "Bound excluded")
        expect(filter.matches(bRoll(method: .animation, status: .ready)), "Ready animation shows")
        expect(!filter.matches(bRoll(method: .undecided, status: .ready)), "Both facets must pass")
        expect(filter.activeConditionCount == 2, "Two conditions active")

        // A-roll and B-roll conditions are evaluated independently, then merged.
        filter.reset()
        filter.shootingDevices["sony"] = .include
        filter.brollMethods[.animation] = .include
        expect(filter.matches(aRoll(device: "sony")), "Sony A-roll shows")
        expect(!filter.matches(aRoll(device: "dji")), "DJI A-roll hides")
        expect(filter.matches(bRoll(method: .animation)), "Animation B-roll shows")
        expect(!filter.matches(bRoll(method: .liveAction)), "Live-action B-roll hides")

        // One preparation filter applies to both B-roll and bindable auxiliary A-roll.
        filter.reset()
        filter.preparationStatuses[.unbound] = .include
        expect(filter.isActive && filter.activeConditionCount == 1, "Shared status counts as one condition")
        expect(filter.matches(aRoll(device: "dji", status: .pending)), "Unbound includes pending auxiliary A-roll")
        expect(filter.matches(aRoll(device: "dji", status: .ready)), "Unbound includes ready auxiliary A-roll")
        expect(!filter.matches(aRoll(device: "dji", status: .bound)), "Unbound excludes bound auxiliary A-roll")
        expect(!filter.matches(aRoll()), "Main A-roll is not counted as pending or unbound")
        expect(filter.matches(bRoll(status: .pending)) && filter.matches(bRoll(status: .ready)), "Shared unbound includes pending and ready B-roll")
        expect(!filter.matches(bRoll(status: .bound)), "Shared unbound hides bound B-roll")
        filter.shootingDevices["dji"] = .include
        filter.arollMethods[.text] = .include
        expect(filter.matches(aRoll(device: "dji", method: .text, status: .ready)), "Device, method and status combine with AND")
        expect(!filter.matches(aRoll(device: "sony", method: .text, status: .ready)), "Status does not bypass device filter")
        expect(!filter.matches(aRoll(device: "dji", status: .ready)), "Status does not bypass method filter")
        filter.reset()
        filter.preparationStatuses[.pending] = .include
        expect(filter.matches(aRoll(device: "dji", status: .pending)), "Pending status shows")
        expect(!filter.matches(aRoll(device: "dji", status: .ready)), "Pending status hides ready")
        expect(filter.matches(bRoll(status: .pending)) && !filter.matches(bRoll(status: .ready)), "Shared pending applies to both roll types")
        filter.preparationStatuses[.ready] = .include
        expect(filter.matches(aRoll(device: "dji", status: .ready)), "Included pending and ready combine with OR")
        expect(filter.matches(bRoll(status: .ready)), "Ready B-roll joins the same shared selection")
        filter.preparationStatuses[.unbound] = .exclude
        expect(!filter.matches(aRoll(device: "dji", status: .pending))
               && !filter.matches(aRoll(device: "dji", status: .ready)), "Overlapping unbound exclusion wins over specific includes")
        filter.reset()
        filter.preparationStatuses[.unbound] = .include
        filter.preparationStatuses[.ready] = .exclude
        expect(filter.matches(aRoll(device: "dji", status: .pending))
               && !filter.matches(aRoll(device: "dji", status: .ready)), "Ready exclusion narrows unbound to pending")
        filter.reset()
        filter.preparationStatuses[.unbound] = .exclude
        expect(filter.matches(aRoll(device: "dji", status: .bound)), "Excluding unbound retains bound rows")
        expect(!filter.matches(aRoll(device: "dji", status: .ready)), "Excluding unbound hides ready rows")
        filter.reset()
        expect(!filter.isActive && filter.matches(aRoll()), "Reset clears shared preparation and restores main-device rows")

        // Unset device is a filterable option.
        filter.reset()
        filter.shootingDevices[nil] = .include
        expect(filter.matches(aRoll(device: nil)), "Unset device included")
        expect(!filter.matches(aRoll(device: "sony")), "Set device hidden when only unset is included")

        // Mixed include and exclude in one facet: excludes win, includes restrict.
        filter.reset()
        filter.arollMethods[.text] = .include
        filter.arollMethods[.none] = .exclude
        expect(filter.matches(aRoll(method: .text)), "Included A-roll method shows")
        expect(!filter.matches(aRoll(method: .none)), "Excluded A-roll method hides")
        expect(!filter.matches(aRoll(method: .searchMaterial)), "Unmentioned method hides when includes exist")

        // Hiding a whole roll type.
        filter.reset()
        filter.showsAroll = false
        expect(filter.isActive, "Hiding A-roll activates the filter")
        expect(!filter.matches(aRoll()), "A-roll hidden")
        expect(filter.matches(bRoll()), "B-roll still shown")

        // Retain drops stale device conditions.
        filter.reset()
        filter.shootingDevices["sony"] = .include
        filter.shootingDevices["deleted"] = .exclude
        filter.shootingDevices[nil] = .exclude
        filter.shootingDevices.retain(["sony", nil])
        expect(filter.shootingDevices["deleted"] == nil, "Deleted device condition removed")
        expect(filter.shootingDevices["sony"] == .include, "Existing device condition kept")
        expect(filter.shootingDevices[nil] == .exclude, "Unset-device condition kept")

        // AppModel produces attributes from row metadata.
        let suite = "com.keyknock.BrollDesk.FilterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let assignmentCacheURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(suite).appendingPathComponent("assignments.json")
        defer { try? FileManager.default.removeItem(at: assignmentCacheURL.deletingLastPathComponent()) }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("第一条文案\n\n第三条", forKey: "broll-namer-script")
        let model = AppModel(defaults: defaults, assignmentsURL: assignmentCacheURL)
        defer { model.flushPendingInlineSaves() }
        let first = model.filterAttributes(for: model.rows[0])
        expect(first.rollType == .aRoll && !first.isBlank, "First row is non-blank A-roll")
        expect(first.shootingDeviceID == "sony", "Default device is Sony")
        expect(first.arollStatus == nil, "Main-device attributes have no preparation state")
        model.undoManager.groupsByEvent = false
        model.undoManager.beginUndoGrouping()
        model.setShootingDevice(model.auxiliaryShootingDevice, for: model.rows[0].id)
        expect(model.filterAttributes(for: model.rows[0]).arollStatus == .pending, "Auxiliary attributes start pending")
        model.setBrollPreparationStatus(.ready, for: model.rows[0].id)
        model.undoManager.endUndoGrouping()
        expect(model.filterAttributes(for: model.rows[0]).arollStatus == .ready, "Auxiliary attributes follow the ready state")
        expect(model.filterAttributesAfterBinding(for: model.rows[0]).arollStatus == .bound, "Binding predicts bound auxiliary status")
        filter.reset()
        filter.preparationStatuses[.unbound] = .include
        expect(filter.matches(model.filterAttributes(for: model.rows[0]))
               && !filter.matches(model.filterAttributesAfterBinding(for: model.rows[0])),
               "Pending binding exit is scheduled only when the selected A-roll status will hide the row")
        if model.rows.count > 2 {
            expect(model.filterAttributes(for: model.rows[1]).isBlank, "Empty row is blank")
        }

        print("ScriptFilterTests passed")
    }
}
