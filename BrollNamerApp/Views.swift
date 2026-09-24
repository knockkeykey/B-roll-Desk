import AppKit
import AVKit
import AVFoundation
import ImageIO
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

private enum ListPaneMetrics {
    static let headerHeight: CGFloat = 70
    static let toolsHeight: CGFloat = 54
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @AppStorage("broll-namer-theme") private var themeRawValue = AppTheme.system.rawValue
    @State private var isSidebarVisible = true

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    private var preferredColorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        HSplitView {
            if isSidebarVisible {
                SidebarView(model: model, themeRawValue: $themeRawValue, isSidebarVisible: $isSidebarVisible)
                    .frame(minWidth: 238, idealWidth: 276, maxWidth: 340)
            }
            AnchorListView(model: model, isSidebarVisible: $isSidebarVisible)
                .frame(minWidth: 390, idealWidth: 540, maxWidth: 760)
            DetailView(model: model)
                .frame(minWidth: 780, idealWidth: 820)
        }
        .padding(.top, -28)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $model.isScriptEditorPresented) {
            ScriptEditorSheet(model: model)
        }
        .sheet(isPresented: $model.isManifestPreviewPresented) {
            ManifestPreviewSheet(text: model.manifestPreviewText)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
        .confirmationDialog(
            "清理归档副本与配对记录？",
            isPresented: $model.isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
                    Button("删除归档副本并清空记录", role: .destructive) {
                        model.clearAssignments()
                    }
                    .pointerCursor()
                    Button("取消", role: .cancel) {}
                        .pointerCursor()
        } message: {
            Text("将删除当前归档位置中已绑定及符合命名规则的旧素材副本，并更新 JSON 和 Markdown 清单。素材目录中的原始文件会保留。")
        }
        .preferredColorScheme(preferredColorScheme)
        .background(OverlayScrollerStyleInstaller().allowsHitTesting(false).accessibilityHidden(true))
    }
}

private struct OverlayScrollerStyleInstaller: NSViewRepresentable {
    final class Coordinator {
        var isScheduling = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        Self.installWhenAttached(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Self.installWhenAttached(view, coordinator: context.coordinator)
    }

    private static func installWhenAttached(
        _ view: NSView,
        coordinator: Coordinator,
        attemptsRemaining: Int = 20
    ) {
        guard !coordinator.isScheduling else { return }
        coordinator.isScheduling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            coordinator.isScheduling = false
            guard let window = view.window else {
                if attemptsRemaining > 0 {
                    installWhenAttached(view, coordinator: coordinator, attemptsRemaining: attemptsRemaining - 1)
                }
                return
            }
            applyOverlayStyle(in: window.contentView)
        }
    }

    private static func applyOverlayStyle(in root: NSView?) {
        guard let root else { return }
        var pendingViews = [root]

        while let view = pendingViews.popLast() {
            if let scrollView = view as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.scrollerKnobStyle = .default
                scrollView.autohidesScrollers = true

                if scrollView.hasVerticalScroller {
                    if !(scrollView.verticalScroller is InsetOverlayScroller) {
                        scrollView.verticalScroller = InsetOverlayScroller(frame: .zero)
                    }
                    scrollView.verticalScroller?.controlSize = .regular
                }
                if scrollView.hasHorizontalScroller {
                    if !(scrollView.horizontalScroller is InsetOverlayScroller) {
                        scrollView.horizontalScroller = InsetOverlayScroller(frame: .zero)
                    }
                    scrollView.horizontalScroller?.controlSize = .regular
                }
            }
            pendingViews.append(contentsOf: view.subviews)
        }
    }
}

private final class InsetOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    private var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func drawKnob() {
        // Keep the native scroll and drag behavior, but draw an Element Plus sized thumb.
        let isVertical = bounds.height >= bounds.width
        let knobRect = rect(for: .knob).insetBy(
            dx: isVertical ? 4 : 2,
            dy: isVertical ? 2 : 4
        )
        guard knobRect.width > 0, knobRect.height > 0 else { return }

        NSColor.labelColor.withAlphaComponent(isHovered ? 0.28 : 0.16).setFill()
        NSBezierPath(
            roundedRect: knobRect,
            xRadius: min(knobRect.width, knobRect.height) / 2,
            yRadius: min(knobRect.width, knobRect.height) / 2
        ).fill()
    }

    override func drawKnobSlot(in rect: NSRect, highlight: Bool) {
        // An overlay scrollbar has a transparent rail; AppKit fades the thumb for us.
    }
}

// SwiftUI's macOS scroll view can reserve a full scroller column even for overlay
// indicators. The material pane uses its own overlay so the content reaches the divider.
private struct MaterialScrollbarInstaller: NSViewRepresentable {
    final class Coordinator {
        weak var scrollView: NSScrollView?
        var indicator: MaterialScrollbar?
        var isScheduling = false
    }

    fileprivate func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        installLater(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        installLater(from: view, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.indicator?.removeFromSuperview()
        coordinator.indicator = nil
    }

    private func installLater(from view: NSView, coordinator: Coordinator, attempts: Int = 20) {
        guard !coordinator.isScheduling else { return }
        coordinator.isScheduling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            coordinator.isScheduling = false
            var ancestor = view.superview
            while let candidate = ancestor, !(candidate is NSScrollView) {
                ancestor = candidate.superview
            }
            guard let scrollView = ancestor as? NSScrollView else {
                if attempts > 0 {
                    installLater(from: view, coordinator: coordinator, attempts: attempts - 1)
                }
                return
            }

            if coordinator.scrollView !== scrollView {
                coordinator.indicator?.removeFromSuperview()
                let indicator = MaterialScrollbar(scrollView: scrollView)
                indicator.translatesAutoresizingMaskIntoConstraints = false
                scrollView.addSubview(indicator, positioned: .above, relativeTo: nil)
                NSLayoutConstraint.activate([
                    indicator.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                    indicator.topAnchor.constraint(equalTo: scrollView.topAnchor),
                    indicator.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                    indicator.widthAnchor.constraint(equalToConstant: 10)
                ])
                coordinator.scrollView = scrollView
                coordinator.indicator = indicator
            }
            scrollView.hasVerticalScroller = false
            coordinator.indicator?.needsDisplay = true
        }
    }
}

