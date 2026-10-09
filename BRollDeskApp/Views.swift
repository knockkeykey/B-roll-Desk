import AppKit
import AVKit
import AVFoundation
import Charts
import ImageIO
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

enum WindowHeaderMetrics {
    static let height: CGFloat = 70
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragRegionView {
        WindowDragRegionView()
    }

    func updateNSView(_ nsView: WindowDragRegionView, context: Context) {}
}

private final class WindowDragRegionView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private enum ListPaneMetrics {
    static let minimumAnchorWidth: CGFloat = 500
    static let headerHeight: CGFloat = WindowHeaderMetrics.height
    static let toolsHeight: CGFloat = 54
    static let anchorToolsHeight: CGFloat = toolsHeight
    static let scriptTimelineHeight: CGFloat = 96
}

private enum WorkspacePaneMetrics {
    static let minimumSidebarWidth: CGFloat = 270
    static let minimumSourceWidth: CGFloat = 340
    static let minimumPreviewWidth: CGFloat = 280
    static let dividerWidth: CGFloat = 8

    static let minimumDetailWidth = minimumSourceWidth + minimumPreviewWidth + dividerWidth
}

private struct WorkflowHelpStep: Identifiable {
    let number: Int
    let title: String
    let instruction: String

    var id: Int { number }
}

private struct WorkflowHelpPopover: View {
    private let steps = [
        WorkflowHelpStep(number: 1, title: "写文案", instruction: "完成这期口播文案，后续 A-roll 剪辑以它为准。"),
        WorkflowHelpStep(number: 2, title: "录制口播（A-roll）", instruction: "录制本期视频的口播。"),
        WorkflowHelpStep(number: 3, title: "准备配对项目", instruction: "选择剪辑项目文件夹，导入文案并按换行拆分；B-roll命名前缀可选填。"),
        WorkflowHelpStep(number: 4, title: "标记需要 B-roll 的文案", instruction: "逐条切换为 B-roll，选择制作方式，并在备注里记下制作提示、搜索词或生成要求。"),
        WorkflowHelpStep(number: 5, title: "准备 B-roll 素材", instruction: "对照待准备列表实拍、制作动画、生成视频或整理图片与现成素材。"),
        WorkflowHelpStep(number: 6, title: "打开素材目录", instruction: "在素材列表中打开刚才整理好的 B-roll 素材目录。"),
        WorkflowHelpStep(number: 7, title: "绑定对应素材", instruction: "把每条 B-roll 文案与素材列表中的对应项目拖拽绑定；绑定后会自动复制到剪辑项目文件夹。"),
        WorkflowHelpStep(number: 8, title: "检查剪辑项目文件夹", instruction: "确认里面有按规则命名的 B-roll 素材，以及文案与素材映射关系对照表。"),
        WorkflowHelpStep(number: 9, title: "把 A-roll 放进项目", instruction: "在左侧项目设置里点击“上传 A-roll”选择视频，或把视频拖到该按钮上。项目副本会放入 A-roll 文件夹并命名为 A-roll；原视频保留。"),
        WorkflowHelpStep(number: 10, title: "交给 AI 剪辑", instruction: "把整个剪辑项目文件夹交给 AI，按文案剪辑 A-roll，并按对照表插入 B-roll。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("粗剪流程")
                        .font(.system(size: 18, weight: .semibold))
                    Text("从文案准备到交给 AI 剪辑")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(step.number))
                                .font(.custom("SmileySans-Oblique", size: 15).weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 25, height: 25)
                                .background(Color.accentColor.opacity(0.1), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(step.instruction)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)

                        if step.number != steps.last?.number {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 480, height: 620)
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @StateObject private var folderDragFeedback = FolderDragFeedbackModel()
    @AppStorage("broll-namer-theme") private var themeRawValue = AppTheme.system.rawValue
    @State private var isSidebarVisible = true
    @State private var isSidebarMounted = true
    @State private var isMaterialListVisible = false
    @State private var isMediaPreviewVisible = false
    @State private var isWindowFullscreen = false

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

    private var sidebarVisibility: Binding<Bool> {
        Binding(
            get: { isSidebarVisible },
            set: { setSidebarVisible($0) }
        )
    }

    private var materialListVisibility: Binding<Bool> {
        Binding(
            get: { isMaterialListVisible },
            set: { isVisible in
                if !isVisible { isMediaPreviewVisible = false }
                isMaterialListVisible = isVisible
            }
        )
    }

    private var mediaPreviewVisibility: Binding<Bool> {
        Binding(
            get: { isMaterialListVisible && isMediaPreviewVisible },
            set: { isMediaPreviewVisible = isMaterialListVisible && $0 }
        )
    }

    private var minimumDetailWidth: CGFloat {
        guard isMaterialListVisible else { return 0 }
        return isMediaPreviewVisible
            ? WorkspacePaneMetrics.minimumDetailWidth
            : WorkspacePaneMetrics.minimumSourceWidth
    }

    private var minimumContentWidth: CGFloat {
        let sidebarWidth: CGFloat = isSidebarVisible ? WorkspacePaneMetrics.minimumSidebarWidth : 0
        let detailWidth = minimumDetailWidth
        let outerDividerCount: CGFloat = isSidebarMounted ? 2 : 1
        return sidebarWidth + ListPaneMetrics.minimumAnchorWidth + detailWidth
            + outerDividerCount * WorkspacePaneMetrics.dividerWidth
    }

    private func setSidebarVisible(_ isVisible: Bool) {
        guard isVisible != isSidebarVisible else { return }

        if isVisible {
            isSidebarMounted = true
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.24)) {
                    isSidebarVisible = true
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.24)) {
                isSidebarVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                if !isSidebarVisible {
                    isSidebarMounted = false
                }
            }
        }
    }

    var body: some View {
        HSplitView {
            if isSidebarMounted {
                SidebarView(model: model, themeRawValue: $themeRawValue, isSidebarVisible: sidebarVisibility)
                    .frame(
                        minWidth: isSidebarVisible ? WorkspacePaneMetrics.minimumSidebarWidth : 0,
                        idealWidth: isSidebarVisible ? 300 : 0,
                        maxWidth: isSidebarVisible ? 360 : 0
                    )
                    .opacity(isSidebarVisible ? 1 : 0)
                    .clipped()
                    .allowsHitTesting(isSidebarVisible)
                    .accessibilityHidden(!isSidebarVisible)
                    .animation(.easeInOut(duration: 0.24), value: isSidebarVisible)
            }
            AnchorListView(
                model: model,
                isSidebarVisible: sidebarVisibility,
                isMaterialListVisible: materialListVisibility
            )
                .frame(minWidth: ListPaneMetrics.minimumAnchorWidth, idealWidth: 760,
                       maxWidth: isMaterialListVisible ? 760 : .infinity)
                .background(SplitViewAutosaveInstaller(
                    name: isSidebarMounted
                        ? "com.keyknock.BrollNamer.main-columns-v3-with-sidebar"
                        : "com.keyknock.BrollNamer.main-columns-v3-without-sidebar"
                ))
            DetailView(
                model: model,
                isMaterialListVisible: materialListVisibility,
                isMediaPreviewVisible: mediaPreviewVisibility
            )
                .frame(minWidth: minimumDetailWidth, idealWidth: isMaterialListVisible ? 820 : 0,
                       maxWidth: isMaterialListVisible ? .infinity : 0)
                .allowsHitTesting(isMaterialListVisible)
                .accessibilityHidden(!isMaterialListVisible)
        }
        .onDrop(of: [UTType.fileURL], delegate: WholeWindowDirectoryDropDelegate(feedback: folderDragFeedback))
        .environmentObject(folderDragFeedback)
        .frame(minWidth: minimumContentWidth)
        .padding(.top, isWindowFullscreen ? 0 : -28)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowFullscreenObserver(isFullscreen: $isWindowFullscreen))
        .sheet(isPresented: $model.isScriptEditorPresented) {
            ScriptEditorSheet(model: model)
        }
        .sheet(isPresented: $model.isAnimationPanelPresented) {
            AnimationWorkspaceView(model: model)
        }
        .sheet(isPresented: $model.isManifestPreviewPresented) {
            ManifestPreviewSheet(text: model.manifestPreviewText)
        }
        .alert(item: $model.alert) { alert in
            return Alert(
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
            Text("将删除当前剪辑项目文件夹中已绑定及符合命名规则的旧素材副本，并更新 JSON 和 Markdown 对照表。素材目录中的原始文件会保留。")
        }
        .preferredColorScheme(preferredColorScheme)
        .font(.system(size: 16))
    }
}

// The hidden title bar needs compensation in a window, but not in full screen.
private struct WindowFullscreenObserver: NSViewRepresentable {
    @Binding var isFullscreen: Bool

    func makeNSView(context: Context) -> WindowFullscreenObserverView {
        let view = WindowFullscreenObserverView()
        view.onChange = { isFullscreen = $0 }
        return view
    }

    func updateNSView(_ view: WindowFullscreenObserverView, context: Context) {
        view.onChange = { isFullscreen = $0 }
    }
}

private final class WindowFullscreenObserverView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { return }
        reportFullscreenState()
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                self?.reportFullscreenState()
            })
        }
    }

    private func reportFullscreenState() {
        guard let window else { return }
        let isFullscreen = window.styleMask.contains(.fullScreen)
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(isFullscreen)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

private struct SplitViewAutosaveInstaller: NSViewRepresentable {
    let name: String

    final class Coordinator {
        weak var splitView: NSSplitView?
        var isScheduling = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        installWhenAttached(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        installWhenAttached(view, coordinator: context.coordinator)
    }

    private func installWhenAttached(_ view: NSView, coordinator: Coordinator, attemptsRemaining: Int = 20) {
        guard !coordinator.isScheduling else { return }
        coordinator.isScheduling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            coordinator.isScheduling = false
            var ancestor = view.superview
            while let candidate = ancestor, !(candidate is NSSplitView) {
                ancestor = candidate.superview
            }
            guard let splitView = ancestor as? NSSplitView else {
                if attemptsRemaining > 0 {
                    installWhenAttached(view, coordinator: coordinator, attemptsRemaining: attemptsRemaining - 1)
                }
                return
            }

            if coordinator.splitView !== splitView || splitView.autosaveName != name {
                splitView.autosaveName = name
                coordinator.splitView = splitView
            }
        }
    }
}

private struct ListScrollbarOverlay: NSViewRepresentable {
    final class Coordinator {
        weak var scrollView: NSScrollView?
        var isScheduling = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ListScrollbar {
        let view = ListScrollbar(frame: .zero)
        installLater(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: ListScrollbar, context: Context) {
        installLater(from: view, coordinator: context.coordinator)
    }

    private func installLater(from view: ListScrollbar, coordinator: Coordinator, attempts: Int = 20) {
        guard !coordinator.isScheduling else { return }
        coordinator.isScheduling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            coordinator.isScheduling = false
            guard let scrollView = findScrollView(around: view) else {
                if attempts > 0 {
                    installLater(from: view, coordinator: coordinator, attempts: attempts - 1)
                }
                return
            }
            if coordinator.scrollView !== scrollView {
                view.attach(to: scrollView)
                coordinator.scrollView = scrollView
            }
            scrollView.scrollerStyle = .overlay
            scrollView.hasVerticalScroller = false
            view.needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                scrollView.hasVerticalScroller = false
                view.needsDisplay = true
            }
        }
    }

    private func findScrollView(around view: NSView) -> NSScrollView? {
        enclosingListScrollView(around: view)
    }
}

private func enclosingListScrollView(around view: NSView) -> NSScrollView? {
    var ancestor = view.superview
    while let candidate = ancestor {
        if let scrollView = candidate as? NSScrollView { return scrollView }
        ancestor = candidate.superview
    }

    guard let root = view.window?.contentView else { return nil }
    let marker = view.convert(view.bounds, to: nil)
    let point = NSPoint(x: marker.midX, y: marker.midY)
    var candidates: [NSScrollView] = []
    var pending = [root]
    while let current = pending.popLast() {
        if let scrollView = current as? NSScrollView,
           scrollView.convert(scrollView.bounds, to: nil).contains(point) {
            candidates.append(scrollView)
        }
        pending.append(contentsOf: current.subviews)
    }
    return candidates.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
}

private final class ListScrollbar: NSView {
    private var isPaneHovered = false {
        didSet {
            if oldValue != isPaneHovered { needsDisplay = true }
        }
    }
    private weak var scrollView: NSScrollView?
    private var paneTrackingArea: NSTrackingArea?
    private var mouseMonitor: Any?
    private var clipObserver: NSObjectProtocol?
    private var documentObserver: NSObjectProtocol?
    private weak var trackedDocument: NSView?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isDragging = false
    private var dragOffset: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    func attach(to scrollView: NSScrollView) {
        if let oldScrollView = self.scrollView, let paneTrackingArea {
            oldScrollView.removeTrackingArea(paneTrackingArea)
        }
        self.scrollView = scrollView
        let paneTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        scrollView.addTrackingArea(paneTrackingArea)
        self.paneTrackingArea = paneTrackingArea
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]
            ) { [weak self] event in
                guard let self else { return event }
                self.updatePaneHover(at: event.window === self.window ? event.locationInWindow : nil)
                return event
            }
        }
        observeScrollView()
        updatePaneHover(at: scrollView.window?.mouseLocationOutsideOfEventStream)
        needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit {
        if let scrollView, let paneTrackingArea { scrollView.removeTrackingArea(paneTrackingArea) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
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
        ) { [weak self] _ in
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            self?.needsDisplay = true
        }

        if trackedDocument !== scrollView.documentView {
            if let documentObserver { NotificationCenter.default.removeObserver(documentObserver) }
            trackedDocument = scrollView.documentView
            trackedDocument?.postsFrameChangedNotifications = true
            documentObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: trackedDocument,
                queue: .main
            ) { [weak self] _ in
                if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
                self?.needsDisplay = true
            }
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
        if event.trackingArea === trackingArea { isHovered = true }
        updatePaneHover(at: event.locationInWindow)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === trackingArea { isHovered = false }
        updatePaneHover(at: event.locationInWindow)
        needsDisplay = true
    }

    private func updatePaneHover(at location: NSPoint?) {
        guard let location, let scrollView, let window,
              window === scrollView.window,
              let contentView = window.contentView else {
            isPaneHovered = false
            return
        }
        let scrollFrame = scrollView.convert(scrollView.bounds, to: nil)
        let contentTop = contentView.convert(contentView.bounds, to: nil).maxY
        let paneFrame = NSRect(
            x: scrollFrame.minX,
            y: scrollFrame.minY,
            width: scrollFrame.width,
            height: max(0, contentTop - scrollFrame.minY)
        )
        let overPane = paneFrame.contains(location)
        let overThumbOverlay = bounds.contains(convert(location, from: nil))
        isPaneHovered = overPane || overThumbOverlay
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
        guard isPaneHovered || isDragging, let thumbRect else { return }
        NSColor.labelColor.withAlphaComponent(isHovered || isDragging ? 0.45 : 0.25).setFill()
        NSBezierPath(roundedRect: thumbRect, xRadius: 3, yRadius: 3).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isPaneHovered || isDragging, thumbRect != nil else { return nil }
        return super.hitTest(point)
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
    @Bindable var model: AppModel
    @Binding var themeRawValue: String
    @Binding var isSidebarVisible: Bool
    @FocusState private var isPrefixFocused: Bool
    @State private var isWorkflowHelpPresented = false
    @State private var isSettingsPresented = false

    private enum AppVersion {
        private static var shortVersion: String {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        }

        private static var buildVersion: String? {
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        }

        static var label: String {
            shortVersion == "未知" ? "版本未知" : "v\(shortVersion)"
        }

        static var details: String {
            guard let buildVersion, !buildVersion.isEmpty else {
                return "版本 \(shortVersion)"
            }
            return "版本 \(shortVersion)\n\n构建 \(buildVersion)"
        }
    }

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "B-roll配对台",
                titleCredit: "@深键",
                systemImage: "photo.stack",
                showsTitleIcon: false,
                showsWaveUnderline: true,
                titleFont: .custom("SmileySans-Oblique", size: 22).weight(.bold),
                actions: [
                    PaneHeaderAction(systemImage: "sidebar.left", help: "收起侧边栏", usesAnimation: false) {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            isSidebarVisible = false
                        }
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
                    SidebarSection(title: "项目设置", systemImage: "archivebox", showsHeading: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            DirectoryChoiceRow(
                                title: "剪辑项目文件夹",
                                value: model.destinationDirectoryName,
                                isConfigured: model.destinationDirectoryURL != nil,
                                action: model.chooseDestinationDirectory,
                                clearAction: model.clearDestinationDirectory,
                                openAction: model.revealDestinationDirectory,
                                onDirectoryDrop: { model.acceptDestinationDirectoryDrop($0) }
                            )

                            ARollUploadControl(model: model)

                            Divider()

                            HStack(spacing: 6) {
                                Label("B-roll命名前缀", systemImage: "pencil.and.list.clipboard")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("选填")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(.tertiary)
                                Image(systemName: model.isPrefixValid ? "checkmark.circle.fill" : "info.circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(model.isPrefixValid ? Color.blue : Color.secondary)
                                    .hoverHelp(model.isPrefixValid
                                        ? "归档文件名会包含这个前缀"
                                        : "留空也可添加文案、素材目录并绑定素材；文件名将以 BR 编号开头")
                                    .accessibilityLabel(model.isPrefixValid
                                        ? "命名前缀已填写，归档文件名会包含此前缀"
                                        : "命名前缀选填，留空时归档文件名以 BR 编号开头")
                                Spacer(minLength: 0)
                            }

                            TextField("例如 第15期", text: $model.prefix)
                                .textFieldStyle(.plain)
                                .font(.system(size: 17))
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

                            Text("示例：\(model.isPrefixValid ? "\(ScriptParser.sanitizePart(model.prefix, maxLength: 30))_" : "")BR001_文案短句.ext")
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .textSelection(.enabled)
                        }
                    }

                    SidebarSection(title: "对照表", systemImage: "doc.text", showsHeading: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Label("对照表", systemImage: "doc.text")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 8) {
                                Label("JSON 文件", systemImage: "curlybraces")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                Spacer(minLength: 0)
                                ManifestIconButton(title: "在 Finder 中显示给 AI 的 JSON 对照表", systemImage: "arrow.up.forward.app") {
                                    model.revealManifest()
                                }
                                ManifestIconButton(title: "预览给 AI 的 JSON 对照表", systemImage: "eye") {
                                    model.previewManifest()
                                }
                                ManifestIconButton(
                                    title: "清空配对和归档副本",
                                    systemImage: "trash",
                                    hoverTint: .red
                                ) {
                                    model.requestClearAssignments()
                                }
                            }

                            Divider()
                        }
                    }

                    SidebarStatisticsSection(model: model)

                    PromptCopyButton()

                    SidebarStatusView(model: model)

                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.trailing, 0, for: .scrollContent)
            .overlay(alignment: .trailing) {
                ListScrollbarOverlay()
                    .frame(width: 8)
                    .accessibilityHidden(true)
            }

            HStack {
                Text(AppVersion.label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .help(AppVersion.details)
                    .accessibilityLabel(AppVersion.details.replacingOccurrences(of: "\n\n", with: "，"))
                Spacer()
                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(IconActionButtonStyle(usesAnimation: false))
                .help("设置")
                .accessibilityLabel("设置")
                .pointerCursor()
                .popover(isPresented: $isSettingsPresented, arrowEdge: .bottom) {
                    AppSettingsPopover(model: model)
                }
                Button {
                    isWorkflowHelpPresented = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(IconActionButtonStyle(usesAnimation: false))
                .help("查看粗剪流程")
                .accessibilityLabel("查看粗剪流程")
                .pointerCursor()
                .popover(isPresented: $isWorkflowHelpPresented, arrowEdge: .bottom) {
                    WorkflowHelpPopover()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.windowBackground)
            .overlay(alignment: .top) { Divider() }
        }
        .background(.windowBackground)
        .onAppear {
            // SwiftUI can assign the first key-window responder after onAppear.
            // Clear it on the next run loop so the naming field only focuses on user click.
            DispatchQueue.main.async {
                isPrefixFocused = false
            }
        }
        .onChange(of: model.prefix) { _, _ in
            model.persistPreferences()
        }
    }
}

