import AppKit
import Foundation

@main struct ScriptImportPersistenceTests {
    @MainActor static func main() async throws {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        for scenario in ["new-txt", "replace-txt", "new-md", "pending-inline", "write-failure"] {
            let suite = "BrollScriptImportPersistenceTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
            let project = root.appendingPathComponent("project", isDirectory: true)
            let scriptURL = project.appendingPathComponent("A-roll/正确文案.txt")
            if scenario == "replace-txt" || scenario == "pending-inline" {
                try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "旧文案，导入后必须替换。".write(to: scriptURL, atomically: true, encoding: .utf8)
            }
            let model = AppModel(defaults: defaults, assignmentsURL: root.appendingPathComponent("cache/assignments.json"))
            defer { model.flushPendingInlineSaves() }
            // Finish initial directory restoration before explicitly choosing the test project.
            await Task.yield()
            model.acceptDestinationDirectoryDrop(project)
            if scenario == "pending-inline" {
                model.replaceInlineRow(at: 0, with: "尚未落盘的旧文案修改。")
            }
            let previousScript = model.scriptText
            let text = "第一句，直接拖入后就应保存，不需要再点完成。\n第二句，重启后继续显示。"
            let importedURL = root.appendingPathComponent(scenario == "new-md" ? "source.md" : "source.txt")
            try text.write(to: importedURL, atomically: true, encoding: .utf8)
            if scenario == "write-failure" {
                // A directory at the target filename deterministically rejects an atomic text write.
                try FileManager.default.createDirectory(at: scriptURL, withIntermediateDirectories: true)
            }

            model.importScript(from: importedURL)
            model.flushPendingInlineSaves()
            if scenario == "write-failure" {
                expect(model.alert != nil, "write-failure: import must surface the project-file save error")
                expect(model.scriptText == previousScript, "write-failure: failed import must retain the previous script")
                continue
            }
            expect(model.scriptText == text && model.rows.count == 2, "\(scenario): import immediately loads both rows")
            expect((try? String(contentsOf: scriptURL, encoding: .utf8)) == text,
                   "\(scenario): import must write the file that startup reads")
            expect((try? String(contentsOf: importedURL, encoding: .utf8)) == text,
                   "\(scenario): original file remains unchanged")
            // Prove restoration comes from the project, rather than surviving process/cache state.
            defaults.set("另一个本机缓存，不能取代项目文案。", forKey: "broll-namer-script")
            let reopened = AppModel(defaults: defaults, assignmentsURL: root.appendingPathComponent("reopened-cache.json"))
            await Task.yield()
            reopened.acceptDestinationDirectoryDrop(project)
            expect(reopened.scriptText == text && reopened.rows.count == 2,
                   "\(scenario): recreating the model and reopening the project must recover the imported script")
            reopened.clearDestinationDirectory()
        }

        guard failures.isEmpty else {
            for failure in failures { print("FAIL \(failure)") }
            exit(1)
        }
        print("PASS script import persistence: direct import, replacement, txt/md, pending inline saves, project-file restoration independent of cache, source preservation and write errors")
    }
}