private final class MaterialScrollbar: NSView {
    private weak var scrollView: NSScrollView?
    private var clipObserver: NSObjectProtocol?
    private var documentObserver: NSObjectProtocol?
    private weak var trackedDocument: NSView?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isDragging = false
    private var dragOffset: CGFloat = 0

    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        observeScrollView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit {
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        if let documentObserver { NotificationCenter.default.removeObserver(documentObserver) }
    }

    func observeScrollView() {
        guard let scrollView else { return }
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        clipObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in self?.needsDisplay = true }

        if trackedDocument !== scrollView.documentView {
            if let documentObserver { NotificationCenter.default.removeObserver(documentObserver) }
            trackedDocument = scrollView.documentView
            trackedDocument?.postsFrameChangedNotifications = true
            documentObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: trackedDocument,
                queue: .main
            ) { [weak self] _ in self?.needsDisplay = true }
        }
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    private var thumbRect: NSRect? {
        guard let scrollView, let document = scrollView.documentView else { return nil }
        let visible = scrollView.contentView.documentVisibleRect
        let documentRect = document.bounds
        let range = documentRect.height - visible.height
        guard range > 1, bounds.height > 0 else { return nil }
        let height = min(bounds.height, max(24, bounds.height * visible.height / documentRect.height))
        let offset = document.isFlipped
            ? visible.minY - documentRect.minY
            : documentRect.maxY - visible.maxY
        let progress = min(1, max(0, offset / range))
        return NSRect(x: 1, y: (bounds.height - height) * progress, width: max(4, bounds.width - 2), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let thumbRect else { return }
        let trackRect = NSRect(x: bounds.midX - 1, y: 2, width: 2, height: max(0, bounds.height - 4))
        NSColor.labelColor.withAlphaComponent(isHovered || isDragging ? 0.10 : 0.055).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 1, yRadius: 1).fill()

        NSColor.labelColor.withAlphaComponent(isHovered || isDragging ? 0.62 : 0.38).setFill()
        NSBezierPath(roundedRect: thumbRect, xRadius: 3, yRadius: 3).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard let thumbRect else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragOffset = thumbRect.contains(point) ? point.y - thumbRect.minY : thumbRect.height / 2
        isDragging = true
        scroll(toThumbOrigin: point.y - dragOffset)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        scroll(toThumbOrigin: point.y - dragOffset)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
    }

    private func scroll(toThumbOrigin origin: CGFloat) {
        guard let scrollView, let document = scrollView.documentView, let thumbRect else { return }
        let clipView = scrollView.contentView
        let visible = clipView.documentVisibleRect
        let range = document.bounds.height - visible.height
        let travel = bounds.height - thumbRect.height
        guard range > 0, travel > 0 else { return }
        let progress = min(1, max(0, origin / travel))
        let y = document.isFlipped
            ? document.bounds.minY + range * progress
            : document.bounds.maxY - visible.height - range * progress
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clipView)
        needsDisplay = true
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Binding var themeRawValue: String
    @Binding var isSidebarVisible: Bool
    @FocusState private var isPrefixFocused: Bool

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "B-roll 配对台",
                systemImage: "film.stack",
                actions: [
                    PaneHeaderAction(systemImage: "sidebar.left", help: "收起侧边栏") {
                        isSidebarVisible = false
                    },
                    PaneHeaderAction(
                        systemImage: theme.icon,
                        help: "当前主题：\(theme.title)，点击切换"
                    ) {
                        themeRawValue = theme.next.rawValue
                    }
                ]
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SidebarSection(title: "归档设置", systemImage: "archivebox") {
                        VStack(alignment: .leading, spacing: 14) {
                            DirectoryChoiceRow(
                                title: "归档位置",
                                value: model.destinationDirectoryName,
                                isConfigured: model.destinationDirectoryURL != nil,
                                action: model.chooseDestinationDirectory,
                                openAction: model.revealDestinationDirectory
                            )

                            Divider()

                            HStack(spacing: 6) {
                                Label("命名规则", systemImage: "pencil.and.list.clipboard")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                ConfigurationStatusIcon(isConfigured: model.isPrefixValid,
                                                        readyHelp: "命名前缀已填写",
                                                        waitingHelp: "填写期数或前缀后可绑定素材")
                                Spacer(minLength: 0)
                            }

                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Label("期数 / 前缀", systemImage: "number")
                                        .font(.subheadline)
                                    Spacer()
                                }
                                TextField("例如 第15期", text: $model.prefix)
                                    .textFieldStyle(.plain)
                                    .font(.callout)
                                    .focused($isPrefixFocused)
                                    .background(PrefixFocusDismissView(isFocused: isPrefixFocused) {
                                        isPrefixFocused = false
                                    })
                                    .frame(height: 40)
                                    .padding(.horizontal, 10)
                                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(isPrefixFocused ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.55),
                                                          lineWidth: isPrefixFocused ? 1.5 : 0.5)
                                    }
                            }

                            Text("示例：\(model.isPrefixValid ? ScriptParser.sanitizePart(model.prefix, maxLength: 30) : "期数")_BR001_文案短句.ext")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .textSelection(.enabled)
                        }
                    }

                    SidebarSection(title: "清单", systemImage: "doc.text") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Label("JSON 文件", systemImage: "curlybraces")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                ManifestIconButton(title: "在 Finder 中显示 JSON 清单", systemImage: "folder") {
                                    model.revealManifest()
                                }
                                ManifestIconButton(title: "预览 JSON 清单内容", systemImage: "eye") {
                                    model.previewManifest()
                                }
                            }

                            Divider()

                            SidebarActionButton(title: "清空配对和归档副本", systemImage: "trash", role: .destructive) {
                                model.requestClearAssignments()
                            }
                        }
                    }

                    SidebarStatusView(model: model)

                }
                .padding(16)
            }
        }
        .background(.windowBackground)
        .defaultFocus($isPrefixFocused, false)
        .onAppear { isPrefixFocused = false }
        .onChange(of: model.prefix) { _, _ in
            model.persistPreferences()
        }
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 2)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
                }
        }
    }
}

private struct SidebarStatusView: View {
    @ObservedObject var model: AppModel

    private var isConnected: Bool {
        model.sourceDirectoryURL != nil && model.destinationDirectoryURL != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isConnected ? Color.green : Color.secondary)
                .font(.body)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Text(model.lastSaved)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isConnected ? Color.green : Color.secondary).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    (isConnected ? Color.green : Color.secondary).opacity(0.14),
                    lineWidth: 0.5
                )
        }
    }
}