private struct AppSettingsPopover: View {
    @Bindable var model: AppModel
    @State private var rateText: String
    @State private var thresholdText: String

    init(model: AppModel) {
        self.model = model
        _rateText = State(initialValue: String(model.pacingSettings.charactersPerMinute))
        _thresholdText = State(initialValue: model.pacingSettings.thresholdLabel)
    }

    private var parsedRate: Int? {
        guard let value = Int(rateText.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }

    private var parsedThreshold: Double? {
        let text = thresholdText.trimmingCharacters(in: .whitespaces)
        let value = Double(text) ?? Double(text.replacingOccurrences(of: ",", with: "."))
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func applyDraft() {
        guard let rate = parsedRate, let threshold = parsedThreshold else { return }
        model.updatePacingSettings(ARollPacingSettings(
            charactersPerMinute: rate,
            maximumContinuousSeconds: threshold,
            remindersEnabled: model.pacingSettings.remindersEnabled
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.system(size: 17, weight: .semibold))
            Divider()
            Text("文案语速与提醒")
                .font(.system(size: 14, weight: .medium))

            HStack {
                Text("估算语速")
                Spacer()
                HStack(spacing: 6) {
                    TextField("350", text: $rateText)
                        .accessibilityLabel("估算语速")
                        .frame(width: 80)
                    Text("字/分钟").foregroundStyle(.secondary)
                }
            }

            Toggle("连续 A-roll 时长提醒", isOn: Binding(
                get: { model.pacingSettings.remindersEnabled },
                set: { enabled in
                    model.updatePacingSettings(ARollPacingSettings(
                        charactersPerMinute: model.pacingSettings.charactersPerMinute,
                        maximumContinuousSeconds: model.pacingSettings.maximumContinuousSeconds,
                        remindersEnabled: enabled
                    ))
                }
            ))
            .toggleStyle(.switch)

            HStack {
                Text("连续超过")
                Spacer()
                HStack(spacing: 6) {
                    TextField("5", text: $thresholdText)
                        .accessibilityLabel("连续 A-roll 提醒时长")
                        .frame(width: 80)
                    Text("秒时提醒").foregroundStyle(.secondary)
                }
            }
            .disabled(!model.pacingSettings.remindersEnabled)

            if parsedRate == nil || parsedThreshold == nil {
                Text("语速请输入大于 0 的整数；提醒秒数请输入大于 0 的数字。")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("按整篇文案累计连续 A-roll 时长，B-roll 会中断计时。忽略标点和空白，实际节奏以口播为准。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("语速和提醒修改后自动保存。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("恢复默认") {
                    let settings = ARollPacingSettings()
                    rateText = String(settings.charactersPerMinute)
                    thresholdText = settings.thresholdLabel
                    model.updatePacingSettings(settings)
                }
                .controlSize(.small)
            }

            Divider()
            ShootingDeviceSettingsView(model: model)
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 360)
        .onChange(of: rateText) { _, _ in applyDraft() }
        .onChange(of: thresholdText) { _, _ in applyDraft() }
    }
}

private struct ShootingDeviceSettingsView: View {
    @Bindable var model: AppModel
    @State private var drafts: [ShootingDevice]

    init(model: AppModel) {
        self.model = model
        _drafts = State(initialValue: model.shootingDevices)
    }

    private var validatedDrafts: [ShootingDevice]? { ShootingDevice.validated(drafts) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("拍摄设备")
                .font(.system(size: 14, weight: .medium))
            Text("用于 A-roll 条目的拍摄设备选项。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($drafts) { $device in
                        HStack {
                            TextField("设备名称", text: $device.name)
                                .accessibilityLabel("拍摄设备名称：\(device.name)")
                            Button {
                                drafts.removeAll { $0.id == device.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help("删除设备选项")
                            .accessibilityLabel("删除拍摄设备：\(device.name)")
                        }
                    }
                }
            }
            .frame(height: min(132, CGFloat(drafts.count) * 30))

            if validatedDrafts == nil {
                Text("设备名称不能为空或重复。")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("添加设备", systemImage: "plus") {
                    drafts.append(ShootingDevice(name: ""))
                }
                Spacer()
                Button("保存设备选项") {
                    if model.updateShootingDevices(drafts) { drafts = model.shootingDevices }
                }
                .disabled(validatedDrafts == nil || validatedDrafts == model.shootingDevices)
            }
            .controlSize(.small)

            Text("修改后点击保存，适用于所有项目。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ARollUploadControl: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false

    private var isEnabled: Bool {
        model.destinationDirectoryURL != nil &&
            !model.isBusy &&
            !model.isARollReplacementConfirmationPresented &&
            !model.isARollRemovalConfirmationPresented
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("A")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 16, alignment: .leading)
                Text("上传 A-roll")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                ConfigurationStatusIcon(
                    isConfigured: model.aRollVideoDisplayName != nil,
                    readyHelp: "A-roll 视频已添加",
                    waitingHelp: "选择或拖入 A-roll 视频"
                )
                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                Button(action: model.chooseARollVideo) {
                    HStack(spacing: 7) {
                        Image(systemName: "film")
                            .foregroundStyle(model.aRollVideoDisplayName == nil
                                ? Color.orange
                                : (isEnabled ? Color.accentColor : Color.secondary))
                        Text(model.aRollVideoDisplayName ?? "点击选择或拖入视频")
                            .font(.system(size: 16))
                            .foregroundStyle(model.aRollVideoDisplayName == nil ? Color.orange : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.94)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                    }
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .background(
                        isDropTargeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .textBackgroundColor).opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor.opacity(0.8) : Color(nsColor: .separatorColor).opacity(0.55),
                                style: isDropTargeted ? StrokeStyle(lineWidth: 1.4, dash: [5, 3]) : StrokeStyle(lineWidth: 0.5)
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: acceptVideoDrop)
                .help(model.destinationDirectoryURL == nil
                    ? "先选择剪辑项目文件夹，再上传 A-roll 视频"
                    : "点击或拖入视频；副本命名为 A-roll，原件保留")
                .accessibilityLabel("上传 A-roll 视频")
                .accessibilityHint("点击选择或拖入一个视频文件，复制到当前项目的 A-roll 文件夹并命名为 A-roll")
                .pointerCursor(isEnabled ? .pointingHand : .arrow)

                if model.aRollVideoDisplayName != nil {
                    Button(action: model.requestARollVideoRemoval) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .foregroundStyle(.secondary)
                    .disabled(!isEnabled)
                    .hoverHelp("移出项目 A-roll 文件夹中的视频")
                    .accessibilityLabel("移出项目 A-roll 文件")
                    .pointerCursor(isEnabled ? .pointingHand : .arrow)
                }
            }
        }
        .confirmationDialog(
            "替换 A-roll 视频？",
            isPresented: Binding(
                get: { model.isARollReplacementConfirmationPresented },
                set: { isPresented in
                    if !isPresented { model.cancelARollVideoReplacement() }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("替换现有 A-roll 视频", role: .destructive) {
                model.confirmARollVideoReplacement()
            }
            Button("取消", role: .cancel) {
                model.cancelARollVideoReplacement()
            }
        } message: {
            Text(model.aRollReplacementConfirmationMessage)
        }
        .confirmationDialog(
            "移出 A-roll 视频？",
            isPresented: Binding(
                get: { model.isARollRemovalConfirmationPresented },
                set: { isPresented in
                    if !isPresented { model.cancelARollVideoRemoval() }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("移出项目副本", role: .destructive) {
                model.confirmARollVideoRemoval()
            }
            Button("取消", role: .cancel) {
                model.cancelARollVideoRemoval()
            }
        } message: {
            Text("将项目 A-roll 文件夹中的视频移入废纸篓；其他位置的文件不受影响。")
        }
    }

    private func acceptVideoDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty, isEnabled else { return false }

        Task { @MainActor in
            let urls = await FileURLDropLoader.urls(from: fileProviders)
            await model.importARollVideo(from: urls)
        }
        return true
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    let systemImage: String
    var showsHeading = true
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        systemImage: String,
        showsHeading: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.showsHeading = showsHeading
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeading ? 8 : 0) {
            if showsHeading {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 2)
            }

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
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("操作状态", systemImage: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .hoverHelp("显示最近一次操作结果和本机保存状态")

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.statusMessage)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Text(model.lastSaved)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("操作状态。最近操作：\(model.statusMessage)。\(model.lastSaved)")
    }
}

private struct PromptCopyButton: View {
    @State private var didCopy = false
    @State private var isErrorPresented = false
    @State private var errorMessage = ""
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 6) {
            Button(action: copyPrompt) {
                Label("复制提示词", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help(didCopy ? "已复制到剪贴板" : "复制提示词.txt 的完整内容到剪贴板")
            .accessibilityLabel("复制提示词")
            .accessibilityHint("将随应用打包的提示词全文复制到剪贴板")
            .pointerCursor()

            if didCopy {
                Text("已复制到剪贴板")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
        .alert("复制提示词失败", isPresented: $isErrorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func copyPrompt() {
        guard let promptURL = Bundle.main.url(forResource: "提示词", withExtension: "txt") else {
            showError("应用资源中未找到提示词.txt。")
            return
        }

        do {
            let prompt = try String(contentsOf: promptURL, encoding: .utf8)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(prompt, forType: .string) else {
                showError("系统剪贴板未能接收提示词内容。")
                return
            }
            showCopySuccess()
        } catch {
            showError("读取提示词.txt 失败：\(error.localizedDescription)")
        }
    }

    private func showCopySuccess() {
        copyFeedbackTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            didCopy = true
        }
        copyFeedbackTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                didCopy = false
            }
        }
    }

    private func showError(_ message: String) {
        copyFeedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            didCopy = false
        }
        errorMessage = message
        isErrorPresented = true
    }
}

private struct DirectoryChoiceRow: View {
    let title: String
    let value: String
    let isConfigured: Bool
    let action: () -> Void
    let clearAction: () -> Void
    let openAction: () -> Void
    let onDirectoryDrop: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(Color.primary)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                ConfigurationStatusIcon(isConfigured: isConfigured,
                                        readyHelp: "剪辑项目文件夹已选择",
                                        waitingHelp: "请选择剪辑项目文件夹")
            }

            HStack(spacing: 7) {
                Image(systemName: isConfigured ? "folder.fill" : "folder")
                    .foregroundStyle(isConfigured ? Color.accentColor : Color.orange)
                Text(value == "未选择" ? "请选择剪辑项目文件夹" : value)
                    .font(.system(size: 16))
                    .foregroundStyle(isConfigured ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.94)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: action) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(IconActionButtonStyle())
                .hoverHelp("选择或更换剪辑项目文件夹")
                .accessibilityLabel("选择或更换剪辑项目文件夹，当前：\(value)")
                .pointerCursor()

                if isConfigured {
                    Button(action: clearAction) {
                        Image(systemName: "folder.badge.minus")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .foregroundStyle(.secondary)
                    .hoverHelp("取消选择剪辑项目文件夹")
                    .accessibilityLabel("取消选择剪辑项目文件夹")
                    .pointerCursor()

                    Button(action: openAction) {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .foregroundStyle(.secondary)
                    .hoverHelp("在 Finder 新标签页中打开归档目录")
                    .accessibilityLabel("在 Finder 新标签页中打开归档目录")
                    .pointerCursor()
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 8)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
            }
            .modifier(DirectoryDropTargetModifier(onDrop: onDirectoryDrop))
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
            .font(.system(size: 14))
            .foregroundStyle(isConfigured ? Color.blue : Color.orange)
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
            .font(.system(size: 16))
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
    var hoverTint: Color?
    let action: () -> Void
    @State private var isHovered = false

    init(
        title: String,
        systemImage: String,
        hoverTint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.hoverTint = hoverTint
        self.action = action
    }

    private var tint: Color {
        isHovered ? (hoverTint ?? .primary) : .primary
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .frame(width: 42, height: 36)
        }
        .buttonStyle(SidebarActionButtonStyle(tint: tint))
        .hoverHelp(title)
        .accessibilityLabel(title)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}

private struct ManifestPreviewSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("AI JSON 对照表预览", systemImage: "curlybraces")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .pointerCursor()
            }
            .padding(16)

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(size: 16, design: .monospaced))
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
    var usesAnimation = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(IconActionButtonChrome(
            isPressed: configuration.isPressed,
            usesAnimation: usesAnimation
        ))
    }
}

private struct IconActionButtonChrome: ViewModifier {
    let isPressed: Bool
    let usesAnimation: Bool
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
            .animation(usesAnimation ? .easeOut(duration: 0.12) : nil, value: isPressed)
            .animation(usesAnimation ? .easeOut(duration: 0.12) : nil, value: isHovered)
    }
}

private struct SidebarStatisticMetric: View {
    let value: Int
    let label: String
    let tint: Color
    var percentageTotal: Int? = nil

    private var percentageText: String? {
        percentageTotal.map { BrollProductionMethodStat.percentageText(for: value, of: $0) }
    }

    private var description: String {
        if let percentageText {
            return "\(label) \(value)，占全部文案条数的 \(percentageText)"
        }
        return "\(label) \(value)"
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value, format: .number)
                .font(.caption.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            if let percentageText {
                Spacer(minLength: 2)
                Text(percentageText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(description)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(description)
    }
}

private struct SidebarStatisticsSection: View {
    let model: AppModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        SidebarSection(title: "统计信息", systemImage: "chart.bar.xaxis", showsHeading: false) {
            VStack(alignment: .leading, spacing: 8) {
                Label("统计信息", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    SidebarStatisticMetric(value: model.scriptCharacterCount, label: "字数", tint: .secondary)
                    SidebarStatisticMetric(value: model.pendingBrollCount, label: "未绑定", tint: .secondary)
                }

                SidebarRollRatioView(aRollCount: model.aRollAnchorCount, bRollCount: model.bRollAnchorCount)

                Text("A-roll / B-roll 占比按文案条数计算")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                ArollStatisticsView(model: model)
                BrollStatisticsView(model: model)
            }
        }
    }
}

private struct SidebarRollRatioView: View {
    let aRollCount: Int
    let bRollCount: Int

