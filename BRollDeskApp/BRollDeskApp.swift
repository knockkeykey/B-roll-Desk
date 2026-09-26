import SwiftUI
import AppKit
import CoreText

@main
struct BRollDeskApp: App {
    @State private var model = AppModel()

    init() {
        if let fontURL = Bundle.main.url(forResource: "SmileySans-Oblique", withExtension: "ttf") {
            _ = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup("B-roll配对台") {
            ContentView(model: model)
                .background {
                    WindowTitlebarDoubleClickZoomInstaller()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 1440, minHeight: 720)
        }
        .defaultSize(width: 1600, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            UndoRedoCommands(model: model)
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

                Button("在 Finder 新标签页中打开给 Codex 的 JSON 对照表") {
                    model.revealManifest()
                }

                Button("预览给 Codex 的 JSON 对照表") {
                    model.previewManifest()
                }
            }
        }
    }
}

private struct UndoRedoCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("撤销") {
                model.undo()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(!model.canUndo)

            Button("重做") {
                model.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.canRedo)
        }
    }
}

private struct WindowTitlebarDoubleClickZoomInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowTitlebarDoubleClickZoomView {
        WindowTitlebarDoubleClickZoomView()
    }

    func updateNSView(_ nsView: WindowTitlebarDoubleClickZoomView, context: Context) {}
}

private final class WindowTitlebarDoubleClickZoomView: NSView {
    private weak var monitoredWindow: NSWindow?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard monitoredWindow !== window else { return }
        stopMonitoring()
        monitoredWindow = window

        guard window != nil else { return }
        // SwiftUI's windowBackgroundDragBehavior modifier requires macOS 15.
        // Set the equivalent AppKit behavior here to keep custom-header dragging on macOS 14.
        window?.isMovableByWindowBackground = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    deinit {
        stopMonitoring()
    }

    private func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        monitoredWindow = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.clickCount == 2,
              let window = monitoredWindow,
              event.window === window,
              let headerRegion = headerRegion(in: window),
              headerRegion.contains(event.locationInWindow),
              !isInteractiveClick(event.locationInWindow, in: window) else {
            return event
        }

        // NSWindow.zoom(_:) toggles between the standard frame and the user's prior frame.
        window.zoom(nil)
        return nil
    }

    private func headerRegion(in window: NSWindow) -> NSRect? {
        guard let contentView = window.contentView else { return nil }
        let contentFrame = contentView.convert(contentView.bounds, to: nil)
        let nativeControlFrames = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { button -> NSRect? in
            guard let button else { return nil }
            return button.convert(button.bounds, to: nil)
        }

        let headerTop = max(contentFrame.maxY, nativeControlFrames.map(\.maxY).max() ?? contentFrame.maxY)
        return NSRect(
            x: contentFrame.minX,
            y: headerTop - WindowHeaderMetrics.height,
            width: contentFrame.width,
            height: WindowHeaderMetrics.height
        )
    }

    private func isInteractiveClick(_ point: NSPoint, in window: NSWindow) -> Bool {
        let nativeWindowControlFrames = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { button -> NSRect? in
            guard let button else { return nil }
            return button.convert(button.bounds, to: nil).insetBy(dx: -6, dy: -6)
        }
        if nativeWindowControlFrames.contains(where: { $0.contains(point) }) {
            return true
        }

        guard let contentView = window.contentView else { return false }
        let contentPoint = contentView.convert(point, from: nil)
        guard let hitView = contentView.hitTest(contentPoint) else { return false }
        return hitView is NSControl || hitView is NSTextView
    }
}