private struct DirectoryChoiceRow: View {
    let title: String
    let value: String
    let isConfigured: Bool
    let action: () -> Void
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(Color.primary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                ConfigurationStatusIcon(isConfigured: isConfigured,
                                        readyHelp: "归档位置已选择",
                                        waitingHelp: "请选择归档位置")
            }

            HStack(spacing: 9) {
                Image(systemName: isConfigured ? "folder.fill" : "folder")
                    .foregroundStyle(isConfigured ? Color.accentColor : Color.orange)
                Text(value == "未选择" ? "请选择归档文件夹" : value)
                    .font(.callout)
                    .foregroundStyle(isConfigured ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: action) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(IconActionButtonStyle())
                .hoverHelp("选择或更换归档位置")
                .accessibilityLabel("选择或更换归档位置，当前：\(value)")
                .pointerCursor()

                if isConfigured {
                    Button(action: openAction) {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .foregroundStyle(.secondary)
                    .hoverHelp("在 Finder 中打开归档目录")
                    .accessibilityLabel("在 Finder 中打开归档目录")
                    .pointerCursor()
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 10)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConfigurationStatusIcon: View {
    let isConfigured: Bool
    let readyHelp: String
    let waitingHelp: String

    var body: some View {
        Image(systemName: isConfigured ? "checkmark.circle.fill" : "circle.dotted")
            .font(.caption)
            .foregroundStyle(isConfigured ? Color.green : Color.orange)
            .hoverHelp(isConfigured ? readyHelp : waitingHelp)
            .accessibilityLabel(isConfigured ? readyHelp : waitingHelp)
    }
}

private struct PrefixFocusDismissView: NSViewRepresentable {
    let isFocused: Bool
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.observeClicks(around: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isFocused = isFocused
        context.coordinator.dismiss = dismiss
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator {
        var isFocused = false
        var dismiss: (() -> Void)?
        private var monitor: Any?

        func observeClicks(around view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak view] event in
                guard let self, self.isFocused, let view, event.window === view.window else { return event }
                let inputBounds = view.convert(view.bounds, to: nil)
                if !inputBounds.contains(event.locationInWindow) {
                    DispatchQueue.main.async { [weak self] in self?.dismiss?() }
                }
                return event
            }
        }

        func stopObserving() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stopObserving() }
    }
}

private struct SidebarActionButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    private var tint: Color {
        role == .destructive ? .red : .primary
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 17)
                Text(title)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(SidebarActionButtonStyle(tint: tint))
        .accessibilityLabel(title)
        .pointerCursor()
    }
}

private struct ManifestIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 42, height: 36)
        }
        .buttonStyle(SidebarActionButtonStyle(tint: .primary))
        .hoverHelp(title)
        .accessibilityLabel(title)
        .pointerCursor()
    }
}

private struct ManifestPreviewSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("JSON 清单预览", systemImage: "curlybraces")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .pointerCursor()
            }
            .padding(16)

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .frame(minWidth: 620, minHeight: 480)
    }
}

private struct SidebarActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SidebarActionButtonChrome(tint: tint, isPressed: configuration.isPressed))
    }
}

private struct SidebarActionButtonChrome: ViewModifier {
    let tint: Color
    let isPressed: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(tint)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                tint.opacity(isPressed ? 0.18 : (isHovered ? 0.13 : 0.06)),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tint.opacity(isPressed || isHovered ? 0.2 : 0.1), lineWidth: 0.5)
            }
            .onHover { isHovered = $0 }
            .scaleEffect(isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct IconActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(IconActionButtonChrome(isPressed: configuration.isPressed))
    }
}