    private var total: Int { aRollCount + bRollCount }
    private var aRollFraction: CGFloat {
        total > 0 ? CGFloat(aRollCount) / CGFloat(total) : 0
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                ratioLabel("A-roll", count: aRollCount, tint: .blue)
                Spacer(minLength: 0)
                ratioLabel("B-roll", count: bRollCount, tint: .green)
            }

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Color.blue.frame(width: geometry.size.width * aRollFraction)
                    Color.green.frame(width: total > 0 ? geometry.size.width * (1 - aRollFraction) : 0)
                }
                .frame(width: geometry.size.width, alignment: .leading)
                .background(.quaternary)
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .padding(8)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A-roll \(aRollCount) 条，占 \(BrollProductionMethodStat.percentageText(for: aRollCount, of: total))；B-roll \(bRollCount) 条，占 \(BrollProductionMethodStat.percentageText(for: bRollCount, of: total))")
    }

    private func ratioLabel(_ title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(tint)
            Text(count, format: .number)
                .fontWeight(.semibold)
            Text(BrollProductionMethodStat.percentageText(for: count, of: total))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private extension ArollProductionMethod {
    var color: Color {
        switch self {
        case .none: return .gray
        case .text: return .blue
        case .searchMaterial: return .orange
        }
    }
}

private enum ArollStatisticsPalette {
    static let unassignedDeviceColor: Color = .gray

    @MainActor static func devices(in model: AppModel) -> [ShootingDevice] {
        var result = model.shootingDevices
        let selectedDevices = model.rows
            .filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && model.rollType(for: $0.id) == .aRoll
            }
            .compactMap { model.shootingDevice(for: $0.id) }
        for device in selectedDevices where !result.contains(where: { $0.id == device.id }) {
            result.append(device)
        }
        return result
    }

    static func color(for deviceID: String?, in devices: [ShootingDevice]) -> Color {
        guard let deviceID, let index = devices.firstIndex(where: { $0.id == deviceID }) else {
            return unassignedDeviceColor
        }
        let hue = (0.57 + Double(index) * 0.61803398875).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.68, brightness: 0.86)
    }
}

private struct ColoredCategoryStat: Identifiable {
    let id: String
    let title: String
    let count: Int
    let color: Color
}

private struct ArollStatisticsView: View {
    let model: AppModel

