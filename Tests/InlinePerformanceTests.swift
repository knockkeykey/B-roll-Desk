import AppKit
import Foundation

/// A deterministic, isolated Release fixture shared by model and native UI measurements.
@main struct InlinePerformanceTests {
    @MainActor static func main() throws {
        let preparing = CommandLine.arguments.contains("--prepare")
        let root = URL(fileURLWithPath: CommandLine.arguments.last!, isDirectory: true)
        let suite = "com.keyknock.BrollDesk.Verification.\(root.lastPathComponent)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { if !preparing { defaults.removePersistentDomain(forName: suite) } }
        let project = root.appendingPathComponent("project", isDirectory: true)
        let broll = project.appendingPathComponent("B-roll", isDirectory: true)
        let aroll = project.appendingPathComponent("A-roll", isDirectory: true)
        try FileManager.default.createDirectory(at: broll, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aroll, withIntermediateDirectories: true)
        let texts = (0..<300).map { i in
            i % 17 == 0 ? "重复文案用于验证同一句话的不同条目不会混淆绑定和拍摄设置。" :
            "第\(i + 1)条：" + String(repeating: "把素材放进文件夹，再按顺序整理，保留原文和已有素材。", count: 1 + i % 3)
        }
        var occurrences: [String: Int] = [:]
        let rows = texts.enumerated().map { i, text -> AnchorRow in
            let hash = ScriptParser.hash(text)
            occurrences[hash, default: 0] += 1
            return AnchorRow(id: ScriptParser.key(for: text, occurrence: occurrences[hash]!), index: i + 1, text: text)
        }
        var assignments: [String: [BrollAsset]] = [:]
        // A real tiny PNG keeps thumbnail work identical in both builds, without touching user assets.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=")!
        for row in rows where (row.index - 1) % 3 == 0 {
            let name = "fixture-\(row.index).png"
            try png.write(to: broll.appendingPathComponent(name))
            assignments[row.id] = [BrollAsset(id: "asset-\(row.index)", anchorKey: row.id, anchorIndex: row.index,
                anchorText: row.text, sourceName: name, sourceDirectoryID: "fixture", sourceRelativePath: name,
                outputName: name, mode: .fs, targetTrack: "V3", audio: "preserve", copiedAt: "fixture")]
        }
        let tasks = rows.filter { ($0.index - 1) % 10 == 0 }.map {
            AnimationTask(id: "task-\($0.index)", rowID: $0.id, text: $0.text, reason: "流程", outputFilename: "animation-\($0.index).mp4")
        }
        let settings = BrollProjectSettings(projectID: "inline-performance", prefix: "perf",
            anchorNotes: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, "备注\($0.index)") }),
            rollTypeOverrides: Dictionary(uniqueKeysWithValues: tasks.map { ($0.rowID, .bRoll) }),
            brollProductionMethods: Dictionary(uniqueKeysWithValues: tasks.map { ($0.rowID, .animation) }),
            assignments: assignments, animationTasks: tasks)
        try JSONEncoder().encode(settings).write(to: broll.appendingPathComponent("project-settings.json"), options: .atomic)
        try texts.joined(separator: "\n").write(to: aroll.appendingPathComponent("正确文案.txt"), atomically: true, encoding: .utf8)
        let cache = root.appendingPathComponent("assignments.json")
        let model = AppModel(defaults: defaults, assignmentsURL: cache)
        model.acceptDestinationDirectoryDrop(project)
        model.flushPendingInlineSaves()
        precondition(model.rows.count == 300 && model.activeAnimationTasks.count == 30)
        guard !preparing else { print("PREPARED \(root.path)"); return }
        model.undoManager.groupsByEvent = false
        let original = model.scriptText
        var times: [Double] = []
        for iteration in 0..<60 {
            let index = [0, 149, 299][iteration % 3]
            model.undoManager.beginUndoGrouping()
            let start = ProcessInfo.processInfo.systemUptime
            model.splitInlineRow(at: index, text: model.rows[index].text, selection: NSRange(location: 10, length: 0))
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            model.undoManager.endUndoGrouping()
            model.undoManager.beginUndoGrouping()
            let mergeStart = ProcessInfo.processInfo.systemUptime
            _ = model.mergeInlineRowWithPrevious(at: index + 1, text: model.rows[index + 1].text)
            times.append((ProcessInfo.processInfo.systemUptime - mergeStart) * 1000)
            model.undoManager.endUndoGrouping()
        }
        model.flushPendingInlineSaves()
        precondition(model.scriptText == original && model.rows.count == 300)
        let sorted = times.sorted()
        print("MODEL samples=\(times.count) p50_ms=\(sorted[sorted.count / 2]) p95_ms=\(sorted[Int(Double(sorted.count - 1) * 0.95)]) max_ms=\(sorted.last!)")
        let saved = try String(contentsOf: aroll.appendingPathComponent("正确文案.txt"), encoding: .utf8)
        precondition(saved == original)
    }
}