private struct IconActionButtonChrome: ViewModifier {
    let isPressed: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .frame(width: 30, height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isPressed ? 0.12 : (isHovered ? 0.075 : 0.025)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isPressed || isHovered ? 0.11 : 0.045), lineWidth: 0.5)
            }
            .onHover { isHovered = $0 }
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct AnchorHeaderMetric: View {
    let value: Int
    let label: String
    let shortLabel: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(shortLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
            Text(value, format: .number)
                .font(.caption.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .hoverHelp("\(label)：\(value)，\(detail)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)，\(detail)")
    }
}

private struct AnchorListView: View {
    @ObservedObject var model: AppModel
    @Binding var isSidebarVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if !isSidebarVisible {
                    Button { isSidebarVisible = true } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .hoverHelp("展开侧边栏")
                    .accessibilityLabel("展开侧边栏")
                    .pointerCursor()
                }
                Label("文案锚点", systemImage: "text.badge.checkmark")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    AnchorHeaderMetric(value: model.scriptCharacterCount, label: "文案字数", shortLabel: "字", detail: "含标点，不计空白", tint: .secondary)
                    AnchorHeaderMetric(value: model.aRollAnchorCount, label: "A-roll 锚点", shortLabel: "A", detail: "尚未绑定素材", tint: .blue)
                    AnchorHeaderMetric(value: model.bRollAnchorCount, label: "B-roll 锚点", shortLabel: "B", detail: "已绑定 \(model.assignedCount) 个素材", tint: .green)
                }
                Button { model.isScriptEditorPresented = true } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(IconActionButtonStyle())
                .hoverHelp("编辑或导入视频文案")
                .accessibilityLabel("编辑或导入视频文案")
                .pointerCursor()
            }
            .padding(.horizontal, 16)
            .frame(height: ListPaneMetrics.headerHeight)
            .overlay(alignment: .bottom) { Divider() }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索文案或 BR 编号", text: $model.anchorSearchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("搜索文案锚点")
                if !model.anchorSearchText.isEmpty {
                    Button {
                        model.anchorSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .hoverHelp("清除搜索")
                    .accessibilityLabel("清除搜索")
                    .pointerCursor()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(height: ListPaneMetrics.toolsHeight)
            .overlay(alignment: .bottom) {
                Divider()
            }

            if model.rows.isEmpty {
                ContentUnavailableView {
                    Label("先导入文案", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("每一行或每一句会变成一个 B-roll 投放位。")
                } actions: {
                    Button("编辑 / 导入文案") {
                        model.isScriptEditorPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .pointerCursor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredRows.isEmpty {
                ContentUnavailableView {
                    Label("没有匹配的文案", systemImage: "magnifyingglass")
                } description: {
                    Text("试试文案关键词或 BR 编号。")
                } actions: {
                    Button("清除搜索") {
                        model.anchorSearchText = ""
                    }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.filteredRows) { row in
                        AnchorRowView(row: row, model: model)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
                .overlay {
                    AnchorListDropOutline(feedback: model.dropFeedback)
                }
                .onDrop(of: [UTType.fileURL], delegate: AnchorListDropDelegate(feedback: model.dropFeedback))
            }
        }
        .background(.windowBackground)
    }
}

private struct AnchorListDropOutline: View {
    @ObservedObject var feedback: DropFeedbackModel

    var body: some View {
        Group {
            if feedback.isFileDragActive {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1.25)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct PaneHeader: View {
    let title: String
    let systemImage: String
    let count: String?
    let actions: [PaneHeaderAction]

    init(
        title: String,
        systemImage: String,
        count: String? = nil,
        actions: [PaneHeaderAction] = []
    ) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            ForEach(actions.indices, id: \.self) { index in
                let headerAction = actions[index]
                Button(action: headerAction.action) {
                    Image(systemName: headerAction.systemImage)
                }
                .buttonStyle(IconActionButtonStyle())
                .foregroundStyle(.secondary)
                .hoverHelp(headerAction.help)
                .accessibilityLabel(headerAction.accessibilityLabel)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: ListPaneMetrics.headerHeight)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct PaneHeaderAction {
    let systemImage: String
    let help: String
    let accessibilityLabel: String
    let action: () -> Void

    init(
        systemImage: String,
        help: String,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.help = help
        self.accessibilityLabel = accessibilityLabel ?? help
        self.action = action
    }
}

private struct AnchorRowView: View {
    let row: AnchorRow
    @ObservedObject var model: AppModel
    @StateObject private var dropState = AnchorDropState()

    private var assets: [BrollAsset] { model.assets(for: row.id) }
    private var isDropTarget: Bool { dropState.isActive }
    private var isAssigned: Bool { !assets.isEmpty }
    private var hasAvailableSource: Bool { assets.contains { model.sourceFile(for: $0) != nil } }
    private var rowFill: Color {
        if isDropTarget { return Color.accentColor.opacity(0.13) }
        return Color.primary.opacity(0.02)
    }

    private var rowBorder: Color {
        if isDropTarget { return Color.accentColor.opacity(0.78) }
        return Color.primary.opacity(0.08)
    }

    private var rowBorderWidth: CGFloat {
        isDropTarget ? 2 : 0.7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(format: "%02d", row.index))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isDropTarget ? Color.accentColor : Color.secondary)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("BR\(String(format: "%03d", row.index))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(isDropTarget ? Color.accentColor : Color.secondary.opacity(0.72))
                        Spacer(minLength: 8)
                        RollTypeTag(
                            isBroll: isAssigned,
                            assetCount: assets.count,
                            onTap: { model.explainARollTag() }
                        )
                    }
                    Text(row.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .hoverHelp("从素材目录或 Finder 拖入图片 / 视频，绑定到这条文案锚点")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: jumpToBoundSource)

            if !assets.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(assets) { asset in
                        AssetChip(
                            asset: asset,
                            model: model,
                            isDropTarget: isDropTarget,
                            isSelected: model.selectedSourceFileURL?.lastPathComponent == asset.sourceName
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture(perform: jumpToBoundSource)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: rowBorderWidth)
        }
        .onDrop(
            of: [UTType.fileURL],
            delegate: FileDropDelegate(rowID: row.id, model: model, feedback: model.dropFeedback, rowState: dropState)
        )
        .pointerCursor(hasAvailableSource ? .pointingHand : .arrow)
        .animation(.snappy(duration: 0.2), value: assets.count)
    }

    private func jumpToBoundSource() {
        let selectedName = model.selectedSourceFileURL?.lastPathComponent
        let availableAssets = assets.filter { model.sourceFile(for: $0) != nil }
        guard let asset = availableAssets.first(where: { $0.sourceName == selectedName }) ?? availableAssets.first else { return }
        model.jumpToSourceFile(for: asset)
    }
}

private struct RollTypeTag: View {
    let isBroll: Bool
    let assetCount: Int
    let onTap: () -> Void

    private var tint: Color { isBroll ? .green : .accentColor }

    var body: some View {
        if isBroll {
            tag
        } else {
            Button(action: onTap) {
                tag
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    private var tag: some View {
        HStack(spacing: 4) {
            Image(systemName: isBroll ? "film" : "waveform")
            Text(isBroll ? "B-roll" : "A-roll")
            if isBroll, assetCount > 1 {
                Text("×\(assetCount)")
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.1), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(0.2), lineWidth: 0.6)
        }
        .hoverHelp(isBroll
            ? "已绑定 \(assetCount) 个视频或图片，文件已复制到归档目录"
            : "点击查看 A-roll 说明和绑定方法"
        )
        .accessibilityLabel(isBroll ? "B-roll，已绑定 \(assetCount) 个素材" : "A-roll，尚未绑定 B-roll 素材")
    }
}

private struct AssetChip: View {
    let asset: BrollAsset
    @ObservedObject var model: AppModel
    let isDropTarget: Bool
    let isSelected: Bool
    @State private var isUnbindConfirmationPresented = false

    private var mediaSymbol: String {
        let ext = URL(fileURLWithPath: asset.sourceName).pathExtension.lowercased()
        return AppModel.imageExtensions.contains(ext) ? "photo" : "film"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.jumpToSourceFile(for: asset)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: mediaSymbol)
                        .foregroundStyle(isSelected ? Color.orange : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.outputName)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("源文件：\(asset.sourceName)")
                            .font(.caption2)
                            .foregroundStyle(isSelected ? Color.orange : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.sourceFile(for: asset) == nil)
            .hoverHelp("归档名：\(asset.outputName)\n\n完整媒体文件名：\(asset.sourceName)")
            .accessibilityLabel("定位源文件 \(asset.sourceName)")
            .pointerCursor(model.sourceFile(for: asset) == nil ? .arrow : .pointingHand)

            Button {
                isUnbindConfirmationPresented = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(IconActionButtonStyle())
            .foregroundStyle(.secondary)
            .hoverHelp("取消绑定并删除归档副本；原始素材保留")
            .accessibilityLabel("取消绑定并删除归档副本 \(asset.sourceName)")
            .pointerCursor()
            .confirmationDialog(
                "取消绑定这个素材？",
                isPresented: $isUnbindConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("删除归档副本并取消绑定", role: .destructive) {
                    model.unbind(asset)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("归档副本将被删除，素材目录中的原始文件会保留。")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isSelected
                ? Color.orange.opacity(0.17)
                : (isDropTarget ? Color.accentColor.opacity(0.09) : Color.green.opacity(0.055)),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.orange.opacity(0.85) : Color.green.opacity(0.18),
                    lineWidth: isSelected ? 1.5 : 0.6
                )
        }
        .contextMenu {
            Button {
                model.reveal(asset)
            } label: {
                Label("在 Finder 中显示", systemImage: "magnifyingglass")
            }
        }
    }
}

private struct MaterialListHeader: View {
    @ObservedObject var model: AppModel
    @Binding var isDirectoryPopoverPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "素材列表",
                systemImage: "film.stack",
                count: "\(model.visibleSourceFiles.count) 个素材",
                actions: [
                    PaneHeaderAction(systemImage: "arrow.clockwise", help: "刷新素材列表") {
                        model.refreshSourceFiles()
                    }
                ]
            )

            HStack(spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: model.sourceDirectoryURL == nil ? "folder" : "folder.fill")
                        .foregroundStyle(model.sourceDirectoryURL == nil ? Color.orange : Color.accentColor)
                    Text(model.sourceDirectoryURL == nil ? "未选择目录" : model.sourceDirectoryName)
                        .font(.callout)
                        .foregroundStyle(model.sourceDirectoryURL == nil ? Color.orange : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)
                        .hoverHelp(model.sourceDirectoryURL?.path ?? "尚未选择素材来源")
                    Button {
                        model.chooseSourceDirectory()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .hoverHelp(model.sourceDirectoryURL == nil ? "选择素材来源目录" : "更换素材来源目录")
                    .accessibilityLabel(model.sourceDirectoryURL == nil ? "选择素材来源目录" : "更换素材来源目录")
                    .pointerCursor()

                    Button {
                        isDirectoryPopoverPresented = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .hoverHelp("管理常用素材目录")
                    .accessibilityLabel("管理常用素材目录")
                    .pointerCursor()
                    .popover(isPresented: $isDirectoryPopoverPresented, arrowEdge: .trailing) {
                        DirectoryManagerPopover(model: model) {
                            isDirectoryPopoverPresented = false
                        }
                        .frame(width: 310)
                    }
                }
                .frame(height: 40)
                .padding(.horizontal, 10)
                .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
                }

                Divider()
                    .frame(height: 24)

                MediaFilterPicker(selection: $model.mediaFilter)
            }
            .padding(.horizontal, 16)
            .frame(height: ListPaneMetrics.toolsHeight)
            .background(.quaternary.opacity(0.2))
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}

private struct DirectoryManagerPopover: View {
    @ObservedObject var model: AppModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("素材目录", systemImage: "folder.badge.gearshape")
                    .font(.headline)
                Spacer()
                if model.sourceDirectoryURL != nil && !model.isCurrentSourceDirectorySaved {
                    Button {
                        model.saveCurrentSourceDirectory()
                    } label: {
                        Label("收藏当前", systemImage: "bookmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.caption)
                    .accessibilityLabel("收藏当前素材目录")
                    .hoverHelp("将当前目录加入常用目录")
                    .pointerCursor()
                }
            }

            DirectoryPopoverAction(title: "选择素材目录…", systemImage: "folder.badge.plus", isPrimary: true) {
                model.chooseSourceDirectory()
                dismiss()
            }

            if model.sourceDirectoryURL != nil {
                DirectoryPopoverAction(title: "在 Finder 中打开当前目录", systemImage: "arrow.up.forward.app") {
                    model.revealSourceDirectory()
                    dismiss()
                }
            }

            DirectoryPopoverAction(title: "选择并收藏新目录…", systemImage: "bookmark") {
                model.chooseAndSaveSourceDirectory()
                dismiss()
            }

            Divider()

            Text("常用目录")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if model.savedDirectories.isEmpty {
                Text("收藏目录后，可从这里快速切换。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(model.savedDirectories) { directory in
                            SavedDirectoryRow(
                                directory: directory,
                                isSelected: directory.path == model.sourceDirectoryURL?.standardizedFileURL.path,
                                select: {
                                    model.selectSavedDirectory(directory.id)
                                    dismiss()
                                },
                                remove: { model.removeSavedDirectory(directory.id) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(CGFloat(model.savedDirectories.count) * 36, 220))
                .background(OverlayScrollerStyleInstaller().allowsHitTesting(false).accessibilityHidden(true))
            }
        }
        .padding(14)
    }
}

private struct DirectoryPopoverAction: View {
    let title: String
    let systemImage: String
    var isPrimary = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: 20)
                Text(title)
                    .font(.callout.weight(isPrimary ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                isPrimary ? Color.accentColor.opacity(isHovered ? 0.16 : 0.10) : Color.primary.opacity(isHovered ? 0.08 : 0.035),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPrimary ? Color.accentColor : Color.primary)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}

private struct SavedDirectoryRow: View {
    let directory: SavedDirectory
    let isSelected: Bool
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "folder")
                        .foregroundStyle(isSelected ? Color.green : Color.secondary)
                    Text(directory.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if isSelected {
                        Text("当前")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHelp("切换到素材目录：\(directory.name)")
            .accessibilityLabel("切换素材目录：\(directory.name)")
            .pointerCursor()

            Menu {
                Button("移除常用目录", systemImage: "trash", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
                    .modifier(IconActionButtonChrome(isPressed: false))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .hoverHelp("管理常用目录")
            .accessibilityLabel("管理常用目录")
            .pointerCursor()
        }
        .background(isSelected ? Color.green.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct DetailView: View {
    @ObservedObject var model: AppModel
    @State private var selectedSourceFileURLs: Set<URL> = []
    @State private var isDirectoryPopoverPresented = false
    @FocusState private var isMaterialListFocused: Bool
    @StateObject private var previewController = MediaPreviewController()

    private var selectedSourceFileURL: URL? {
        selectedSourceFileURLs.first
    }

    var body: some View {
        let visibleFiles = model.visibleSourceFiles

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                MaterialListHeader(model: model, isDirectoryPopoverPresented: $isDirectoryPopoverPresented)

                if visibleFiles.isEmpty {
                    ContentUnavailableView {
                        Label("还没有素材", systemImage: "film")
                    } description: {
                        Text(model.sourceDirectoryURL == nil ? "选择素材目录" : "没有符合条件的素材")
                    } actions: {
                        Button("选择素材目录") {
                            model.chooseSourceDirectory()
                        }
                        .buttonStyle(.bordered)
                        .pointerCursor()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geometry in
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(visibleFiles.enumerated()), id: \.element.id) { index, file in
                                        SourceFileRow(
                                            file: file,
                                            index: index + 1,
                                            model: model,
                                            isAssigned: model.isAssigned(file),
                                            isSelected: selectedSourceFileURLs.contains(file.url)
                                        )
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 4)
                                        .id(file.url.standardizedFileURL.path)
                                        .onTapGesture {
                                            selectSourceFile(file)
                                        }

                                        if index < visibleFiles.count - 1 {
                                            Divider()
                                                .padding(.leading, 174)
                                                .padding(.trailing, 16)
                                        }
                                    }
                                }
                                .frame(width: geometry.size.width)
                                .background(alignment: .topLeading) {
                                    MaterialScrollbarInstaller()
                                        .frame(width: 1, height: 1)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                            .scrollIndicators(.hidden)
                            .contentMargins(.trailing, 0, for: .scrollContent)
                            .task(id: model.sourceFileJumpID) {
                                guard model.sourceFileJumpID != nil,
                                      let url = model.selectedSourceFileURL,
                                      let file = visibleFiles.first(where: { $0.url == url }) else { return }
                                selectSourceFile(file)
                                await Task.yield()
                                guard !Task.isCancelled else { return }
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(file.url.standardizedFileURL.path, anchor: .center)
                                }
                            }
                            .focusable()
                            .focused($isMaterialListFocused)
                            .focusEffectDisabled()
                            .onKeyPress(keys: [.upArrow, .downArrow, .space]) { keyPress in
                                switch keyPress.key {
                                case .upArrow:
                                    if let url = moveSelection(by: -1) {
                                        proxy.scrollTo(url.standardizedFileURL.path, anchor: .center)
                                    }
                                    return .handled
                                case .downArrow:
                                    if let url = moveSelection(by: 1) {
                                        proxy.scrollTo(url.standardizedFileURL.path, anchor: .center)
                                    }
                                    return .handled
                                case .space:
                                    guard selectedSourceFileURL != nil else { return .ignored }
                                    previewController.togglePlayback()
                                    return .handled
                                default:
                                    return .ignored
                                }
                            }
                        }
                    }
                }

            }
            .frame(minWidth: 420, idealWidth: 440, maxWidth: .infinity)

            Divider()

            MediaPreviewView(
                file: selectedSourceFileURL.flatMap(model.sourceFile(at:)),
                controller: previewController
            )
            .frame(minWidth: 340, idealWidth: 480, maxWidth: .infinity)
        }
        .background(.windowBackground)
        .onChange(of: model.sourceFiles) { _, files in
            let availableURLs = Set(files.map(\.url))
            selectedSourceFileURLs = selectedSourceFileURLs.intersection(availableURLs)
            model.selectedSourceFileURL = selectedSourceFileURLs.first
        }
        .onChange(of: selectedSourceFileURLs) { _, urls in
            model.selectedSourceFileURL = urls.first
        }
    }

    private func selectSourceFile(_ file: SourceFile) {
        selectedSourceFileURLs = [file.url]
        model.selectedSourceFileURL = file.url
        if file.kind == .video {
            previewController.play(url: file.url)
        } else {
            previewController.load(url: nil)
        }
        isMaterialListFocused = true
    }

    private func moveSelection(by offset: Int) -> URL? {
        let visibleFiles = model.visibleSourceFiles
        guard !visibleFiles.isEmpty else { return nil }

        let currentIndex = selectedSourceFileURL.flatMap { selectedURL in
            visibleFiles.firstIndex { $0.url == selectedURL }
        }

        let targetIndex: Int
        if let currentIndex {
            targetIndex = min(max(currentIndex + offset, 0), visibleFiles.count - 1)
        } else {
            targetIndex = offset < 0 ? visibleFiles.count - 1 : 0
        }

        let file = visibleFiles[targetIndex]
        selectSourceFile(file)
        return file.url
    }
}

private struct MediaFilterPicker: View {
    @Binding var selection: MediaFilter

    var body: some View {
        Picker("素材类型", selection: $selection) {
            ForEach(MediaFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.systemImage)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(width: 156, height: 40)
        .hoverHelp("筛选素材类型")
        .pointerCursor()
    }
}

private struct MediaPreviewView: View {
    let file: SourceFile?
    @ObservedObject var controller: MediaPreviewController

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "当前媒体",
                systemImage: file?.kind.systemImage ?? "play.rectangle",
                count: file == nil ? "未选择" : nil
            )

            HStack(spacing: 8) {
                if let file {
                    Image(systemName: file.kind.systemImage)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .hoverHelp(file.name)
                        Text(MediaFormatting.bytes(file.byteCount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button {
                        QuickLookPreviewController.shared.preview(url: file.url)
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .hoverHelp("使用 Quick Look 打开素材")
                    .accessibilityLabel("使用 Quick Look 打开素材")
                    .pointerCursor()

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .hoverHelp("在 Finder 中显示素材")
                    .accessibilityLabel("在 Finder 中显示素材")
                    .pointerCursor()
                } else {
                    Text("从素材列表选择文件")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .frame(height: ListPaneMetrics.toolsHeight)
            .background(.quaternary.opacity(0.2))
            .overlay(alignment: .bottom) {
                Divider()
            }

            if let file {
                if file.kind == .image {
                    ImagePreviewContent(file: file)
                } else {
                    NativePlayerView(player: controller.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.separator.opacity(0.75), lineWidth: 0.5)
                    }
                    .padding(16)
                    .background(.windowBackground)
                    .onChange(of: file.url) { _, url in
                        controller.load(url: url)
                    }
                    .onAppear {
                        controller.load(url: file.url)
                    }
                    .onDisappear {
                        controller.pause()
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("选择素材", systemImage: "play.rectangle")
                } description: {
                    Text("从素材列表选择")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.windowBackground)
    }
}

private struct ImagePreviewContent: View {
    let file: SourceFile
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.12))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .task(id: file.cacheIdentity) {
            image = nil
            image = await ImageThumbnailLoader.image(for: file, maxPixelSize: 2048)
        }
    }
}

private struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

private final class MediaPreviewController: ObservableObject {
    let player = AVPlayer()

    @Published private(set) var isPlaying = false

    private var currentURL: URL?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var hasReachedEnd = false

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.syncPlayingState()
        }
    }

    func load(url: URL?) {
        guard currentURL != url else { return }
        currentURL = url
        hasReachedEnd = false
        pause()
        player.replaceCurrentItem(with: url.map(AVPlayerItem.init(url:)))

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        if let item = player.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.isPlaying = false
                self?.hasReachedEnd = true
            }
        }
    }

    func play(url: URL) {
        load(url: url)
        guard player.currentItem != nil else { return }
        if hasReachedEnd {
            player.seek(to: .zero)
            hasReachedEnd = false
        }
        player.play()
        isPlaying = true
    }

    func togglePlayback() {
        guard player.currentItem != nil else { return }

        if player.timeControlStatus == .playing || player.rate != 0 {
            pause()
        } else if let currentURL {
            play(url: currentURL)
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    private func syncPlayingState() {
        let playing = player.timeControlStatus == .playing || player.rate != 0
        if isPlaying != playing {
            isPlaying = playing
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }
}

private struct SourceFileRow: View {
    let file: SourceFile
    let index: Int
    @ObservedObject var model: AppModel
    let isAssigned: Bool
    let isSelected: Bool

    private var assignedAssets: [BrollAsset] {
        model.assignedAssets(forSourceName: file.name)
    }

    private var hoverDetails: String {
        let archiveNames = assignedAssets.map(\.outputName)
        let archiveLines = archiveNames.isEmpty
            ? "归档名：未归档"
            : archiveNames.map { "归档名：\($0)" }.joined(separator: "\n\n")
        return "\(archiveLines)\n\n完整媒体文件名：\(file.name)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%03d", index))
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)

            MediaThumbnailView(file: file)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? Color.orange : Color.primary)
                Text(isAssigned ? "已绑定" : MediaFormatting.bytes(file.byteCount))
                    .font(.caption2)
                    .foregroundStyle(isAssigned ? .green : .secondary)
            }
            Spacer(minLength: 5)
            if isAssigned {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(isSelected ? Color.orange : Color.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.orange.opacity(0.17) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.orange.opacity(0.8) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onDrag {
            return NSItemProvider(object: file.url as NSURL)
        }
        .pointerCursor()
        .hoverHelp(hoverDetails)
        .accessibilityValue(isSelected ? "已选中" : "未选中")
    }
}

private struct HoverHelpModifier: ViewModifier {
    let text: String

    @State private var isHovering = false
    @State private var isTooltipVisible = false
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background {
                HoverTooltipPopoverHost(text: wrappedText, isPresented: isTooltipVisible)
                    .allowsHitTesting(false)
            }
            .accessibilityHint(Text(text))
            .onHover { hovering in
                showTask?.cancel()
                isHovering = hovering

                guard hovering else {
                    isTooltipVisible = false
                    return
                }

                showTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        return
                    }
                    guard isHovering else { return }
                    isTooltipVisible = true
                }
            }
            .onDisappear {
                showTask?.cancel()
                isHovering = false
                isTooltipVisible = false
            }
    }

    private var wrappedText: String {
        let maxLineWidth: CGFloat = 360
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]

        return text.components(separatedBy: "\n").flatMap { paragraph -> [String] in
            guard !paragraph.isEmpty else { return [""] }

            var wrappedLines: [String] = []
            var currentLine = ""
            for character in paragraph {
                let candidate = currentLine + String(character)
                if !currentLine.isEmpty,
                   (candidate as NSString).size(withAttributes: attributes).width > maxLineWidth {
                    wrappedLines.append(currentLine)
                    currentLine = String(character)
                } else {
                    currentLine = candidate
                }
            }
            wrappedLines.append(currentLine)
            return wrappedLines
        }
        .joined(separator: "\n")
    }
}