    var body: some View {
        let total = model.aRollAnchorCount
        let methodStats = ArollProductionMethod.allCases.map {
            ColoredCategoryStat(id: $0.id, title: $0.title,
                                count: model.arollProductionMethodCount($0), color: $0.color)
        }
        let devices = ArollStatisticsPalette.devices(in: model)
        let deviceStats = devices.map { device in
            ColoredCategoryStat(id: "device-\(device.id)", title: device.name,
                                count: model.arollShootingDeviceCount(device.id),
                                color: ArollStatisticsPalette.color(for: device.id, in: devices))
        } + [ColoredCategoryStat(id: "device-none", title: "未设置",
                                count: model.arollShootingDeviceCount(nil),
                                color: ArollStatisticsPalette.unassignedDeviceColor)]

        VStack(alignment: .leading, spacing: 8) {
            Label("A-roll 统计", systemImage: "person.crop.rectangle")
                .font(.caption.weight(.semibold))

            ArollCategoryDonutView(title: "制作方式占比", statistics: methodStats, total: total)
            ArollCategoryDonutView(title: "拍摄设备占比", statistics: deviceStats, total: total)

            Text("占比以全部 A-roll 文案为基数")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ArollCategoryDonutView: View {
    let title: String
    let statistics: [ColoredCategoryStat]
    let total: Int

    private let legendColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: "chart.pie.fill")
                .font(.system(size: 11, weight: .medium))

            Chart {
                ForEach(statistics.filter { $0.count > 0 }) { statistic in
                    SectorMark(
                        angle: .value("文案数", statistic.count),
                        innerRadius: .ratio(0.48),
                        angularInset: 1.2
                    )
                    .foregroundStyle(statistic.color)
                    .annotation(position: .overlay, alignment: .center) {
                        Text(BrollProductionMethodStat.percentageText(for: statistic.count, of: total))
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .shadow(color: .black.opacity(0.55), radius: 1)
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 148)
            .overlay {
                VStack(spacing: 1) {
                    Text(total, format: .number)
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    Text("条 A-roll")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .allowsHitTesting(false)
            }

            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 5) {
                ForEach(statistics) { statistic in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(statistic.color)
                            .frame(width: 4, height: 14)
                        Text(statistic.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(statistic.count, format: .number)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
                    .padding(.horizontal, 7)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private extension BrollProductionMethod {
    var color: Color {
        switch self {
        case .undecided: return .gray
        case .liveAction: return .green
        case .animation: return .orange
        case .aiVideo: return .purple
        case .imageMotion: return .blue
        case .stockFootage: return .cyan
        case .screenRecording: return .pink
        case .other: return .indigo
        }
    }
}

private struct BrollProductionMethodStat: Identifiable {
    let method: BrollProductionMethod
    let count: Int

    var id: String { method.rawValue }
    var color: Color { method.color }

    func percentageText(of total: Int) -> String {
        Self.percentageText(for: count, of: total)
    }

    static func percentageText(for count: Int, of total: Int) -> String {
        let percentage = total > 0 ? Int((Double(count) / Double(total) * 100).rounded()) : 0
        return "\(percentage)%"
    }
}

private struct BrollStatisticsView: View {
    let model: AppModel

    private let legendColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        let total = model.bRollAnchorCount
        let methodStats = BrollProductionMethod.allCases.map {
            BrollProductionMethodStat(method: $0, count: model.brollProductionMethodCount($0))
        }

        VStack(alignment: .leading, spacing: 8) {
            Label("制作方式占比", systemImage: "chart.pie.fill")
                .font(.caption.weight(.semibold))

            Chart {
                ForEach(methodStats.filter { $0.count > 0 }) { statistic in
                    SectorMark(
                        angle: .value("文案数", statistic.count),
                        innerRadius: .ratio(0.48),
                        angularInset: 1.2
                    )
                    .foregroundStyle(statistic.color)
                    .annotation(position: .overlay, alignment: .center) {
                        Text(statistic.percentageText(of: total))
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .shadow(color: .black.opacity(0.55), radius: 1)
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 188)
            .overlay {
                VStack(spacing: 1) {
                    Text(total, format: .number)
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    Text("条 B-roll")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .allowsHitTesting(false)
            }

            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 6) {
                ForEach(methodStats) { statistic in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(statistic.color)
                            .frame(width: 4, height: 14)
                        Text(statistic.method.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .padding(.horizontal, 7)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }

            Divider()

            Text("准备情况")
                .font(.caption.weight(.semibold))

            HStack(spacing: 6) {
                ForEach(BrollPreparationStatus.allCases) { status in
                    preparationStatusCard(status, total: total)
                }
            }

            Text("占比以全部 B-roll 文案为基数")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func preparationStatusCard(_ status: BrollPreparationStatus, total: Int) -> some View {
        let count: Int
        let tint: Color
        switch status {
        case .pending:
            count = model.pendingPreparationBrollCount
            tint = .orange
        case .ready:
            count = model.readyPreparationBrollCount
            tint = .green
        case .bound:
            count = model.boundPreparationBrollCount
            tint = .blue
        }

        return VStack(alignment: .leading, spacing: 4) {
            Text(status.title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(count, format: .number)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(BrollProductionMethodStat.percentageText(for: count, of: total))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ScriptRowVisibilityMarker: NSViewRepresentable {
    let rowID: String
    var tracksTextEditing = false

    func makeNSView(context: Context) -> ScriptRowMarkerView {
        let view = ScriptRowMarkerView()
        view.rowID = rowID
        view.tracksTextEditing = tracksTextEditing
        return view
    }

    func updateNSView(_ view: ScriptRowMarkerView, context: Context) {
        view.rowID = rowID
        view.tracksTextEditing = tracksTextEditing
    }
}

private final class ScriptRowMarkerView: NSView {
    /// Live markers, so scroll updates need not walk the whole list view hierarchy.
    static let registry = NSHashTable<ScriptRowMarkerView>.weakObjects()

    var rowID = ""
    var tracksTextEditing = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { Self.registry.remove(self) } else { Self.registry.add(self) }
    }

    static func markers(in document: NSView) -> [ScriptRowMarkerView] {
        registry.allObjects.filter { $0.window === document.window && $0.isDescendant(of: document) }
    }
}

private struct ScriptListVisibilityObserver: NSViewRepresentable {
    let onChange: ([VisibleScriptRow]) -> Void
    let onSelectRow: (String) -> Void
    let onDoubleClickRow: (String) -> Void

    func makeNSView(context: Context) -> ScriptListVisibilityView {
        let view = ScriptListVisibilityView()
        view.onChange = onChange
        view.onSelectRow = onSelectRow
        view.onDoubleClickRow = onDoubleClickRow
        return view
    }

    func updateNSView(_ view: ScriptListVisibilityView, context: Context) {
        view.onChange = onChange
        view.onSelectRow = onSelectRow
        view.onDoubleClickRow = onDoubleClickRow
        view.scheduleUpdate()
    }

    static func dismantleNSView(_ view: ScriptListVisibilityView, coordinator: ()) {
        view.stopObserving()
    }
}

/// Read the native list viewport so cached/offscreen SwiftUI rows cannot trigger follow mode.
private final class ScriptListVisibilityView: NSView {
    var onChange: (([VisibleScriptRow]) -> Void)?
    var onSelectRow: ((String) -> Void)?
    var onDoubleClickRow: ((String) -> Void)?
    private weak var scrollView: NSScrollView?
    private weak var documentView: NSView?
    private var observers: [NSObjectProtocol] = []
    private var pendingUpdate: DispatchWorkItem?
    private var mouseMonitor: Any?
    private var lastVisibleRows: [VisibleScriptRow] = []
    private var attachmentAttempts = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopObserving() }
        else { attachmentAttempts = 0; scheduleUpdate() }
    }

    override func layout() {
        super.layout()
        scheduleUpdate()
    }

    func stopObserving() {
        pendingUpdate?.cancel()
        pendingUpdate = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        scrollView = nil
        documentView = nil
    }

    func scheduleUpdate() {
        guard window != nil, pendingUpdate == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingUpdate = nil
            self.updateVisibleRows()
        }
        pendingUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    private func updateVisibleRows() {
        guard let list = enclosingListScrollView(around: self), let document = list.documentView else {
            if attachmentAttempts < 20 { attachmentAttempts += 1; scheduleUpdate() }
            return
        }
        if list !== scrollView || document !== documentView {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            scrollView = list
            documentView = document
            // Keep native row selection and keyboard navigation, using our card highlight.
            (document as? NSTableView)?.selectionHighlightStyle = .none
            if mouseMonitor == nil {
                mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    self?.handleRowClick(event)
                    return event
                }
            }
            list.contentView.postsBoundsChangedNotifications = true
            document.postsFrameChangedNotifications = true
            for (name, object) in [(NSView.boundsDidChangeNotification, list.contentView),
                                   (NSView.frameDidChangeNotification, document)] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) {
                    [weak self] _ in self?.scheduleUpdate()
                })
            }
        }
        let clip = list.contentView
        var visible: [(CGFloat, VisibleScriptRow)] = []
        for marker in ScriptRowMarkerView.markers(in: document) {
            if !marker.tracksTextEditing,
               !marker.isHiddenOrHasHiddenAncestor,
               marker.bounds.height > 0 {
                let rect = marker.convert(marker.bounds, to: clip)
                let intersection = rect.intersection(clip.bounds)
                if !intersection.isNull, intersection.height > 1 {
                    let top = clip.isFlipped ? intersection.minY - rect.minY : rect.maxY - intersection.maxY
                    let start = min(1, max(0, top / rect.height))
                    let end = min(1, start + intersection.height / rect.height)
                    let order = clip.isFlipped ? rect.minY : -rect.maxY
                    visible.append((order, VisibleScriptRow(id: marker.rowID,
                                                           startFraction: Double(start), endFraction: Double(end))))
                }
            }
        }
        // Quantize subpixel layout changes to avoid repeatedly updating SwiftUI during a scroll.
        let rows = visible.sorted { $0.0 < $1.0 }.map { _, row in
            VisibleScriptRow(id: row.id, startFraction: (row.startFraction * 100).rounded() / 100,
                             endFraction: (row.endFraction * 100).rounded() / 100)
        }
        guard rows != lastVisibleRows else { return }
        lastVisibleRows = rows
        onChange?(rows)
    }

    private func handleRowClick(_ event: NSEvent) {
        guard event.window === window, let documentView, let clip = scrollView?.contentView,
              clip.convert(clip.bounds, to: nil).contains(event.locationInWindow) else { return }
        var clickedRowID: String?
        var clickedTextRowID: String?
        for marker in ScriptRowMarkerView.markers(in: documentView) {
            if !marker.isHiddenOrHasHiddenAncestor,
               marker.convert(marker.bounds, to: nil).contains(event.locationInWindow) {
                if marker.tracksTextEditing { clickedTextRowID = marker.rowID }
                else { clickedRowID = marker.rowID }
            }
        }
        let isDoubleClick = event.clickCount == 2
        // Let controls handle the event before committing the row selection or replacing its text.
        DispatchQueue.main.async { [weak self] in
            if let clickedRowID { self?.onSelectRow?(clickedRowID) }
            if isDoubleClick, let clickedTextRowID { self?.onDoubleClickRow?(clickedTextRowID) }
        }
    }
}

private enum ScriptRowSelectionStyle {
    static let fill = Color.blue.opacity(0.13)
    static let border = Color.blue.opacity(0.75)
    static let borderWidth: CGFloat = 1.5
}

private struct ScriptDistributionTimeline: View {
    let distribution: ScriptDistribution
    let aRollProductionMethod: (String) -> ArollProductionMethod
    let bRollProductionMethod: (String) -> BrollProductionMethod
    let shootingDevice: (String) -> ShootingDevice?
    /// Rows passing the current search and filter; nil when nothing narrows the list.
    let matchedRowIDs: Set<String>?
    let state: ScriptTimelineState
    let selectedRowID: String?
    let onSelectRow: (String) -> Void
    var expanded = false
    var barHeight: CGFloat = 30
    var onOpenWindow: (() -> Void)? = nil
    @State private var hoveredRowID: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var viewport: ScriptTimelineViewport { state.viewport }
    private var followsScript: Bool { state.followsScript }
    private var controlHeight: CGFloat { expanded ? 28 : 18 }
    private var navigatorHeight: CGFloat { expanded ? 28 : 16 }

    private var aRollColor: Color {
        colorScheme == .dark
            ? Color(red: 0.43, green: 0.45, blue: 0.47)
            : Color(red: 0.73, green: 0.75, blue: 0.77)
    }

    private var bRollColor: Color {
        colorScheme == .dark
            ? Color(red: 0.40, green: 0.64, blue: 0.44)
            : Color(red: 0.60, green: 0.77, blue: 0.62)
    }

    private func aRollColor(for device: ShootingDevice?) -> Color {
        // Use stable device IDs so renaming or reordering devices preserves their shades.
        switch device?.id {
        case "sony":
            return colorScheme == .dark
                ? Color(red: 0.50, green: 0.52, blue: 0.54)
                : Color(red: 0.78, green: 0.80, blue: 0.82)
        case "dji":
            return colorScheme == .dark
                ? Color(red: 0.30, green: 0.32, blue: 0.34)
                : Color(red: 0.53, green: 0.55, blue: 0.57)
        default:
            return aRollColor
        }
    }

    private func segmentColor(_ segment: ScriptDistribution.Segment) -> Color {
        segment.rollType == .aRoll ? aRollColor(for: shootingDevice(segment.id)) : bRollColor
    }

    var body: some View {
        let visibleSegments = self.visibleSegments
        let rangeDescription = "第 \(visibleSegments.first?.row.index ?? 1) 至 \(visibleSegments.last?.row.index ?? 1) 条"
        let lastSegmentID = distribution.segments.last?.id
        VStack(spacing: expanded ? 10 : 4) {
            HStack(spacing: 10) {
                legend("A-roll", color: aRollColor)
                    .help("拍摄设备：索尼浅灰，大疆深灰")
                legend("B-roll", color: bRollColor)
                Spacer(minLength: 0)
                Text("\(distribution.segments.count) 段")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                HStack(spacing: 2) {
                    zoomButton("minus", label: "缩小时间线", factor: 1 / 1.5, disabled: viewport.span >= 0.999)
                    Text("\((1 / viewport.span).formatted(.number.precision(.fractionLength(1))))×")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: expanded ? 48 : 34)
                    zoomButton("plus", label: "放大时间线", factor: 1.5,
                               disabled: viewport.span <= ScriptTimelineViewport.minimumSpan + 0.0001)
                }
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                        state.toggleFollowMode(in: distribution)
                    }
                } label: {
                    Label(followsScript ? "自适应" : "全局总览",
                          systemImage: followsScript ? "arrow.left.and.right.righttriangle.left.righttriangle.right" : "rectangle.expand.vertical")
                        .frame(width: expanded ? 104 : 76, height: controlHeight)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .hoverHelp(followsScript ? "切换到全局总览，固定显示全部文案" : "切换到自适应，恢复记住的缩放比例并跟随文案列表移动")
                .accessibilityLabel("时间线模式：\(followsScript ? "自适应" : "全局总览")")
                .accessibilityHint("切换自适应与全局总览")
                .pointerCursor()

                if let onOpenWindow {
                    Button(action: onOpenWindow) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 22, height: controlHeight)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .hoverHelp("在独立窗口放大展示时间线，可拖到另一块屏幕")
                    .accessibilityLabel("打开独立时间线窗口")
                    .pointerCursor()
                }
            }
            .font(.system(size: expanded ? 13 : 9, weight: .medium))
            .lineLimit(1)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    ForEach(visibleSegments) { segment in
                        let start = max(segment.startFraction, viewport.start)
                        let end = min(segment.endFraction, viewport.end)
                        segmentButton(segment, width: geometry.size.width * (end - start) / viewport.span,
                                      isLast: segment.id == lastSegmentID)
                            .offset(x: geometry.size.width * (start - viewport.start) / viewport.span)
                    }
                }
                .frame(width: geometry.size.width, height: barHeight, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .frame(height: barHeight)
            .background {
                ScriptTimelineScrollRegion(viewport: viewport, onChange: manuallySetRange)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("文案分布，\(rangeDescription)")
            .accessibilityHint("滚轮向上查看前面的文案，向下查看后面的文案，保持缩放倍数")

            HStack {
                endpointLabel(viewport.start <= 0.0001 ? "开头" : "第 \(visibleSegments.first?.row.index ?? 1) 条")
                Spacer()
                endpointLabel(viewport.end >= 0.9999 ? "结尾" : "第 \(visibleSegments.last?.row.index ?? 1) 条")
            }
            ScriptTimelineNavigator(distribution: distribution, viewport: viewport,
                                    segmentColor: segmentColor,
                                    selectedRowID: selectedRowID,
                                    height: navigatorHeight,
                                    onChange: manuallySetRange)
                .frame(height: navigatorHeight)
        }
        .onAppear { state.initializeIfNeeded(in: distribution) }
        .onChange(of: state.visibleRows) { _, _ in
            // Scroll updates arrive continuously; restarting an animation for each one causes stutter.
            if followsScript { updateFollowRange(animated: false) }
        }
        .onChange(of: distribution) { _, _ in updateFollowRange() }
        .onChange(of: selectedRowID) { _, _ in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                state.followSelection(in: distribution)
            }
        }
    }

    private var visibleSegments: [ScriptDistribution.Segment] {
        distribution.segments.filter { $0.endFraction > viewport.start && $0.startFraction < viewport.end }
    }

    private func updateFollowRange(animated: Bool = true) {
        withAnimation(animated && !reduceMotion ? .easeOut(duration: 0.14) : nil) {
            state.updateFollowRange(in: distribution)
        }
    }

    private func manuallySetRange(_ range: ScriptTimelineViewport) {
        state.setRange(range)
    }

    private func zoomButton(_ symbol: String, label: String, factor: Double, disabled: Bool) -> some View {
        Button {
            manuallySetRange(viewport.zoomed(by: factor))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: expanded ? 13 : 9, weight: .semibold))
                .frame(width: expanded ? 28 : 20, height: controlHeight)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .hoverHelp(label)
        .accessibilityLabel(label)
        .pointerCursor()
    }

    private func segmentButton(_ segment: ScriptDistribution.Segment, width: CGFloat, isLast: Bool) -> some View {
        let aRollMethod = aRollProductionMethod(segment.id)
        let bRollMethod = bRollProductionMethod(segment.id)
        let device = shootingDevice(segment.id)
        let detailDescription: String
        let methodColor: Color
        if segment.rollType == .aRoll {
            detailDescription = "，制作方式：\(aRollMethod.title)，拍摄设备：\(device?.name ?? "未设置")"
            methodColor = aRollMethod.color
        } else {
            detailDescription = "，制作方式：\(bRollMethod.title)"
            methodColor = bRollMethod.color
        }
        let isSelected = selectedRowID == segment.id
        return Button {
            onSelectRow(segment.id)
        } label: {
            VStack(spacing: 1) {
                Rectangle()
                    .fill(segmentColor(segment))
                    .overlay(alignment: .trailing) {
                        if width >= 3, !isLast {
                            Color(nsColor: .windowBackgroundColor).opacity(0.7).frame(width: 0.5)
                        }
                    }
                    .overlay {
                        if isSelected {
                            ScriptRowSelectionStyle.fill
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(ScriptRowSelectionStyle.border,
                                              lineWidth: min(ScriptRowSelectionStyle.borderWidth, width))
                        } else if hoveredRowID == segment.id {
                            Color.blue.opacity(0.08)
                        }
                    }
                    .overlay {
                        if expanded, width >= 48 {
                            Text(String(segment.row.index))
                                .font(.system(size: 18, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.primary.opacity(0.75))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: barHeight - (expanded ? 15 : 11))
                Rectangle()
                    .fill(methodColor)
                    .frame(height: expanded ? 8 : 4)
            }
            .frame(width: max(0, width))
            .opacity(matchedRowIDs?.contains(segment.id) == false && !isSelected ? 0.25 : 1)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("第 \(segment.row.index) 条 · \(segment.rollType.title)\(detailDescription)\n\(segment.row.text)\n点击定位文案")
        .accessibilityLabel("第 \(segment.row.index) 条，\(segment.rollType.title)\(detailDescription)，\(segment.row.text)")
        .accessibilityHint("定位到这条文案")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovered in
            if isHovered { hoveredRowID = segment.id }
            else if hoveredRowID == segment.id { hoveredRowID = nil }
        }
        .pointerCursor()
    }

    private func endpointLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: expanded ? 11 : 8))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: expanded ? 9 : 6, height: expanded ? 9 : 6)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

struct ScriptTimelineWindowView: View {
    @Bindable var model: AppModel
    @AppStorage("broll-namer-theme") private var themeRawValue = AppTheme.system.rawValue
    @AppStorage("broll-namer-script-timeline-always-on-top") private var isPinned = false

    private var preferredColorScheme: ColorScheme? {
        switch AppTheme(rawValue: themeRawValue) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        let state = model.scriptTimeline
        let distribution = ScriptDistribution(rows: model.rows, rollType: { model.rollType(for: $0) })
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("剪辑时间线", systemImage: "rectangle.split.3x1")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Text(model.destinationDirectoryURL?.lastPathComponent ?? "当前文案")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button {
                        isPinned.toggle()
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                            .frame(width: 28, height: 28)
                            .background(isPinned ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .hoverHelp(isPinned ? "取消窗口置顶" : "保持窗口置顶")
                    .accessibilityLabel("时间线窗口置顶")
                    .accessibilityValue(isPinned ? "已置顶" : "未置顶")
                    .accessibilityHint("将时间线窗口保持在其他普通窗口上方")
                    .pointerCursor()
                }

                if distribution.segments.isEmpty {
                    ContentUnavailableView("暂无时间线", systemImage: "rectangle.split.3x1",
                                           description: Text("在主窗口导入文案后，时间线会同步显示在这里。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScriptDistributionTimeline(
                        distribution: distribution,
                        aRollProductionMethod: { model.arollProductionMethod(for: $0) },
                        bRollProductionMethod: { model.brollProductionMethod(for: $0) },
                        shootingDevice: { model.shootingDevice(for: $0) },
                        matchedRowIDs: state.matchedRowIDs,
                        state: state,
                        selectedRowID: state.selectedRowID,
                        onSelectRow: state.requestReveal,
                        expanded: true,
                        barHeight: max(60, geometry.size.height - 275)
                    )
                    Divider()
                    if let row = model.rows.first(where: { $0.id == state.selectedRowID }) {
                        Text("第 \(row.index) 条 · \(row.text)")
                            .font(.system(size: 14))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("点击色块定位文案。大时间线内滚轮前后移动，加减按钮或拖动黄色范围框两端调整倍数。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.windowBackground)
        .background {
            ScriptTimelineWindowLevelController(isFloating: isPinned)
                .frame(width: 0, height: 0)
        }
        .preferredColorScheme(preferredColorScheme)
    }
}

private struct ScriptTimelineWindowLevelController: NSViewRepresentable {
    let isFloating: Bool

    func makeNSView(context: Context) -> ScriptTimelineWindowLevelView {
        let view = ScriptTimelineWindowLevelView()
        view.isFloating = isFloating
        return view
    }

    func updateNSView(_ view: ScriptTimelineWindowLevelView, context: Context) {
        view.isFloating = isFloating
    }
}

private final class ScriptTimelineWindowLevelView: NSView {
    var isFloating = false {
        didSet { updateWindowLevel() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowLevel()
    }

    private func updateWindowLevel() {
        window?.level = isFloating ? .floating : .normal
    }
}

/// Listen for scroll events without taking hit tests away from segment clicks or range dragging.
private struct ScriptTimelineScrollRegion: NSViewRepresentable {
    let viewport: ScriptTimelineViewport
    let onChange: (ScriptTimelineViewport) -> Void

    func makeNSView(context: Context) -> ScriptTimelineScrollView {
        let view = ScriptTimelineScrollView()
        view.viewport = viewport
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ScriptTimelineScrollView, context: Context) {
        view.viewport = viewport
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: ScriptTimelineScrollView, coordinator: ()) {
        view.stopMonitoring()
    }
}

private final class ScriptTimelineScrollView: NSView {
    var viewport = ScriptTimelineViewport.full
    var onChange: ((ScriptTimelineViewport) -> Void)?
    private var eventMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  !self.isHiddenOrHasHiddenAncestor else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point), self.visibleRect.contains(point),
                  !Self.isOverNativeScrollView(in: window, at: event.locationInWindow) else { return event }
            let rawDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            guard rawDelta.isFinite, rawDelta != 0 else { return event }
            // Consume momentum so navigation stops when the user's fingers stop.
            guard event.momentumPhase.isEmpty else { return nil }
            let delta = event.isDirectionInvertedFromDevice ? -rawDelta : rawDelta
            let next = self.viewport.panned(byScrollDelta: delta, precise: event.hasPreciseScrollingDeltas,
                                           viewportWidth: self.bounds.width)
            guard next != self.viewport else { return nil }
            // Update immediately: multiple wheel events can precede SwiftUI's next render.
            self.viewport = next
            self.onChange?(next)
            return nil
        }
    }

    /// Native scroll views and the list's custom thumb retain wheel-event ownership,
    /// even if a SwiftUI background/overlay gives this view a larger frame than the timeline bar.
    private static func isOverNativeScrollView(in window: NSWindow, at windowPoint: NSPoint) -> Bool {
        guard let contentView = window.contentView else { return false }
        var hitView = contentView.hitTest(contentView.convert(windowPoint, from: nil))
        while let view = hitView {
            if view is NSScrollView || view is ListScrollbar { return true }
            hitView = view.superview
        }
        return false
    }

    func stopMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

private struct ScriptTimelineNavigator: View {
    let distribution: ScriptDistribution
    let viewport: ScriptTimelineViewport
    let segmentColor: (ScriptDistribution.Segment) -> Color
    let selectedRowID: String?
    let height: CGFloat
    let onChange: (ScriptTimelineViewport) -> Void
    @State private var dragOrigin: ScriptTimelineViewport?
    private static let coordinateSpace = "ScriptTimelineNavigator"

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let selectionWidth = width * viewport.span
            ZStack(alignment: .leading) {
                // One Canvas draw instead of a view per segment, so dragging/following the range stays cheap.
                Canvas { context, size in
                    let barHeight = size.height / 2
                    let y = (size.height - barHeight) / 2
                    for segment in distribution.segments {
                        let rect = CGRect(x: size.width * segment.startFraction, y: y,
                                          width: size.width * segment.fraction, height: barHeight)
                        context.fill(Path(rect), with: .color(segmentColor(segment).opacity(0.65)))
                    }
                    // 选中块画在最上层，并保证最小宽度，缩小到全局总览时也能在范围框里看到
                    if let selected = distribution.segments.first(where: { $0.id == selectedRowID }) {
                        let minWidth: CGFloat = 4
                        let rawWidth = size.width * selected.fraction
                        let width = max(minWidth, rawWidth)
                        let x = min(size.width - width,
                                    max(0, size.width * selected.startFraction - (width - rawWidth) / 2))
                        let rect = CGRect(x: x, y: y - 1, width: width, height: barHeight + 2)
                        let path = Path(roundedRect: rect, cornerRadius: 1.5)
                        context.fill(path, with: .color(segmentColor(selected)))
                        context.fill(path, with: .color(ScriptRowSelectionStyle.fill))
                        context.stroke(path, with: .color(ScriptRowSelectionStyle.border),
                                       lineWidth: min(ScriptRowSelectionStyle.borderWidth, width / 2))
                    }
                }
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let center = Double(value.location.x / width)
                    onChange(ScriptTimelineViewport(start: center - viewport.span / 2, end: center + viewport.span / 2))
                })
                .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.yellow.opacity(0.16))
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.yellow, lineWidth: 2) }
                    .frame(width: selectionWidth, height: height)
                    .contentShape(Rectangle())
                    // 使用固定坐标空间：范围框本身随拖动移动，局部坐标会让位移来回抵消导致闪烁
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpace))
                        .onChanged { value in
                            if dragOrigin == nil { dragOrigin = viewport }
                            NSCursor.closedHand.set()
                            guard let origin = dragOrigin else { return }
                            onChange(origin.moved(by: Double(value.translation.width / width)))
                        }
                        .onEnded { _ in
                            dragOrigin = nil
                            NSCursor.openHand.set()
                        })
                    .pointerCursor(.openHand)
                    .offset(x: width * viewport.start)
                    .help("拖动范围框平移时间线，拖动两端调整范围；在上方时间线内滚轮前后移动。滚动文案时保持缩放比例")
                    .accessibilityLabel("时间线可视范围")
                    .accessibilityAdjustableAction { direction in
                        onChange(viewport.moved(by: direction == .increment ? 0.05 : -0.05))
                    }

                rangeHandle(isStart: true, width: width)
                    .offset(x: width * viewport.start - 4)
                rangeHandle(isStart: false, width: width)
                    .offset(x: width * viewport.end - 6)
            }
            .coordinateSpace(name: Self.coordinateSpace)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("时间线缩放导航条")
    }

    private func rangeHandle(isStart: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.yellow)
            .overlay { Capsule().fill(Color.black.opacity(0.45)).frame(width: 2, height: 8) }
            .frame(width: 10, height: height)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
                .onChanged { value in
                    if dragOrigin == nil { dragOrigin = viewport }
                    guard let origin = dragOrigin else { return }
                    let offset = Double(value.translation.width / width)
                    onChange(isStart ? origin.resizingStart(to: origin.start + offset)
                                     : origin.resizingEnd(to: origin.end + offset))
                }
                .onEnded { _ in dragOrigin = nil })
            .pointerCursor(.resizeLeftRight)
            .help(isStart ? "拖动左端调整时间线范围起点" : "拖动右端调整时间线范围终点")
            .accessibilityLabel(isStart ? "时间线范围起点" : "时间线范围终点")
            .accessibilityAdjustableAction { direction in
                let offset = direction == .increment ? 0.01 : -0.01
                onChange(isStart ? viewport.resizingStart(to: viewport.start + offset)
                                 : viewport.resizingEnd(to: viewport.end + offset))
            }
    }
}

private struct AnchorListView: View {
    @Bindable var model: AppModel
    @Binding var isSidebarVisible: Bool
    @Binding var isMaterialListVisible: Bool
    @State private var rowFilter = ScriptRowFilter()
    @State private var isSearchVisible = false
    @FocusState private var isSearchFocused: Bool
    @State private var editingIndex: Int?
    @State private var editingText = ""
    @State private var editingCursor = 0
    @State private var editingSession = UUID()
    @State private var pendingScrollRowID: String?
    @State private var revealedDeleteRowID: String?
    @State private var rowPulse: AnchorRowPulse?
    @State private var bindingExitTokens: [String: UUID] = [:]
    @State private var fadingBoundRowIDs: Set<String> = []
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedScriptRowID: String? {
        get { model.scriptTimeline.selectedRowID }
        nonmutating set { model.scriptTimeline.selectedRowID = newValue }
    }

