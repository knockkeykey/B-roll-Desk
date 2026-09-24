import SwiftUI
import CoreText

@main
struct BrollNamerApp: App {
    @State private var model = AppModel()

    init() {
        if let fontURL = Bundle.main.url(forResource: "SmileySans-Oblique", withExtension: "ttf") {
            _ = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup("B-roll 配对台") {
            ContentView(model: model)
                .frame(minWidth: 1440, minHeight: 720)
        }
        .defaultSize(width: 1600, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            UndoRedoCommands()
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

                Button("在 Finder 新标签页中打开 JSON 清单") {
                    model.revealManifest()
                }

                Button("预览 JSON 清单") {
                    model.previewManifest()
                }
            }
        }
    }
}

private struct UndoRedoCommands: Commands {
    @Environment(\.undoManager) private var undoManager

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("撤销") {
                undoManager?.undo()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(undoManager?.canUndo != true)

            Button("重做") {
                undoManager?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(undoManager?.canRedo != true)
        }
    }
}