private struct HoverTooltipPopoverHost: NSViewRepresentable {
    let text: String
    let isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HoverTooltipAnchorView {
        let view = HoverTooltipAnchorView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ view: HoverTooltipAnchorView, context: Context) {
        context.coordinator.update(text: text, isPresented: isPresented, anchorView: view)
    }

    fileprivate static func dismantleNSView(_ view: HoverTooltipAnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    fileprivate final class Coordinator {
        weak var anchorView: NSView?
        private var popover: NSPopover?
        private var presentedText: String?

        func update(text: String, isPresented: Bool, anchorView: NSView) {
            self.anchorView = anchorView
            guard isPresented else {
                close()
                return
            }

            show(text: text, from: anchorView)
        }

        func show(text: String, from anchorView: NSView) {
            guard let window = anchorView.window else { return }

            let popover: NSPopover
            if let existing = self.popover {
                popover = existing
            } else {
                let created = NSPopover()
                created.behavior = .transient
                created.animates = false
                self.popover = created
                popover = created
            }

            if presentedText != text || popover.contentViewController == nil {
                let controller = NSHostingController(rootView: HoverTooltip(text: text))
                popover.contentViewController = controller
                popover.contentSize = HoverTooltip.preferredSize(for: text)
                presentedText = text
            }

            guard !popover.isShown else { return }

            let mouseLocation = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: mouseLocation)
            let anchorPoint = anchorView.convert(windowPoint, from: nil)
            let anchorRect = NSRect(x: anchorPoint.x, y: anchorPoint.y, width: 1, height: 1)
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? window.screen
            let edge = preferredEdge(
                around: mouseLocation,
                popoverSize: popover.contentSize,
                visibleFrame: screen?.visibleFrame ?? window.frame
            )

            popover.show(relativeTo: anchorRect, of: anchorView, preferredEdge: edge)
        }

        private func preferredEdge(around point: NSPoint, popoverSize: CGSize, visibleFrame: NSRect) -> NSRectEdge {
            let safeFrame = visibleFrame.insetBy(dx: 12, dy: 12)
            let roomOnRight = safeFrame.maxX - point.x
            let roomOnLeft = point.x - safeFrame.minX
            if roomOnRight >= popoverSize.width + 18 { return .maxX }
            if roomOnLeft >= popoverSize.width + 18 { return .minX }

            let roomBelow = point.y - safeFrame.minY
            let roomAbove = safeFrame.maxY - point.y
            if roomBelow >= popoverSize.height + 18 { return .minY }
            if roomAbove >= popoverSize.height + 18 { return .maxY }
            return roomBelow >= roomAbove ? .minY : .maxY
        }

        func close() {
            if popover?.isShown == true {
                popover?.performClose(nil)
            }
            presentedText = nil
        }
    }
}