    var body: some View {
        @Bindable var timeline = model.scriptTimeline
        let pacingHints = model.aRollPacingHints
        let distribution = ScriptDistribution(rows: model.rows, rollType: { model.rollType(for: $0) })
        let boundRowIDs = Set(model.assignments.compactMap { $0.value.isEmpty ? nil : $0.key })
        let rowAttributes = model.rows.map(model.filterAttributes(for:))
        let filteredRows = model.filteredRows.filter { isListed($0, attributes: rowAttributes) }
        let hasActiveFilters = rowFilter.isActive
        let isNarrowingRows = hasActiveFilters || !model.anchorSearchText.isEmpty
        let countableAttributes = rowAttributes.filter { !$0.isBlank }
        let visibleCount = filteredRows.filter { !rowAttributes[$0.index - 1].isBlank }.count
        let matchedRowIDs: Set<String>? = isNarrowingRows ? Set(filteredRows.map(\.id)) : nil

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if !isSidebarVisible {
                    Button {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            isSidebarVisible = true
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(IconActionButtonStyle(usesAnimation: false))
                    .hoverHelp("展开侧边栏")
                    .accessibilityLabel("展开侧边栏")
                    .pointerCursor()
                }
                Label("文案列表", systemImage: "text.badge.checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                WindowDragRegion()
                    .frame(minWidth: 8, maxWidth: .infinity, maxHeight: .infinity)
                if !isMaterialListVisible {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isMaterialListVisible = true
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(IconActionButtonStyle(usesAnimation: false))
                    .hoverHelp("展开素材列表")
                    .accessibilityLabel("展开素材列表")
                    .pointerCursor()
                }
                Button { model.isScriptEditorPresented = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(IconActionButtonStyle())
                .hoverHelp("编辑或导入视频文案")
                .accessibilityLabel("编辑或导入视频文案")
                .pointerCursor()
                Button { model.openAnimationPanel() } label: {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(IconActionButtonStyle())
                .hoverHelp("AI 动画助手：配置 DeepSeek、分析文案和复制制作提示词")
                .accessibilityLabel("AI 动画助手")
                .pointerCursor()
            }
            .padding(.horizontal, 16)
            .frame(height: ListPaneMetrics.headerHeight)
            .overlay(alignment: .bottom) { Divider() }

            scriptToolbar(visibleCount: visibleCount, totalCount: countableAttributes.count,
                          attributes: countableAttributes, isNarrowingRows: isNarrowingRows)

            if !distribution.segments.isEmpty {
                ScriptDistributionTimeline(
                    distribution: distribution,
                    aRollProductionMethod: { model.arollProductionMethod(for: $0) },
                    bRollProductionMethod: { model.brollProductionMethod(for: $0) },
                    shootingDevice: { model.shootingDevice(for: $0) },
                    matchedRowIDs: matchedRowIDs,
                    state: timeline,
                    selectedRowID: selectedScriptRowID,
                    onSelectRow: revealTimelineRow,
                    onOpenWindow: { openWindow(id: "script-timeline") }
                )
                    .padding(.horizontal, 16)
                    .frame(height: ListPaneMetrics.scriptTimelineHeight)
                    .overlay(alignment: .bottom) { Divider() }
            }

            if !model.hasScriptContent {
                ContentUnavailableView {
                    Label("先导入文案", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("选择或拖入 .txt / .md 文稿后即可按句整理，并开始匹配素材")
                } actions: {
                    Button("导入文案") {
                        model.importScript()
                    }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(ScriptFileDropTargetModifier { model.importScript(from: $0) })
            } else {
                ScrollViewReader { proxy in
                    List(selection: $timeline.selectedRowID) {
                        ForEach(filteredRows) { row in
                            SwipeToDeleteAnchorRow(
                                rowID: row.id,
                                revealedRowID: $revealedDeleteRowID,
                                isEnabled: editingIndex == nil,
                                onDelete: { deleteRow(row) }
                            ) {
                                AnchorRowView(
                                    row: row,
                                    model: model,
                                    isEditing: editingIndex == row.index - 1,
                                    isSelected: selectedScriptRowID == row.id,
                                    editingText: $editingText,
                                    editingCursor: editingCursor,
                                    editingSession: editingSession,
                                    beginEditing: { beginEditing(row) },
                                    finishEditing: { session in finishEditing(session: session) },
                                    splitAtSelection: { text, selection in
                                        splitRow(row, text: text, selection: selection)
                                    },
                                    mergeWithPrevious: { text in mergeRow(row, text: text) },
                                    pacingHint: pacingHints[row.id],
                                    pulse: rowPulse?.pulse(for: row.id),
                                    onBindingStarted: { retainRowForBinding(row.id) },
                                    onBindingFinished: { finishBindingExit(row.id) }
                                )
                            }
                            .id(row.id)
                            .tag(row.id)
                            .background(ScriptRowVisibilityMarker(rowID: row.id).accessibilityHidden(true))
                            .opacity(fadingBoundRowIDs.contains(row.id) ? 0 : 1)
                            .scaleEffect(fadingBoundRowIDs.contains(row.id) ? 0.96 : 1)
                            .offset(y: fadingBoundRowIDs.contains(row.id) ? -12 : 0)
                            .allowsHitTesting(bindingExitTokens[row.id] == nil)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.inset)
                    .scrollIndicators(.hidden)
                    .overlay {
                        AnchorListDropOutline(feedback: model.dropFeedback)
                    }
                    .background {
                        ScriptListVisibilityObserver(onChange: { [timeline] in timeline.visibleRows = $0 },
                                                     onSelectRow: selectScriptRow,
                                                     onDoubleClickRow: beginEditingRow)
                            .accessibilityHidden(true)
                    }
                    .overlay(alignment: .trailing) {
                        ListScrollbarOverlay()
                            .frame(width: 8)
                            .accessibilityHidden(true)
                    }
                    .onDrop(of: [UTType.fileURL], delegate: AnchorListDropDelegate(feedback: model.dropFeedback))
                    .onChange(of: pendingScrollRowID) { _, rowID in
                        guard let rowID else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(rowID, anchor: .center)
                            if pendingScrollRowID == rowID {
                                pendingScrollRowID = nil
                            }
                        }
                    }
                }
                .overlay {
                    if filteredRows.isEmpty {
                        ContentUnavailableView {
                            Label(hasActiveFilters ? "没有符合筛选的文案" : "没有匹配的文案",
                                  systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "magnifyingglass")
                        } description: {
                            if hasActiveFilters {
                                Text(model.anchorSearchText.isEmpty
                                    ? "当前筛选条件下没有符合条件的文案。"
                                    : "当前搜索与筛选条件下没有符合条件的文案。")
                            } else {
                                Text("试试其他文案关键词。")
                            }
                        } actions: {
                            Button(hasActiveFilters ? "清除筛选" : "清除搜索") {
                                if hasActiveFilters {
                                    rowFilter.reset()
                                } else {
                                    model.anchorSearchText = ""
                                }
                            }
                            .buttonStyle(.bordered)
                            .pointerCursor()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    }
                }
            }
        }
        .background(.windowBackground)
        // Binding completes asynchronously; animate the parent list, not just its row content.
        .animation(rowEditAnimation, value: boundRowIDs)
        .onChange(of: filteredRows.map(\.id)) { _, _ in
            revealedDeleteRowID = nil
        }
        .onChange(of: selectedScriptRowID) { _, _ in revealedDeleteRowID = nil }
        .onChange(of: matchedRowIDs, initial: true) { _, rowIDs in
            timeline.matchedRowIDs = rowIDs
        }
        .onChange(of: timeline.revealRequest) { _, request in
            if let request { revealTimelineRow(request.rowID) }
        }
        .onChange(of: model.rows.map(\.id)) { _, rowIDs in
            if let selectedScriptRowID, !rowIDs.contains(selectedScriptRowID) {
                self.selectedScriptRowID = nil
            }
        }
        .onChange(of: rowFilter) { _, _ in resetBindingExits() }
        .onChange(of: model.shootingDevices.map(\.id)) { _, _ in pruneDeletedDeviceFilters() }
        .onChange(of: model.destinationDirectoryURL) { _, _ in
            resetBindingExits()
            selectedScriptRowID = nil
            timeline.visibleRows = []
        }
        .onChange(of: boundRowIDs) { oldIDs, newIDs in
            for rowID in oldIDs.subtracting(newIDs) {
                // Undo or unbinding cancels a pending departure immediately.
                bindingExitTokens.removeValue(forKey: rowID)
                fadingBoundRowIDs.remove(rowID)
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced { resetBindingExits() }
        }
    }

    private func retainRowForBinding(_ rowID: String) {
        // Only retain rows that the filter will hide once they become bound B-roll.
        guard let row = model.rows.first(where: { $0.id == rowID }) else { return }
        let current = model.filterAttributes(for: row)
        let bound = ScriptRowFilter.Attributes(
            rollType: .bRoll, isBlank: current.isBlank, shootingDeviceID: current.shootingDeviceID,
            arollMethod: current.arollMethod, brollMethod: current.brollMethod, brollStatus: .bound
        )
        guard !rowFilter.matches(bound) else { return }
        // Retain the row before the asynchronous copy updates the status filter.
        bindingExitTokens[rowID] = UUID()
        fadingBoundRowIDs.remove(rowID)
    }

    private func finishBindingExit(_ rowID: String) {
        guard let token = bindingExitTokens[rowID] else { return }
        guard !reduceMotion, model.brollPreparationStatus(for: rowID) == .bound else {
            bindingExitTokens.removeValue(forKey: rowID)
            fadingBoundRowIDs.remove(rowID)
            return
        }

        Task { @MainActor in
            // Show the bound state briefly, then fade the card before closing its gap.
            try? await Task.sleep(for: .milliseconds(250))
            guard bindingExitTokens[rowID] == token else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                _ = fadingBoundRowIDs.insert(rowID)
            }
            try? await Task.sleep(for: .milliseconds(550))
            guard bindingExitTokens[rowID] == token else { return }
            withAnimation(.snappy(duration: 0.42, extraBounce: 0.04)) {
                bindingExitTokens.removeValue(forKey: rowID)
            }
            // Keep the removed card transparent while the List closes its gap.
            try? await Task.sleep(for: .milliseconds(450))
            guard bindingExitTokens[rowID] == nil else { return }
            fadingBoundRowIDs.remove(rowID)
        }
    }

    private func resetBindingExits() {
        bindingExitTokens.removeAll()
        fadingBoundRowIDs.removeAll()
    }

    private func deleteRow(_ row: AnchorRow) {
        revealedDeleteRowID = nil
        finishEditing(session: editingSession)
        model.deleteInlineRow(at: row.index - 1)
    }

    private func revealTimelineRow(_ rowID: String) {
        guard let index = model.rows.firstIndex(where: { $0.id == rowID }) else { return }
        finishEditing(session: editingSession)
        guard model.rows.indices.contains(index) else { return }
        let rowID = model.rows[index].id
        selectScriptRow(rowID)
        // Keep the current filter when the row is already listed; otherwise clear it to reveal the row.
        let row = model.rows[index]
        let query = model.anchorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isListed = (query.isEmpty || row.text.localizedCaseInsensitiveContains(query))
            && rowFilter.matches(model.filterAttributes(for: row))
        if !isListed {
            model.anchorSearchText = ""
            rowFilter.reset()
            resetBindingExits()
        }
        pendingScrollRowID = rowID
    }

    private func isListed(_ row: AnchorRow, attributes: [ScriptRowFilter.Attributes]) -> Bool {
        // Keep rows mid-edit or mid-binding-exit so they don't vanish under the cursor.
        if editingIndex == row.index - 1 || bindingExitTokens[row.id] != nil { return true }
        guard attributes.indices.contains(row.index - 1) else { return false }
        return rowFilter.matches(attributes[row.index - 1])
    }

    /// Drops conditions for devices that were deleted in settings.
    private func pruneDeletedDeviceFilters() {
        var valid: Set<String?> = [nil]
        for device in model.shootingDevices { valid.insert(device.id) }
        rowFilter.shootingDevices.retain(valid)
    }

    private func scriptToolbar(visibleCount: Int, totalCount: Int,
                               attributes: [ScriptRowFilter.Attributes], isNarrowingRows: Bool) -> some View {
        HStack(spacing: 8) {
            ScriptFilterButton(
                filter: $rowFilter,
                devices: deviceFilterOptions,
                attributes: attributes
            )

            if rowFilter.isActive {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(filterChips) { chip in
                            ScriptFilterChipView(chip: chip)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                Button("清除") {
                    rowFilter.reset()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .hoverHelp("清除全部筛选条件")
                .pointerCursor()
            } else {
                Text("显示全部文案")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }

            if isNarrowingRows {
                Text("\(visibleCount) / \(totalCount)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("当前显示的文案条数 / 全部文案条数")
            }

            scriptSearchControl
        }
        .padding(.horizontal, 12)
        .frame(height: ListPaneMetrics.anchorToolsHeight)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .background {
            Button("搜索文案") { showSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    private var deviceFilterOptions: [ScriptFilterOption<String?>] {
        model.shootingDevices.map { ScriptFilterOption(value: Optional($0.id), title: $0.name) }
            + [ScriptFilterOption(value: nil, title: "未设置设备")]
    }

    private var filterChips: [ScriptFilterChip] {
        var chips: [ScriptFilterChip] = []
        if !rowFilter.showsAroll {
            chips.append(ScriptFilterChip(id: "hide-a", scope: "A", title: "隐藏 A-roll", state: .exclude) {
                rowFilter.showsAroll = true
            })
        }
        if !rowFilter.showsBroll {
            chips.append(ScriptFilterChip(id: "hide-b", scope: "B", title: "隐藏 B-roll", state: .exclude) {
                rowFilter.showsBroll = true
            })
        }
        for option in deviceFilterOptions {
            guard let state = rowFilter.shootingDevices[option.value] else { continue }
            chips.append(ScriptFilterChip(id: "device-\(option.value ?? "none")", scope: "A",
                                          title: option.title, state: state) {
                rowFilter.shootingDevices[option.value] = nil
            })
        }
        for method in ArollProductionMethod.allCases {
            guard let state = rowFilter.arollMethods[method] else { continue }
            chips.append(ScriptFilterChip(id: "a-method-\(method.rawValue)", scope: "A",
                                          title: method.title, state: state) {
                rowFilter.arollMethods[method] = nil
            })
        }
        for method in BrollProductionMethod.allCases {
            guard let state = rowFilter.brollMethods[method] else { continue }
            chips.append(ScriptFilterChip(id: "b-method-\(method.rawValue)", scope: "B",
                                          title: method.title, state: state) {
                rowFilter.brollMethods[method] = nil
            })
        }
        for status in BrollPreparationStatus.allCases {
            guard let state = rowFilter.brollStatuses[status] else { continue }
            chips.append(ScriptFilterChip(id: "b-status-\(status.rawValue)", scope: "B",
                                          title: status.title, state: state) {
                rowFilter.brollStatuses[status] = nil
            })
        }
        return chips
    }

    @ViewBuilder
    private var scriptSearchControl: some View {
        if isSearchVisible || !model.anchorSearchText.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索文案", text: $model.anchorSearchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .focused($isSearchFocused)
                    .onExitCommand { closeSearch() }
                    .accessibilityLabel("搜索文案锚点")
                Button(action: closeSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(IconActionButtonStyle())
                .hoverHelp("清除并收起搜索")
                .accessibilityLabel("清除搜索")
                .pointerCursor()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: 180)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onChange(of: isSearchFocused) { _, isFocused in
                if !isFocused && model.anchorSearchText.isEmpty { isSearchVisible = false }
            }
        } else {
            Button(action: showSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(IconActionButtonStyle())
            .hoverHelp("搜索文案（⌘F）")
            .accessibilityLabel("搜索文案")
            .pointerCursor()
        }
    }

    private func showSearch() {
        isSearchVisible = true
        DispatchQueue.main.async { isSearchFocused = true }
    }

    private func closeSearch() {
        model.anchorSearchText = ""
        isSearchFocused = false
        isSearchVisible = false
    }

    private func selectScriptRow(_ rowID: String) {
        guard bindingExitTokens[rowID] == nil,
              let index = model.rows.firstIndex(where: { $0.id == rowID }) else { return }
        if let editingIndex, editingIndex != index { finishEditing(session: editingSession) }
        selectedScriptRowID = model.rows[index].id
    }

    private func beginEditing(_ row: AnchorRow) {
        revealedDeleteRowID = nil
        if editingIndex != row.index - 1 {
            finishEditing(session: editingSession)
        }
        selectedScriptRowID = row.id
        model.anchorSearchText = ""
        editingText = row.text
        editingCursor = (row.text as NSString).length
        editingSession = UUID()
        withAnimation(rowEditAnimation) {
            editingIndex = row.index - 1
        }
    }

    private func beginEditingRow(_ rowID: String) {
        guard let row = model.rows.first(where: { $0.id == rowID }), editingIndex != row.index - 1 else { return }
        beginEditing(row)
    }

    private func finishEditing(session: UUID) {
        guard session == editingSession, let index = editingIndex else { return }
        let text = editingText
        editingIndex = nil
        guard model.rows.indices.contains(index), model.rows[index].text != text else { return }
        let wasSelected = selectedScriptRowID == model.rows[index].id
        model.replaceInlineRow(at: index, with: text)
        if wasSelected { selectedScriptRowID = model.rows[index].id }
    }

    private func splitRow(_ row: AnchorRow, text: String, selection: NSRange) {
        guard editingIndex == row.index - 1 else { return }
        let index = row.index - 1
        editingSession = UUID()
        withAnimation(rowEditAnimation) {
            model.splitInlineRow(at: index, text: text, selection: selection)
            editingIndex = index + 1
            editingText = model.rows[index + 1].text
            editingCursor = 0
        }
        pendingScrollRowID = model.rows[index + 1].id
        selectedScriptRowID = model.rows[index + 1].id
        triggerPulse([
            model.rows[index].id: .splitSource,
            model.rows[index + 1].id: .splitInserted
        ])
    }

    private func mergeRow(_ row: AnchorRow, text: String) {
        guard editingIndex == row.index - 1 else { return }
        let index = row.index - 1
        guard index > 0 else { return }
        editingSession = UUID()
        var mergedCursor: Int?
        withAnimation(rowEditAnimation) {
            mergedCursor = model.mergeInlineRowWithPrevious(at: index, text: text)
            if let mergedCursor {
                editingIndex = index - 1
                editingText = model.rows[index - 1].text
                editingCursor = mergedCursor
            }
        }
        guard mergedCursor != nil else { return }
        pendingScrollRowID = model.rows[index - 1].id
        selectedScriptRowID = model.rows[index - 1].id
        triggerPulse([model.rows[index - 1].id: .merged])
    }

    private var rowEditAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.04)
    }

    private func triggerPulse(_ kinds: [String: AnchorRowPulse.Kind]) {
        let pulse = AnchorRowPulse(kinds: kinds)
        rowPulse = pulse
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        // Clear so rows scrolled back into view later don't replay the effect.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if rowPulse?.token == pulse.token {
                rowPulse = nil
            }
        }
    }
}

struct AnchorRowPulse: Equatable {
    enum Kind: Equatable {
        case splitSource
        case splitInserted
        case merged
    }

    struct Target: Equatable {
        let token: UUID
        let kind: Kind
    }

    let token = UUID()
    let kinds: [String: Kind]

    func pulse(for rowID: String) -> Target? {
        kinds[rowID].map { Target(token: token, kind: $0) }
    }
}

private struct SwipeToDeleteAnchorRow<Content: View>: View {
    let rowID: String
    @Binding var revealedRowID: String?
    let isEnabled: Bool
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDrag: Bool?
    @State private var dragStartOffset: CGFloat = 0

    private let actionWidth: CGFloat = 76
    private var offset: CGFloat {
        min(0, max(-actionWidth, (revealedRowID == rowID ? -actionWidth : 0) + dragOffset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            content()
                .background(.windowBackground, in: RoundedRectangle(cornerRadius: 10))
                .offset(x: offset)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .onChanged { value in
                            guard isEnabled else { return }
                            if isHorizontalDrag == nil {
                                isHorizontalDrag = abs(value.translation.width) > abs(value.translation.height) * 1.3
                                dragStartOffset = revealedRowID == rowID ? -actionWidth : 0
                            }
                            guard isHorizontalDrag == true else { return }
                            if revealedRowID != nil && revealedRowID != rowID {
                                revealedRowID = nil
                            }
                            dragOffset = value.translation.width
                        }
                        .onEnded { _ in
                            guard isHorizontalDrag == true else {
                                isHorizontalDrag = nil
                                dragOffset = 0
                                return
                            }
                            let shouldReveal = dragStartOffset + dragOffset < -actionWidth / 2
                            withAnimation(.easeOut(duration: 0.18)) {
                                revealedRowID = shouldReveal ? rowID : nil
                                dragOffset = 0
                            }
                            isHorizontalDrag = nil
                        },
                    including: isEnabled ? .all : .subviews
                )
            if offset < 0 {
                Button(role: .destructive, action: onDelete) {
                    VStack(spacing: 5) {
                        Image(systemName: "trash")
                        Text("删除").font(.caption)
                    }
                    .foregroundStyle(.white)
                    .frame(width: actionWidth - 6)
                    .frame(maxHeight: .infinity)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .frame(width: -offset, alignment: .trailing)
                .clipped()
                .help("删除这条文案（可撤销）")
                .accessibilityLabel("删除这条文案")
                .pointerCursor()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                revealedRowID = nil
                dragOffset = 0
                isHorizontalDrag = nil
            }
        }
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
    let titleCredit: String?
    let systemImage: String
    let showsTitleIcon: Bool
    let showsWaveUnderline: Bool
    let titleFont: Font?
    let count: String?
    let disablesTitleIconAnimation: Bool
    let actions: [PaneHeaderAction]

    init(
        title: String,
        titleCredit: String? = nil,
        systemImage: String,
        showsTitleIcon: Bool = true,
        showsWaveUnderline: Bool = false,
        titleFont: Font? = nil,
        count: String? = nil,
        disablesTitleIconAnimation: Bool = false,
        actions: [PaneHeaderAction] = []
    ) {
        self.title = title
        self.titleCredit = titleCredit
        self.systemImage = systemImage
        self.showsTitleIcon = showsTitleIcon
        self.showsWaveUnderline = showsWaveUnderline
        self.titleFont = titleFont
        self.count = count
        self.disablesTitleIconAnimation = disablesTitleIconAnimation
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if showsWaveUnderline {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title)
                            .font(titleFont ?? .system(size: 17, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if let titleCredit {
                            Text(titleCredit)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    HeaderWaveUnderline()
                        .stroke(
                            Color.accentColor.opacity(0.82),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 120, height: 11)
                        .overlay(alignment: .leading) {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.9), lineWidth: 1.5)
                                .frame(width: 8, height: 8)
                        }
                        .overlay(alignment: .trailing) {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.9), lineWidth: 1.5)
                                .frame(width: 8, height: 8)
                        }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .offset(y: 8)
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 8) {
                    if showsTitleIcon {
                        Image(systemName: systemImage)
                            .transaction { transaction in
                                if disablesTitleIconAnimation {
                                    transaction.animation = nil
                                }
                            }
                            .accessibilityHidden(true)
                    }
                    Text(title)
                }
                .font(titleFont ?? .system(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            }
            WindowDragRegion()
                .frame(minWidth: 8, maxWidth: .infinity, maxHeight: .infinity)
            if let count {
                Text(count)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            ForEach(actions.indices, id: \.self) { index in
                let headerAction = actions[index]
                Button(action: headerAction.action) {
                    Image(systemName: headerAction.systemImage)
                        .transaction { transaction in
                            if !headerAction.usesAnimation {
                                transaction.animation = nil
                            }
                        }
                }
                .buttonStyle(IconActionButtonStyle(usesAnimation: headerAction.usesAnimation))
                .transaction { transaction in
                    if !headerAction.usesAnimation {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
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

private struct HeaderWaveUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startX: CGFloat = 8
        let endX = rect.width - 8
        let centerY = rect.midY
        path.move(to: CGPoint(x: startX, y: centerY))
        for step in 1...32 {
            let progress = CGFloat(step) / 32
            let x = startX + (endX - startX) * progress
            let y = centerY + sin(progress * .pi * 4) * min(2.2, rect.height * 0.22)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

private struct PaneHeaderAction {
    let systemImage: String
    let help: String
    let accessibilityLabel: String
    let usesAnimation: Bool
    let action: () -> Void

    init(
        systemImage: String,
        help: String,
        accessibilityLabel: String? = nil,
        usesAnimation: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.help = help
        self.accessibilityLabel = accessibilityLabel ?? help
        self.usesAnimation = usesAnimation
        self.action = action
    }
}

private struct AnchorRowView: View {
    let row: AnchorRow
    @Bindable var model: AppModel
    let isEditing: Bool
    let isSelected: Bool
    @Binding var editingText: String
    let editingCursor: Int
    let editingSession: UUID
    let beginEditing: () -> Void
    let finishEditing: (UUID) -> Void
    let splitAtSelection: (String, NSRange) -> Void
    let mergeWithPrevious: (String) -> Void
    let pacingHint: ARollPacingHint?
    var pulse: AnchorRowPulse.Target? = nil
    var onBindingStarted: () -> Void = {}
    var onBindingFinished: () -> Void = {}
    @StateObject private var dropState = AnchorDropState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseGlow: Double = 0
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOffset: CGFloat = 0
    @State private var editEntryGlow: Double = 0
    @State private var editEntryScale: CGFloat = 1
    @State private var isNoteEditorPresented = false
    @State private var isPacingDetailsPresented = false
    @State private var noteDraft = ""
    @State private var didCopyAnimationPrompt = false
    @State private var animationCopyToken: UUID?

    private var assets: [BrollAsset] { model.assets(for: row.id) }
    private var rowNote: String { model.note(for: row.id) }
    private var isDropTarget: Bool { dropState.isActive }
    private var isBinding: Bool { model.bindingRowIDs.contains(row.id) }
    private var isPendingBinding: Bool {
        !isBinding && model.rollType(for: row.id) == .bRoll && assets.isEmpty
    }
    private var isBroll: Bool { model.rollType(for: row.id) == .bRoll }

    private var rowFill: Color {
        if isSelected { return ScriptRowSelectionStyle.fill }
        return isDropTarget ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.025)
    }

    private var rowBorder: Color {
        if isSelected { return ScriptRowSelectionStyle.border }
        return isDropTarget || isBinding ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.07)
    }

    private var rowBorderWidth: CGFloat {
        isSelected ? ScriptRowSelectionStyle.borderWidth : (isDropTarget ? 1.5 : 0.5)
    }

    // Pulse tint follows the row's roll type: blue for A-roll, green for B-roll.
    private var pulseTint: Color { isBroll ? .green : .blue }

    private func runPulse() {
        guard let pulse else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            pulseGlow = 1
            guard !reduceMotion else { return }
            switch pulse.kind {
            case .splitInserted:
                pulseOffset = -14
                pulseScale = 0.98
            case .splitSource:
                pulseScale = 0.99
            case .merged:
                pulseScale = 0.955
            }
        }
        withAnimation(.spring(response: 0.38, dampingFraction: pulse.kind == .merged ? 0.52 : 0.7)) {
            pulseOffset = 0
            pulseScale = 1
        }
        withAnimation(.easeOut(duration: 0.85).delay(0.18)) {
            pulseGlow = 0
        }
    }

    private func runEditingEntryMotion() {
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            editEntryScale = 0.988
            editEntryGlow = 1
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
            editEntryScale = 1
        }
        withAnimation(.easeOut(duration: 0.52)) {
            editEntryGlow = 0
        }
    }

    private var editingEntryHighlight: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(pulseTint.opacity(0.045 * editEntryGlow))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(pulseTint.opacity(0.24 * editEntryGlow), lineWidth: 1)
            }
            .allowsHitTesting(false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                BrollStatusIndicator(
                    isBroll: isBroll,
                    selection: model.brollPreparationStatus(for: row.id),
                    isBound: !assets.isEmpty,
                    onToggle: { model.setBrollPreparationStatus($0, for: row.id) }
                )
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 2) {
                        Text("\(String(format: "%02d", row.index))  BR\(String(format: "%03d", row.index))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(isDropTarget ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                        if let pacingHint, !isBroll, !isEditing {
                            ARollPacingReminder(hint: pacingHint, isExpanded: $isPacingDetailsPresented)
                            .padding(.leading, 7)
                        }
                        Spacer(minLength: 8)
                        Button {
                            noteDraft = rowNote
                            isNoteEditorPresented = true
                        } label: {
                            Label("备注", systemImage: rowNote.isEmpty ? "square.and.pencil" : "note.text")
                                .modifier(RowMetaControlChrome(isActive: !rowNote.isEmpty))
                        }
                        .buttonStyle(.plain)
                        .help(rowNote.isEmpty ? "添加备注" : "编辑备注")
                        .accessibilityLabel(rowNote.isEmpty ? "为这条文案添加备注" : "编辑这条文案的备注")
                        .pointerCursor()
                        .popover(isPresented: $isNoteEditorPresented, arrowEdge: .top) {
                            AnchorNoteEditorView(
                                rowNumber: row.index,
                                text: $noteDraft,
                                onCancel: { isNoteEditorPresented = false },
                                onSave: {
                                    model.setNote(noteDraft, for: row.id)
                                    isNoteEditorPresented = false
                                }
                            )
                        }
                        if let task = model.animationTask(for: row.id) {
                            Button {
                                didCopyAnimationPrompt = model.copyAnimationPrompt(task)
                                animationCopyToken = UUID()
                            } label: {
                                Label(didCopyAnimationPrompt ? "已复制" : "复制提示词", systemImage: didCopyAnimationPrompt ? "checkmark" : "doc.on.doc")
                                    .fixedSize(horizontal: true, vertical: false)
                                    .modifier(RowMetaControlChrome(isActive: false))
                            }
                            .buttonStyle(.plain)
                            .help("复制这条文案的完整动画制作提示词")
                            .accessibilityLabel(didCopyAnimationPrompt ? "已复制动画制作提示词" : "复制动画制作提示词")
                            .pointerCursor()
                        }
                        if isBroll {
                            RollProductionMethodMenu(
                                selection: model.brollProductionMethod(for: row.id),
                                rollType: .bRoll,
                                onSelect: { model.setBrollProductionMethod($0, for: row.id) }
                            )
                        } else {
                            ShootingDeviceMenu(
                                selection: model.shootingDevice(for: row.id),
                                devices: model.shootingDevices,
                                onSelect: { model.setShootingDevice($0, for: row.id) }
                            )
                            RollProductionMethodMenu(
                                selection: model.arollProductionMethod(for: row.id),
                                rollType: .aRoll,
                                onSelect: { model.setArollProductionMethod($0, for: row.id) }
                            )
                        }
                        RollTypeTag(
                            isBroll: isBroll,
                            assetCount: assets.count,
                            onTap: { model.toggleRollType(for: row.id) }
                        )
                    }
                    if isEditing {
                        InlineAnchorEditor(
                            text: $editingText,
                            initialCursor: editingCursor,
                            session: editingSession,
                            onFinish: finishEditing,
                            onSplit: splitAtSelection,
                            onMerge: mergeWithPrevious
                        )
                        .id(editingSession)
                        .frame(minHeight: 22)
                        .transition(.opacity)
                    } else {
                        Text(row.text.isEmpty ? "双击输入文案" : row.text)
                            .font(.system(size: 16))
                            .foregroundStyle(row.text.isEmpty ? .tertiary : .primary)
                            .lineSpacing(2)
                            .frame(minHeight: 22, alignment: .topLeading)
                            .contentShape(Rectangle())
                            .background(ScriptRowVisibilityMarker(rowID: row.id, tracksTextEditing: true)
                                .accessibilityHidden(true))
                            .onTapGesture(count: 2, perform: beginEditing)
                            .pointerCursor()
                            .transition(.opacity)
                    }
                }
            }
            .contentShape(Rectangle())

            if isPendingBinding {
                PendingAssetChip()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !assets.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(assets) { asset in
                        AssetChip(
                            asset: asset,
                            model: model,
                            isDropTarget: isDropTarget,
                            isSelected: model.sourceFile(for: asset)?.url.standardizedFileURL
                                == model.selectedSourceFileURL?.standardizedFileURL
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if isBinding {
                BindingProgressChip()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let pacingHint, isPacingDetailsPresented, !isBroll, !isEditing {
                ARollPacingDetails(hint: pacingHint) {
                    isPacingDetailsPresented = false
                    // Use the existing roll-type action so this remains undoable.
                    if model.rollType(for: row.id) == .aRoll {
                        model.toggleRollType(for: row.id)
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(pulseTint.opacity(0.13 * pulseGlow))
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: rowBorderWidth)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(pulseTint.opacity(0.75 * pulseGlow), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .overlay { editingEntryHighlight }
        .scaleEffect(pulseScale * editEntryScale)
        .offset(y: pulseOffset)
        .onAppear(perform: runPulse)
        .onChange(of: pulse) { _, _ in runPulse() }
        .onChange(of: isEditing) { _, editing in
            if editing { runEditingEntryMotion() }
        }
        .onChange(of: pacingHint) { _, hint in
            if hint == nil { isPacingDetailsPresented = false }
        }
        .task(id: animationCopyToken) {
            guard animationCopyToken != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                didCopyAnimationPrompt = false
            } catch {}
        }
        .onDrop(
            of: [UTType.fileURL],
            delegate: FileDropDelegate(
                rowID: row.id, model: model, feedback: model.dropFeedback, rowState: dropState,
                onBindingStarted: onBindingStarted, onBindingFinished: onBindingFinished
            )
        )
        .animation(.snappy(duration: 0.2), value: assets.count)
        .animation(.snappy(duration: 0.2), value: isPendingBinding)
        .animation(.snappy(duration: 0.2), value: isBinding)
    }
}

private struct ARollPacingReminder: View {
    let hint: ARollPacingHint
    @Binding var isExpanded: Bool
    @State private var isHovered = false

    // Muted amber stays distinct from green preparation states in both appearances.
    static let tint = Color(nsColor: .systemOrange).opacity(0.72)

    private var elapsed: String { String(format: "%.1f", hint.cumulativeSeconds) }

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text("连续 ≈\(elapsed)s")
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
            }
            .foregroundStyle(Self.tint.opacity(isHovered || isExpanded ? 1 : 0.78))
            .padding(.horizontal, 4)
            .frame(height: 22)
            .background(Self.tint.opacity(isHovered || isExpanded ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("截至本条，连续 A-roll 约 \(elapsed) 秒，建议补一段 B-roll。点击查看。")
        .accessibilityLabel("连续 A-roll 约 \(elapsed) 秒，超过 \(hint.settings.thresholdLabel) 秒，建议补充 B-roll")
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .accessibilityHint("展开或收起估算说明，并可将本条设为 B-roll")
        .pointerCursor()
    }
}

private struct ARollPacingDetails: View {
    let hint: ARollPacingHint
    let onMarkBroll: () -> Void

    private var range: String {
        hint.startRowIndex == hint.endRowIndex
            ? "第 \(hint.startRowIndex) 条"
            : "第 \(hint.startRowIndex)–\(hint.endRowIndex) 条"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("这里可以补一段 B-roll")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text("\(range) · 整段约 \(String(format: "%.1f", hint.totalSeconds)) 秒")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("将本条设为 B-roll", action: onMarkBroll)
                    .controlSize(.small)
                    .pointerCursor()
            }
            Text("只补一部分时，双击文案并按回车拆分，再标记 B-roll。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("按 \(hint.settings.charactersPerMinute) 字/分钟、连续 \(hint.settings.thresholdLabel) 秒估算，忽略标点和空白；实际节奏以口播为准。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

private struct AnchorNoteEditorView: View {
    let rowNumber: Int
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BR\(String(format: "%03d", rowNumber)) 制作备注")
                .font(.system(size: 15, weight: .semibold))

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(5)

                if text.isEmpty {
                    Text("记下要做的画面、动作、场景、搜索词或生成提示…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 13)
                        .padding(.leading, 11)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 128)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .pointerCursor()
                Button("保存", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .pointerCursor()
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct ScriptFilterOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var systemImage: String?

    var id: Value { value }
}

private struct ScriptFilterChip: Identifiable {
    let id: String
    let scope: String
    let title: String
    let state: ScriptFilterState
    let onRemove: () -> Void
}

private struct ScriptFilterChipView: View {
    let chip: ScriptFilterChip

    private var tint: Color { chip.state == .include ? .accentColor : .red }

    var body: some View {
        HStack(spacing: 4) {
            Text(chip.scope)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 14)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Image(systemName: chip.state == .include ? "checkmark" : "minus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(chip.title)
                .font(.system(size: 12, weight: .medium))
                .strikethrough(chip.state == .exclude, color: tint)
                .lineLimit(1)
            Button(action: chip.onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHelp("移除这个条件")
            .accessibilityLabel("移除条件")
            .pointerCursor()
        }
        .padding(.leading, 4)
        .padding(.trailing, 3)
        .frame(height: 24)
        .background(tint.opacity(0.08), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.7) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(chip.scope)-roll \(chip.state == .include ? "只看" : "不看")\(chip.title)")
    }
}

/// Toolbar button that opens the combined A-roll / B-roll filter.
private struct ScriptFilterButton: View {
    @Binding var filter: ScriptRowFilter
    let devices: [ScriptFilterOption<String?>]
    let attributes: [ScriptRowFilter.Attributes]
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(filter.isActive ? Color.accentColor : Color.secondary)
                Text("筛选")
                if filter.isActive {
                    Text("\(filter.activeConditionCount)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.accentColor, in: Capsule())
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(filter.isActive ? 0.15 : 0.06), lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScriptFilterPopover(filter: $filter, devices: devices, attributes: attributes)
        }
        .hoverHelp("按 A-roll / B-roll 的设备、制作方式和准备状态筛选")
        .accessibilityLabel("筛选文案")
        .accessibilityValue(filter.isActive ? "\(filter.activeConditionCount) 个条件" : "未筛选")
        .pointerCursor()
    }
}

private struct ScriptFilterPopover: View {
    @Binding var filter: ScriptRowFilter
    let devices: [ScriptFilterOption<String?>]
    let attributes: [ScriptRowFilter.Attributes]

    private var aRolls: [ScriptRowFilter.Attributes] { attributes.filter { $0.rollType == .aRoll } }
    private var bRolls: [ScriptRowFilter.Attributes] { attributes.filter { $0.rollType == .bRoll } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("筛选文案")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if filter.isActive {
                    Button("全部清除") { filter.reset() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .pointerCursor()
                }
            }
            Text("点一下只看，再点一下不看，第三下取消。A-roll 和 B-roll 各自筛选后一起显示。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(alignment: .top, spacing: 16) {
                column(title: "A-roll", count: aRolls.count, isShown: $filter.showsAroll) {
                    section("拍摄设备", isActive: filter.shootingDevices.isActive,
                            clear: { filter.shootingDevices.removeAll() }) {
                        ForEach(devices) { device in
                            optionRow(device.title, systemImage: device.value == nil ? "questionmark.circle" : "camera",
                                      count: aRolls.filter { $0.shootingDeviceID == device.value }.count,
                                      state: filter.shootingDevices[device.value]) {
                                filter.shootingDevices.cycle(device.value)
                            }
                        }
                    }
                    section("制作方式", isActive: filter.arollMethods.isActive,
                            clear: { filter.arollMethods.removeAll() }) {
                        ForEach(ArollProductionMethod.allCases) { method in
                            optionRow(method.title, systemImage: method.systemImage,
                                      count: aRolls.filter { $0.arollMethod == method }.count,
                                      state: filter.arollMethods[method]) {
                                filter.arollMethods.cycle(method)
                            }
                        }
                    }
                }

                Divider()

                column(title: "B-roll", count: bRolls.count, isShown: $filter.showsBroll) {
                    section("制作方式", isActive: filter.brollMethods.isActive,
                            clear: { filter.brollMethods.removeAll() }) {
                        ForEach(BrollProductionMethod.allCases) { method in
                            optionRow(method.title, systemImage: method.systemImage,
                                      count: bRolls.filter { $0.brollMethod == method }.count,
                                      state: filter.brollMethods[method]) {
                                filter.brollMethods.cycle(method)
                            }
                        }
                    }
                    section("准备状态", isActive: filter.brollStatuses.isActive,
                            clear: { filter.brollStatuses.removeAll() }) {
                        ForEach(BrollPreparationStatus.allCases) { status in
                            optionRow(status.title, systemImage: status.systemImage,
                                      count: bRolls.filter { $0.brollStatus == status }.count,
                                      state: filter.brollStatuses[status]) {
                                filter.brollStatuses.cycle(status)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 480)
    }

    private func column<Content: View>(title: String, count: Int, isShown: Binding<Bool>,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: isShown) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel("显示 \(title)")

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .disabled(!isShown.wrappedValue)
            .opacity(isShown.wrappedValue ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, isActive: Bool, clear: @escaping () -> Void,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if isActive {
                    Button("清除", action: clear)
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .pointerCursor()
                }
            }
            content()
        }
    }

    private func optionRow(_ title: String, systemImage: String, count: Int,
                           state: ScriptFilterState?, action: @escaping () -> Void) -> some View {
        let tint: Color = switch state {
        case .include: .accentColor
        case .exclude: .red
        case nil: .secondary
        }
        let stateDescription = switch state {
        case .include: "只看"
        case .exclude: "不看"
        case nil: "不限"
        }
        let stateImage = switch state {
        case .include: "checkmark.circle.fill"
        case .exclude: "minus.circle.fill"
        case nil: "circle"
        }
        return Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: stateImage)
                    .foregroundStyle(tint)
                .frame(width: 14)
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .foregroundStyle(state == .exclude ? Color.secondary : Color.primary)
                    .strikethrough(state == .exclude, color: .red)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(stateDescription)，\(count) 条")
        .accessibilityHint("点击在只看、不看、不限之间切换")
        .pointerCursor()
    }
}

private struct ShootingDeviceMenu: View {
    let selection: ShootingDevice?
    let devices: [ShootingDevice]
    let onSelect: (ShootingDevice?) -> Void

    var body: some View {
        Menu {
            Button { onSelect(nil) } label: {
                if selection == nil {
                    Label("无", systemImage: "checkmark")
                } else {
                    Text("无")
                }
            }
            ForEach(devices) { device in
                Button { onSelect(device) } label: {
                    if selection?.id == device.id {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
            if let selection, !devices.contains(where: { $0.id == selection.id }) {
                Divider()
                Label(selection.name, systemImage: "checkmark")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "camera")
                Text(selection?.name ?? "拍摄设备")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .modifier(RowMetaControlChrome())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("选择这个 A-roll 的拍摄设备，可在左下角设置中编辑设备选项")
        .accessibilityLabel("拍摄设备：\(selection?.name ?? "无")")
        .pointerCursor()
    }
}

private struct RollProductionMethodMenu<Method: RollProductionMethod>: View {
    let selection: Method
    let rollType: AnchorRollType
    let onSelect: (Method) -> Void

    private var title: String { selection.title }

    var body: some View {
        Menu {
            ForEach(Array(Method.allCases)) { method in
                Button {
                    onSelect(method)
                } label: {
                    if method == selection {
                        Label(method.title, systemImage: "checkmark")
                    } else {
                        Text(method.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selection.systemImage)
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .modifier(RowMetaControlChrome())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("选择这个 \(rollType.title) 的制作方式")
        .accessibilityLabel("制作方式：\(selection.title)")
        .pointerCursor()
    }
}

/// Leading status circle, Reminders-style: gray hollow = 待准备, green check = 素材就绪, green link = 已绑定.
private struct BrollStatusIndicator: View {
    let isBroll: Bool
    let selection: BrollPreparationStatus
    let isBound: Bool
    let onToggle: (BrollPreparationStatus) -> Void

    /// Bumped on each 待准备 → 素材就绪 tap to drive the keyframe feedback.
    @State private var feedbackTrigger = 0
    /// Shows the ready state locally while the feedback plays, before the model commits
    /// (so rows filtered out of 待准备 don't vanish mid-animation).
    @State private var isCommittingReady = false

    private static let feedbackDuration: TimeInterval = 0.75

    private var displayedStatus: BrollPreparationStatus {
        if isBound { return .bound }
        return isCommittingReady ? .ready : selection
    }

    private var nextStatus: BrollPreparationStatus {
        displayedStatus == .pending ? .ready : .pending
    }

    private var tint: Color {
        switch displayedStatus {
        case .pending: return Color.secondary.opacity(0.6)
        case .ready, .bound: return .green
        }
    }

    var body: some View {
        Group {
            if !isBroll {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .help("A-roll")
                    .accessibilityLabel("A-roll")
            } else if isBound {
                icon
                    .help("已绑定素材")
                    .accessibilityLabel("B-roll 已绑定")
            } else {
                Button(action: toggle) {
                    icon
                        .background(readyRipple)
                }
                .buttonStyle(.plain)
                .disabled(isCommittingReady)
                .help("\(displayedStatus.title) · 点击标记为\(nextStatus.title)")
                .accessibilityLabel("B-roll 准备进度：\(displayedStatus.title)")
                .accessibilityHint("点击切换为\(nextStatus.title)")
                .pointerCursor()
            }
        }
        .frame(width: 18, height: 18)
    }

    private var icon: some View {
        Image(systemName: displayedStatus.systemImage)
            .font(.system(size: 16, weight: displayedStatus == .pending ? .light : .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .contentShape(Circle())
            .animation(.snappy(duration: 0.28), value: displayedStatus)
            .keyframeAnimator(initialValue: 1.0, trigger: feedbackTrigger) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.78, duration: 0.14)
                    SpringKeyframe(1.22, duration: 0.24, spring: .smooth)
                    SpringKeyframe(1.0, duration: 0.36, spring: .bouncy)
                }
            }
    }

    /// Green ring that expands and fades out when a row is marked 素材就绪.
    private var readyRipple: some View {
        Circle()
            .stroke(Color.green, lineWidth: 1.5)
            .keyframeAnimator(initialValue: RippleValues(), trigger: feedbackTrigger) { ring, values in
                ring
                    .scaleEffect(values.scale)
                    .opacity(values.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.8, duration: 0.01)
                    CubicKeyframe(2.0, duration: 0.7)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.8, duration: 0.01)
                    CubicKeyframe(0, duration: 0.7)
                }
            }
            .allowsHitTesting(false)
    }

    private func toggle() {
        guard nextStatus == .ready else {
            onToggle(.pending)
            return
        }
        isCommittingReady = true
        feedbackTrigger += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.feedbackDuration) {
            onToggle(.ready)
            isCommittingReady = false
        }
    }
}

private struct RippleValues {
    var scale: CGFloat = 1
    var opacity: Double = 0
}

/// Low-emphasis text control used in the row header: no fill until hovered.
private struct RowMetaControlChrome: ViewModifier {
    var isActive = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.medium))
            .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Color.primary.opacity(isHovered ? 0.07 : 0),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct BindingProgressChip: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在绑定素材…")
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.accentColor)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.8)
        }
        .padding(.leading, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在绑定素材")
    }
}

private struct PendingAssetChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.to.line")
            Text("拖入素材以绑定")
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(.tertiary)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
        }
        .padding(.leading, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("B-roll 待绑定素材；从素材列表拖拽素材到这条文案")
    }
}

private struct InlineAnchorEditor: NSViewRepresentable {
    @Binding var text: String
    let initialCursor: Int
    let session: UUID
    let onFinish: (UUID) -> Void
    let onSplit: (String, NSRange) -> Void
    let onMerge: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> AnchorTextView {
        let view = AnchorTextView()
        view.delegate = context.coordinator
        view.string = text
        view.font = .systemFont(ofSize: 16)
        view.textColor = .labelColor
        view.drawsBackground = false
        view.isRichText = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.onSplit = { [weak coordinator = context.coordinator] value, selection in
            coordinator?.parent.onSplit(value, selection)
        }
        view.onMerge = { [weak coordinator = context.coordinator] value in
            coordinator?.parent.onMerge(value)
        }
        view.onEscape = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.parent.onFinish(coordinator.creationSession)
        }

        let cursor = initialCursor
        DispatchQueue.main.async { [weak view] in
            guard let view, let window = view.window else { return }
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: min(cursor, (view.string as NSString).length), length: 0))
        }
        return view
    }

    func updateNSView(_ view: AnchorTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text {
            view.string = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AnchorTextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 300, 40)
        let displayText = text.isEmpty ? " " : text
        let bounds = (displayText as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 16)]
        )
        return CGSize(width: width, height: max(22, ceil(bounds.height) + 2))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineAnchorEditor
        let creationSession: UUID

        init(parent: InlineAnchorEditor) {
            self.parent = parent
            creationSession = parent.session
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFinish(creationSession)
        }
    }
}

private final class AnchorTextView: NSTextView {
    var onSplit: ((String, NSRange) -> Void)?
    var onMerge: ((String) -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let hasCommandModifier = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if !hasCommandModifier && (event.keyCode == 36 || event.keyCode == 76) {
            onSplit?(string, selectedRange())
            return
        }
        if !hasCommandModifier && event.keyCode == 51 {
            let selection = selectedRange()
            if selection.location == 0 && selection.length == 0 {
                onMerge?(string)
                return
            }
        }
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

private struct RollTypeTag: View {
    let isBroll: Bool
    let assetCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            tag
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var tag: some View {
        HStack(spacing: 3) {
            Text(isBroll ? "B-roll" : "A-roll")
                .foregroundStyle(isBroll ? Color.green : Color.secondary)
            if isBroll, assetCount > 1 {
                Text("×\(assetCount)")
                    .monospacedDigit()
            }
        }
        .modifier(RowMetaControlChrome())
        .help("点击切换为\(isBroll ? "A-roll" : "B-roll")")
        .accessibilityLabel("\(isBroll ? "B-roll" : "A-roll")，点击切换为\(isBroll ? "A-roll" : "B-roll")")
    }
}

private struct AssetChip: View {
    let asset: BrollAsset
    @Bindable var model: AppModel
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
                HStack(spacing: 6) {
                    Image(systemName: mediaSymbol)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.orange : Color.primary.opacity(0.7))
                    Text(asset.outputName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.sourceFile(for: asset) == nil)
            .hoverHelp("归档名：\(asset.outputName)\n\n完整媒体文件名：\(asset.sourceName)\n\n源文件：\(model.sourceOriginLabel(for: asset))")
            .accessibilityLabel("定位源文件 \(asset.sourceName)")
            .pointerCursor(model.sourceFile(for: asset) == nil ? .arrow : .pointingHand)

            Button {
                model.reveal(asset)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(IconActionButtonStyle(usesAnimation: false))
            .hoverHelp("在 Finder 中打开剪辑文件夹并选中归档副本")
            .accessibilityLabel("在剪辑文件夹中显示 \(asset.outputName)")
            .pointerCursor()

            Button {
                model.revealSource(asset)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(IconActionButtonStyle(usesAnimation: false))
            .hoverHelp("在 Finder 中打开源文件所在目录并选中原始素材")
            .accessibilityLabel("在源目录中显示 \(asset.sourceName)")
            .pointerCursor()

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
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            isSelected
                ? Color.orange.opacity(0.12)
                : (isDropTarget ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.045)),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.6), lineWidth: 1)
            }
        }
        .padding(.leading, 28)
        .contextMenu {
            Button {
                model.reveal(asset)
            } label: {
                Label("在 Finder 新标签页中显示", systemImage: "arrow.up.forward.app")
            }
        }
    }
}

private struct MaterialListHeader: View {
    @Bindable var model: AppModel
    @Binding var isDirectoryPopoverPresented: Bool
    @Binding var isMaterialListVisible: Bool
    @Binding var isMediaPreviewVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "素材列表",
                systemImage: "photo.stack",
                actions: paneHeaderActions
            )

            HStack(spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: model.sourceDirectories.isEmpty ? "folder" : "folder.fill")
                        .foregroundStyle(model.sourceDirectories.isEmpty ? Color.orange : Color.accentColor)
                    Text(model.sourceDirectoryName)
                        .font(.system(size: 16))
                        .foregroundStyle(model.sourceDirectories.isEmpty ? Color.orange : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .hoverHelp(model.sourceDirectoryTooltip)
                    Button {
                        model.chooseSourceDirectory()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .hoverHelp("添加一个或多个素材来源目录")
                    .accessibilityLabel("添加素材来源目录")
                    .pointerCursor()

                    if let currentSourceDirectoryURL = model.sourceDirectoryURL {
                        Button {
                            model.removeCurrentSourceDirectory()
                        } label: {
                            Image(systemName: "folder.badge.minus")
                        }
                        .buttonStyle(IconActionButtonStyle())
                        .hoverHelp("从本项目素材来源中移除，不移动里面的素材：\(currentSourceDirectoryURL.lastPathComponent)")
                        .accessibilityLabel("移除当前素材目录：\(currentSourceDirectoryURL.lastPathComponent)")
                        .pointerCursor()
                    }

                    Button {
                        isDirectoryPopoverPresented = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .accessibilityLabel("管理常用素材目录")
                    .pointerCursor()
                    .popover(isPresented: $isDirectoryPopoverPresented, arrowEdge: .trailing) {
                        DirectoryManagerPopover(model: model) {
                            isDirectoryPopoverPresented = false
                        }
                        .frame(width: 310)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: 40)
                .padding(.horizontal, 10)
                .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
                }
                .modifier(DirectoryDropTargetModifier { model.acceptSourceDirectoryDrop($0) })

                MediaFilterPicker(selection: $model.mediaFilter)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
            .frame(height: ListPaneMetrics.toolsHeight)
            .background(.quaternary.opacity(0.2))
            .overlay(alignment: .bottom) {
                Divider()
            }

        }
    }

    private var paneHeaderActions: [PaneHeaderAction] {
        var actions = [
            PaneHeaderAction(systemImage: "arrow.clockwise", help: "刷新素材列表", usesAnimation: false) {
                model.refreshSourceFiles(recoverSourceDirectories: true)
            }
        ]

        if !isMediaPreviewVisible {
            actions.append(
                PaneHeaderAction(systemImage: "sidebar.right", help: "展开当前媒体栏", usesAnimation: false) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isMediaPreviewVisible = true
                    }
                }
            )
        }

        actions.append(
            PaneHeaderAction(systemImage: "sidebar.left", help: "收起素材列表", usesAnimation: false) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isMaterialListVisible = false
                }
            }
        )
        return actions
    }
}

private struct DirectoryManagerPopover: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("素材目录", systemImage: "folder.badge.gearshape")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if model.sourceDirectoryURL != nil && !model.isCurrentSourceDirectorySaved {
                    Button {
                        model.saveCurrentSourceDirectory()
                    } label: {
                        Label("收藏当前", systemImage: "bookmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 14))
                    .accessibilityLabel("收藏当前素材目录")
                    .hoverHelp("将当前目录加入常用目录")
                    .pointerCursor()
                }
            }

            DirectoryPopoverAction(
                title: "添加素材目录…",
                systemImage: "folder.badge.plus",
                isPrimary: true,
                onDirectoryDrop: { url in
                    model.acceptSourceDirectoryDrop(url)
                    dismiss()
                }
            ) {
                model.chooseSourceDirectory()
                dismiss()
            }

            if model.sourceDirectoryURL != nil {
                DirectoryPopoverAction(title: "在 Finder 新标签页中打开当前目录", systemImage: "arrow.up.forward.app") {
                    model.revealSourceDirectory()
                    dismiss()
                }
            }

            DirectoryPopoverAction(
                title: "添加并收藏新目录…",
                systemImage: "bookmark",
                onDirectoryDrop: { url in
                    model.acceptSourceDirectoryDrop(url, saveAsFavorite: true)
                    dismiss()
                }
            ) {
                model.chooseAndSaveSourceDirectory()
                dismiss()
            }

            if !model.sourceDirectories.isEmpty {
                Divider()

                Text("本项目来源（\(model.sourceDirectories.count)）")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 4) {
                        if model.sourceDirectories.count > 1 {
                            Button {
                                model.selectSourceDirectory(nil)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.stack.3d.up")
                                        .foregroundStyle(Color.accentColor)
                                    Text("全部来源")
                                        .font(.system(size: 14, weight: .medium))
                                    Spacer(minLength: 2)
                                    if model.selectedSourceDirectoryID == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 7)
                                .frame(height: 36)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("显示全部素材来源")
                            .pointerCursor()
                            .background(model.selectedSourceDirectoryID == nil
                                ? Color.accentColor.opacity(0.12)
                                : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                        }
                        ForEach(model.sourceDirectories) { directory in
                            HStack(spacing: 8) {
                                Button {
                                    if model.isSourceDirectoryAvailable(id: directory.id) {
                                        model.selectSourceDirectory(directory.id)
                                        dismiss()
                                    } else {
                                        model.reconnectProjectSourceDirectory(directory.id)
                                        if model.isSourceDirectoryAvailable(id: directory.id) {
                                            model.selectSourceDirectory(directory.id)
                                            dismiss()
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: model.isSourceDirectoryAvailable(id: directory.id)
                                            ? "folder.fill"
                                            : "folder.badge.questionmark")
                                            .foregroundStyle(model.isSourceDirectoryAvailable(id: directory.id)
                                                ? Color.accentColor
                                                : Color.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(directory.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .lineLimit(1)
                                            Text(directory.path)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer(minLength: 2)
                                        if model.selectedSourceDirectoryID == directory.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(model.isSourceDirectoryAvailable(id: directory.id)
                                    ? "显示素材目录：\(directory.name)"
                                    : "重新连接素材目录：\(directory.name)")
                                .pointerCursor()
                                if !model.isSourceDirectoryAvailable(id: directory.id) {
                                    Button {
                                        model.reconnectProjectSourceDirectory(directory.id)
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(IconActionButtonStyle(usesAnimation: false))
                                    .hoverHelp("重新连接这个素材来源")
                                    .accessibilityLabel("重新连接素材目录：\(directory.name)")
                                    .pointerCursor()
                                }
                                Button(role: .destructive) {
                                    model.removeProjectSourceDirectory(directory.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(IconActionButtonStyle(usesAnimation: false))
                                .hoverHelp("从本项目素材来源中移除")
                                .accessibilityLabel("移除素材目录：\(directory.name)")
                                .pointerCursor()
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(model.selectedSourceDirectoryID == directory.id
                                ? Color.accentColor.opacity(0.12)
                                : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                .frame(height: min(CGFloat(model.sourceDirectories.count) * 46
                    + (model.sourceDirectories.count > 1 ? 40 : 0), 200))
            }

            Divider()

            Text("常用目录")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            if model.savedDirectories.isEmpty {
                Text("选择常用目录后，会将它添加到本项目来源。")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(model.savedDirectories) { directory in
                            SavedDirectoryRow(
                                directory: directory,
                                isSelected: model.isSourceDirectoryConnected(path: directory.path),
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
            }
        }
        .padding(14)
    }
}

private struct DirectoryPopoverAction: View {
    let title: String
    let systemImage: String
    var isPrimary = false
    var onDirectoryDrop: ((URL) -> Void)?
    let action: () -> Void
    @State private var isHovered = false

    init(
        title: String,
        systemImage: String,
        isPrimary: Bool = false,
        onDirectoryDrop: ((URL) -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isPrimary = isPrimary
        self.onDirectoryDrop = onDirectoryDrop
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 16, weight: isPrimary ? .semibold : .regular))
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
        .modifier(OptionalDirectoryDropTargetModifier(onDrop: onDirectoryDrop))
    }
}

private struct OptionalDirectoryDropTargetModifier: ViewModifier {
    let onDrop: ((URL) -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onDrop {
            content.modifier(DirectoryDropTargetModifier(onDrop: onDrop))
        } else {
            content
        }
    }
}

private struct ScriptFileDropTargetModifier: ViewModifier {
    let onDrop: (URL) -> Void
    @State private var isDropTarget = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.055))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    Color.accentColor.opacity(0.65),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                                )
                        }
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget, perform: acceptDrop)
            .accessibilityHint(isDropTarget
                ? "松开以导入 .txt 或 .md 文稿"
                : "也可以从 Finder 拖入 .txt 或 .md 文稿")
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        FileURLDropLoader.loadURLs(from: fileProviders) { urls in
            guard !urls.isEmpty else { return }
            let scriptURL = urls.first {
                let fileExtension = $0.pathExtension.lowercased()
                return fileExtension == "txt" || fileExtension == "md"
            } ?? urls[0]
            onDrop(scriptURL)
        }
        return true
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
                        Text("已连接")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 16))
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHelp("添加到当前项目素材来源：\(directory.name)")
            .accessibilityLabel("添加素材目录：\(directory.name)")
            .pointerCursor()

            Menu {
                Button("移除常用目录", systemImage: "trash", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
                    .modifier(IconActionButtonChrome(isPressed: false, usesAnimation: true))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("管理常用目录")
            .pointerCursor()
        }
        .background(isSelected ? Color.green.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct DetailView: View {
    @Bindable var model: AppModel
    @Binding var isMaterialListVisible: Bool
    @Binding var isMediaPreviewVisible: Bool
    @State private var selectedSourceFileURLs: Set<URL> = []
    @State private var isDirectoryPopoverPresented = false
    @FocusState private var isMaterialListFocused: Bool
    @StateObject private var previewController = MediaPreviewController()

    private var selectedSourceFileURL: URL? {
        selectedSourceFileURLs.first
    }

    var body: some View {
        Group {
            if isMaterialListVisible && isMediaPreviewVisible {
                HSplitView {
                    materialList
                        .frame(minWidth: WorkspacePaneMetrics.minimumSourceWidth, idealWidth: 440, maxWidth: .infinity)
                        .background(SplitViewAutosaveInstaller(
                            name: "com.keyknock.BrollNamer.media-columns-with-preview"
                        ))

                    mediaPreview
                }
            } else if isMaterialListVisible {
                materialList
                    .frame(minWidth: WorkspacePaneMetrics.minimumSourceWidth, maxWidth: .infinity)
            } else {
                Color.clear
            }
        }
        .background(.windowBackground)
        .onChange(of: model.visibleSourceFiles) { _, files in
            let availableURLs = Set(files.map(\.url))
            selectedSourceFileURLs = selectedSourceFileURLs.intersection(availableURLs)
            model.selectedSourceFileURL = selectedSourceFileURLs.first
        }
        .onChange(of: selectedSourceFileURLs) { _, urls in
            model.selectedSourceFileURL = urls.first
            if urls.isEmpty {
                previewController.load(url: nil)
            }
        }
    }

    private var mediaPreview: some View {
        MediaPreviewView(
            file: selectedSourceFileURL.flatMap(model.sourceFile(at:)),
            controller: previewController,
            model: model,
            isMediaPreviewVisible: $isMediaPreviewVisible
        )
        .frame(minWidth: WorkspacePaneMetrics.minimumPreviewWidth, idealWidth: 480, maxWidth: .infinity)
    }

    private var materialList: some View {
        let visibleFiles = model.visibleSourceFiles

        // The nested split view may restore a wider pane than the available space.
        // Measure the allocated width so headers and empty states cannot cover neighbours.
        return GeometryReader { pane in
            VStack(spacing: 0) {
                MaterialListHeader(
                    model: model,
                    isDirectoryPopoverPresented: $isDirectoryPopoverPresented,
                    isMaterialListVisible: $isMaterialListVisible,
                    isMediaPreviewVisible: $isMediaPreviewVisible
                )

                if visibleFiles.isEmpty {
                    ContentUnavailableView {
                        Label(
                            model.sourceDirectories.isEmpty ? "再导入素材目录" : "没有符合条件的素材",
                            systemImage: "photo.stack"
                        )
                    } description: {
                        Text(model.sourceDirectories.isEmpty
                            ? "选择或拖入目录后即可浏览其中的视频和图片"
                            : "调整筛选条件，或添加其他素材目录")
                    } actions: {
                        Button("添加素材目录") {
                            model.chooseSourceDirectory()
                        }
                        .buttonStyle(.bordered)
                        .pointerCursor()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(OptionalDirectoryDropTargetModifier(
                        onDrop: model.sourceDirectories.isEmpty
                            ? { model.acceptSourceDirectoryDrop($0) }
                            : nil
                    ))
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
                                        .padding(.horizontal, 10)
                                        .id(file.url.standardizedFileURL.path)
                                        .onTapGesture {
                                            selectSourceFile(file)
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                                .frame(width: geometry.size.width)
                            }
                            .scrollIndicators(.hidden)
                            .contentMargins(.trailing, 0, for: .scrollContent)
                            .overlay(alignment: .trailing) {
                                ListScrollbarOverlay()
                                    .frame(width: 8)
                                    .accessibilityHidden(true)
                            }
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
            .frame(width: pane.size.width, height: pane.size.height)
            .clipped()
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
    @Bindable var model: AppModel
    @Binding var isMediaPreviewVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "当前媒体",
                systemImage: file?.kind.systemImage ?? "photo.stack",
                count: file == nil ? "未选择" : nil,
                disablesTitleIconAnimation: true,
                actions: [
                    PaneHeaderAction(systemImage: "sidebar.right", help: "收起当前媒体栏", usesAnimation: false) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isMediaPreviewVisible = false
                        }
                    }
                ]
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
                        Text("\(file.sourceDirectoryName) · \(MediaFormatting.bytes(file.byteCount))")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button {
                        QuickLookPreviewController.shared.preview(url: file.url)
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(IconActionButtonStyle(usesAnimation: false))
                    .hoverHelp("使用 Quick Look 打开素材")
                    .accessibilityLabel("使用 Quick Look 打开素材")
                    .pointerCursor()

                    Button {
                        model.revealInFinder(file.url)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(IconActionButtonStyle(usesAnimation: false))
                    .hoverHelp("在 Finder 新标签页中显示素材")
                    .accessibilityLabel("在 Finder 新标签页中显示素材")
                    .pointerCursor()
                } else {
                    Text("从素材列表选择文件")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .font(.system(size: 14))
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
                }
            } else {
                ContentUnavailableView {
                    Label("选择素材", systemImage: "photo.stack")
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                } description: {
                    Text("从素材列表选择")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.windowBackground)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
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
    @Bindable var model: AppModel
    let isAssigned: Bool
    let isSelected: Bool

    @State private var isHovered = false

    private var rowFill: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.orange.opacity(0.16)) }
        if isHovered { return AnyShapeStyle(.quinary) }
        return AnyShapeStyle(.clear)
    }

    private var assignedAssets: [BrollAsset] {
        model.assignedAssets(for: file)
    }

    private var subtitle: String {
        var parts = [file.sourceDirectoryName, MediaFormatting.bytes(file.byteCount)]
        if let date = file.modificationDate {
            parts.append(date.formatted(.dateTime.month().day().hour().minute()))
        }
        return parts.joined(separator: " · ")
    }

    private var hoverDetails: String {
        let archiveNames = assignedAssets.map(\.outputName)
        let archiveLines = archiveNames.isEmpty
            ? "归档名：未归档"
            : archiveNames.map { "归档名：\($0)" }.joined(separator: "\n\n")
        return "\(archiveLines)\n\n来源目录：\(file.sourceDirectoryName)\n\n完整媒体路径：\(file.url.path)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%03d", index))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                .frame(width: 26, alignment: .trailing)

            MediaThumbnailView(file: file)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if isAssigned {
                AssignedBadge(count: max(assignedAssets.count, 1))
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onDrag {
            return NSItemProvider(object: file.url as NSURL)
        }
        .pointerCursor()
        .hoverHelp(hoverDetails)
        .accessibilityElement(children: .combine)
        .accessibilityValue([isSelected ? "已选中" : nil, isAssigned ? "已绑定" : nil].compactMap { $0 }.joined(separator: "，"))
    }
}

private struct AssignedBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text(count > 1 ? "已绑定 ×\(count)" : "已绑定")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(Color.green)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.12), in: Capsule())
        .fixedSize()
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
            // A transient tooltip would dismiss any popover that is already open (e.g. one the
            // hovered button just presented), so stay hidden while another popover is visible.
            let tooltipWindow = popover.contentViewController?.view.window
            guard !NSApp.windows.contains(where: {
                $0.isVisible && $0 !== tooltipWindow && String(describing: type(of: $0)).contains("Popover")
            }) else { return }

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
        let font = NSFont.systemFont(ofSize: 14)
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
            .font(.system(size: 14))
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

    private let thumbnailSize = CGSize(width: 80, height: 45)

    var body: some View {
        let maxPixelSize = max(1, Int(ceil(max(thumbnailSize.width, thumbnailSize.height) * displayScale)))

        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()

                if file.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(4)
                }
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
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
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
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
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $model.scriptText)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    }

                HStack {
                    Picker(
                        "拆分方式",
                        selection: Binding(
                            get: { model.splitMode },
                            set: { model.setSplitMode($0) }
                        )
                    ) {
                        ForEach(SplitMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    .pointerCursor()

                    Spacer()

                    Text("当前生成 \(model.scriptAnchorCount) 个锚点")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                HStack {
                    Button {
                        model.importScript()
                    } label: {
                        Label("导入 .txt / .md", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.destinationDirectoryURL == nil)
                    .hoverHelp(model.destinationDirectoryURL == nil
                        ? "请先选择剪辑项目文件夹，再导入文案"
                        : "导入 .txt / .md 文稿")
                    .pointerCursor()

                    Text("一行一个锚点；句号模式会按中文和英文句末标点拆分。点击“完成”后保存到 A-roll/正确文案.txt。")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .navigationTitle("编辑 / 导入文案")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        model.confirmScript()
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
    }
}
