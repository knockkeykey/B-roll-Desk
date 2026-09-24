import SwiftUI

@main
struct BrollNamerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("B-roll 配对台") {
            ContentView(model: model)
                .frame(minWidth: 1440, minHeight: 720)
        }
        .defaultSize(width: 1600, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("工作区") {
                Button("编辑 / 导入文案") {
                    model.isScriptEditorPresented = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("刷新素材目录") {
                    model.refreshSourceFiles()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("在 Finder 中打开 JSON 清单") {
                    model.revealManifest()
                }

                Button("预览 JSON 清单") {
                    model.previewManifest()
                }
            }
        }
    }
}