private final class HoverTooltipAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct HoverTooltip: View {
    let text: String

    private static let maximumTextWidth: CGFloat = 360

    static func preferredSize(for text: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: 13)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: maximumTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).size

        let width = min(380, max(160, ceil(measured.width) + 20))
        let height = max(38, ceil(measured.height) + 20)
        return CGSize(width: width, height: height)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(2)
            .frame(width: Self.preferredSize(for: text).width - 20, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(
                width: Self.preferredSize(for: text).width,
                height: Self.preferredSize(for: text).height,
                alignment: .leading
            )
    }
}

private struct PointerCursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isCursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                guard isCursorPushed != isHovering else { return }
                isCursorPushed = isHovering
                if isHovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
    }
}

private extension View {
    func hoverHelp(_ text: String) -> some View {
        modifier(HoverHelpModifier(text: text))
    }

    func pointerCursor(_ cursor: NSCursor = .pointingHand) -> some View {
        modifier(PointerCursorModifier(cursor: cursor))
    }
}

private final class QuickLookPreviewController: NSResponder, QLPreviewPanelDataSource {
    static let shared = QuickLookPreviewController()

    private var previewURL: URL?
    private weak var hostWindow: NSWindow?
    private weak var originalNextResponder: NSResponder?

    func preview(url: URL) {
        previewURL = url

        if let window = NSApp.keyWindow {
            if hostWindow !== window {
                hostWindow = window
                originalNextResponder = window.nextResponder
                window.nextResponder = self
            }
        }

        NSApp.activate(ignoringOtherApps: true)

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }

        if let hostWindow, hostWindow.nextResponder === self {
            hostWindow.nextResponder = originalNextResponder
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        previewURL! as NSURL
    }
}

private struct MediaThumbnailView: View {
    let file: SourceFile

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?
    @State private var isLoading = true

    private let thumbnailSize = CGSize(width: 92, height: 56)

    var body: some View {
        let maxPixelSize = max(1, Int(ceil(max(thumbnailSize.width, thumbnailSize.height) * displayScale)))

        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()

                if file.kind == .video {
                    LinearGradient(
                        colors: [.black.opacity(0.45), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )

                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(6)
                }
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary)
                Image(systemName: isLoading ? "hourglass" : file.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(5)
                }
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.separator.opacity(0.65), lineWidth: 0.5)
        }
        .accessibilityLabel("\(file.kind.title)缩略图")
        .task(id: "\(file.cacheIdentity)|\(maxPixelSize)") {
            isLoading = true
            image = nil
            if file.kind == .image {
                image = await ImageThumbnailLoader.image(for: file, maxPixelSize: maxPixelSize)
            } else {
                image = await VideoThumbnailLoader.image(for: file, maxPixelSize: maxPixelSize)
            }
            if !Task.isCancelled {
                isLoading = false
            }
        }
    }
}

private final class MediaThumbnailCache {
    static let shared = MediaThumbnailCache()

    private let cache = NSCache<NSString, CGImage>()

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func image(for key: String) -> CGImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: CGImage, for key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: max(1, cost))
    }
}

@MainActor
private enum ImageThumbnailLoader {
    static func image(for file: SourceFile, maxPixelSize: Int) async -> NSImage? {
        let pixelSize = max(1, maxPixelSize)
        let key = "\(file.cacheIdentity)|\(pixelSize)"
        if let cached = MediaThumbnailCache.shared.image(for: key) {
            return NSImage(cgImage: cached, size: .zero)
        }

        let url = file.url
        let worker = Task.detached(priority: .utility) { () -> (CGImage, Int)? in
            guard !Task<Never, Never>.isCancelled,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }

            return (cgImage, cgImage.bytesPerRow * cgImage.height)
        }

        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        guard !Task<Never, Never>.isCancelled, let (cgImage, cost) = result else { return nil }
        MediaThumbnailCache.shared.insert(cgImage, for: key, cost: cost)
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

@MainActor
private enum VideoThumbnailLoader {
    static func image(for file: SourceFile, maxPixelSize: Int) async -> NSImage? {
        let pixelSize = max(1, maxPixelSize)
        let key = "\(file.cacheIdentity)|\(pixelSize)"
        if let cached = MediaThumbnailCache.shared.image(for: key) {
            return NSImage(cgImage: cached, size: .zero)
        }

        let url = file.url
        let asset = AVURLAsset(url: url)
        let loadedDuration = try? await asset.load(.duration)
        guard !Task<Never, Never>.isCancelled else { return nil }
        let duration = loadedDuration.map(CMTimeGetSeconds) ?? .nan
        let sampleSeconds: Double
        if duration.isFinite, duration > 0 {
            sampleSeconds = min(max(duration * 0.12, 0.05), 1.0)
        } else {
            sampleSeconds = 0.5
        }

        let requestedTime = CMTime(seconds: sampleSeconds, preferredTimescale: 600)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixelSize, height: pixelSize)

        let cgImage: CGImage
        do {
            (cgImage, _) = try await generator.image(at: requestedTime)
        } catch {
            return nil
        }
        let cost = cgImage.bytesPerRow * cgImage.height
        MediaThumbnailCache.shared.insert(cgImage, for: key, cost: cost)
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

private struct ScriptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $model.scriptText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    }

                HStack {
                    Picker("拆分方式", selection: $model.splitMode) {
                        ForEach(SplitMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    .pointerCursor()

                    Spacer()

                    Text("当前生成 \(model.rows.count) 个锚点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                HStack {
                    Button {
                        model.importScript()
                    } label: {
                        Label("导入 .txt / .md", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .pointerCursor()

                    Text("一行一个锚点；句号模式会按中文和英文句末标点拆分。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .navigationTitle("编辑 / 导入文案")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        model.parseScript()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .pointerCursor()
                }
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .onChange(of: model.scriptText) { _, _ in
            model.parseScript()
        }
        .onChange(of: model.splitMode) { _, _ in
            model.parseScript()
        }
    }
}
