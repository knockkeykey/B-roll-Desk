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

private enum ListPaneMetrics {
    static let headerHeight: CGFloat = WindowHeaderMetrics.height
    static let toolsHeight: CGFloat = 54
    static let anchorToolsHeight: CGFloat = toolsHeight
}

private enum AnchorPreparationFilter: Hashable {
    case all
    case pendingPreparation
    case pendingBinding
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
    @State private var isMediaPreviewVisible = true

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

    private var minimumContentWidth: CGFloat {
        let sidebarWidth: CGFloat = isSidebarVisible ? 270 : 0
        let detailWidth: CGFloat = isMediaPreviewVisible ? 780 : 420
        let outerDividerCount: CGFloat = isSidebarMounted ? 2 : 1
        let previewDividerCount: CGFloat = isMediaPreviewVisible ? 1 : 0
        return sidebarWidth + 390 + detailWidth + (outerDividerCount + previewDividerCount) * 8
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
                        minWidth: isSidebarVisible ? 270 : 0,
                        idealWidth: isSidebarVisible ? 300 : 0,
                        maxWidth: isSidebarVisible ? 360 : 0
                    )
                    .opacity(isSidebarVisible ? 1 : 0)
                    .clipped()
                    .allowsHitTesting(isSidebarVisible)
                    .accessibilityHidden(!isSidebarVisible)
                    .animation(.easeInOut(duration: 0.24), value: isSidebarVisible)
            }
            AnchorListView(model: model, isSidebarVisible: sidebarVisibility)
                .frame(minWidth: 390, idealWidth: 760, maxWidth: 760)
                .background(SplitViewAutosaveInstaller(
                    name: isSidebarMounted
                        ? "com.keyknock.BrollNamer.main-columns-v3-with-sidebar"
                        : "com.keyknock.BrollNamer.main-columns-v3-without-sidebar"
                ))
            DetailView(model: model, isMediaPreviewVisible: $isMediaPreviewVisible)
                .frame(minWidth: isMediaPreviewVisible ? 780 : 420, idealWidth: 820)
        }
        .onDrop(of: [UTType.fileURL], delegate: WholeWindowDirectoryDropDelegate(feedback: folderDragFeedback))
        .environmentObject(folderDragFeedback)
        .frame(minWidth: minimumContentWidth)
        .padding(.top, -28)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $model.isScriptEditorPresented) {
            ScriptEditorSheet(model: model)
        }
        .sheet(isPresented: $model.isManifestPreviewPresented) {
            ManifestPreviewSheet(text: model.manifestPreviewText)
        }
        .alert(item: $model.alert) { alert in
            if alert.action == .openAccessibilitySettings {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("打开辅助功能设置")) {
                        model.openAccessibilitySettings()
                    },
                    secondaryButton: .cancel(Text("好"))
                )
            }

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
                                ManifestIconButton(title: "在 Finder 中显示给 Codex 的 JSON 对照表", systemImage: "arrow.up.forward.app") {
                                    model.revealManifest()
                                }
                                ManifestIconButton(title: "预览给 Codex 的 JSON 对照表", systemImage: "eye") {
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
                Label("Codex JSON 对照表预览", systemImage: "curlybraces")
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

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value, format: .number)
                .font(.caption.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help("\(label)：\(value)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
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
                    SidebarStatisticMetric(value: model.aRollAnchorCount, label: "A-roll", tint: .blue)
                    SidebarStatisticMetric(value: model.bRollAnchorCount, label: "B-roll", tint: .green)
                    SidebarStatisticMetric(value: model.pendingBrollCount, label: "未绑定", tint: .secondary)
                }

                BrollStatisticsView(model: model)
            }
        }
    }
}

private struct BrollProductionMethodStat: Identifiable {
    let method: BrollProductionMethod
    let count: Int

    var id: String { method.rawValue }

    var color: Color {
        switch method {
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

private struct AnchorListView: View {
    @Bindable var model: AppModel
    @Binding var isSidebarVisible: Bool
    @State private var selectedProductionMethods: Set<BrollProductionMethod> = []
    @State private var preparationFilter = AnchorPreparationFilter.all
    @State private var editingIndex: Int?
    @State private var editingText = ""
    @State private var editingCursor = 0
    @State private var editingSession = UUID()
    @State private var pendingScrollRowID: String?
    @State private var revealedDeleteRowID: String?

    var body: some View {
        let filteredRows = model.filteredRows.filter { row in
            let rollType = model.rollType(for: row.id)
            if !selectedProductionMethods.isEmpty {
                guard rollType == .bRoll,
                      selectedProductionMethods.contains(model.brollProductionMethod(for: row.id)) else {
                    return false
                }
            }
            switch preparationFilter {
            case .all:
                return true
            case .pendingPreparation:
                return rollType == .bRoll && model.brollPreparationStatus(for: row.id) == .pending
            case .pendingBinding:
                return rollType == .bRoll && model.brollPreparationStatus(for: row.id) != .bound
            }
        }
        let hasActiveFilters = !selectedProductionMethods.isEmpty || preparationFilter != .all
        let isShowingPendingBroll = preparationFilter == .pendingPreparation && selectedProductionMethods.isEmpty
        let isShowingUnboundBroll = preparationFilter == .pendingBinding && selectedProductionMethods.isEmpty

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
                Spacer(minLength: 4)
                Button { model.isScriptEditorPresented = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(IconActionButtonStyle())
                .hoverHelp("编辑或导入视频文案")
                .accessibilityLabel("编辑或导入视频文案")
                .pointerCursor()
            }
            .padding(.horizontal, 16)
            .frame(height: ListPaneMetrics.headerHeight)
            .overlay(alignment: .bottom) { Divider() }

            GeometryReader { geometry in
                let spacing: CGFloat = 6
                let productionMethodFilterWidth = min(210, max(142, geometry.size.width * 0.31))
                let preparationFilterWidth = min(210, max(150, geometry.size.width * 0.34))

                let searchField = HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索文案", text: $model.anchorSearchText)
                        .textFieldStyle(.plain)
                        .lineLimit(1)
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
                .padding(.vertical, 7)
                .frame(minWidth: 72, maxWidth: .infinity)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: spacing) {
                    searchField
                    BrollProductionMethodFilterMenu(selection: $selectedProductionMethods)
                        .frame(width: productionMethodFilterWidth)

                    Picker("", selection: $preparationFilter) {
                        Text("全部").tag(AnchorPreparationFilter.all)
                        Text("待准备").tag(AnchorPreparationFilter.pendingPreparation)
                        Text("待绑定").tag(AnchorPreparationFilter.pendingBinding)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .frame(width: preparationFilterWidth)
                    .accessibilityLabel("筛选文案状态")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(height: ListPaneMetrics.anchorToolsHeight)
            .overlay(alignment: .bottom) {
                Divider()
            }

            if !model.hasScriptContent {
                ContentUnavailableView {
                    Label("先导入文案", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("选择文案文件后即可按句整理，并开始匹配素材")
                } actions: {
                    Button("导入文案") {
                        model.importScript()
                    }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRows.isEmpty {
                ContentUnavailableView {
                    Label(
                        isShowingPendingBroll
                            ? "没有待准备的 B-roll"
                            : (isShowingUnboundBroll ? "没有待绑定的 B-roll" : "没有匹配的文案"),
                        systemImage: isShowingPendingBroll || isShowingUnboundBroll ? "checkmark.circle" : "magnifyingglass"
                    )
                } description: {
                    if preparationFilter == .pendingPreparation || preparationFilter == .pendingBinding {
                        if isShowingPendingBroll {
                            Text(model.anchorSearchText.isEmpty
                                ? "当前没有待准备的 B-roll。"
                                : "当前搜索结果中没有待准备的 B-roll。")
                        } else if isShowingUnboundBroll {
                            Text(model.anchorSearchText.isEmpty
                                ? "当前没有待绑定的 B-roll。"
                                : "当前搜索结果中没有待绑定的 B-roll。")
                        } else {
                            Text("当前搜索与筛选条件下没有符合条件的文案。")
                        }
                    } else if hasActiveFilters {
                        Text(model.anchorSearchText.isEmpty
                            ? "当前筛选条件下没有符合条件的文案。"
                            : "当前搜索与筛选条件下没有符合条件的文案。")
                    } else {
                        Text("试试其他文案关键词。")
                    }
                } actions: {
                    Button(hasActiveFilters ? "重置筛选" : "清除搜索") {
                        if hasActiveFilters {
                            selectedProductionMethods.removeAll()
                            preparationFilter = .all
                        } else {
                            model.anchorSearchText = ""
                        }
                    }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
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
                                    editingText: $editingText,
                                    editingCursor: editingCursor,
                                    editingSession: editingSession,
                                    beginEditing: { beginEditing(row) },
                                    finishEditing: { session in finishEditing(session: session) },
                                    splitAtSelection: { text, selection in
                                        splitRow(row, text: text, selection: selection)
                                    },
                                    mergeWithPrevious: { text in mergeRow(row, text: text) }
                                )
                            }
                            .id(row.id)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.inset)
                    .scrollIndicators(.hidden)
                    .overlay {
                        AnchorListDropOutline(feedback: model.dropFeedback)
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
            }
        }
        .background(.windowBackground)
        .onChange(of: filteredRows.map(\.id)) { _, _ in
            revealedDeleteRowID = nil
        }
    }

    private func deleteRow(_ row: AnchorRow) {
        revealedDeleteRowID = nil
        finishEditing(session: editingSession)
        model.deleteInlineRow(at: row.index - 1)
    }

    private func beginEditing(_ row: AnchorRow) {
        revealedDeleteRowID = nil
        if editingIndex != row.index - 1 {
            finishEditing(session: editingSession)
        }
        model.anchorSearchText = ""
        editingIndex = row.index - 1
        editingText = row.text
        editingCursor = (row.text as NSString).length
        editingSession = UUID()
    }

    private func finishEditing(session: UUID) {
        guard session == editingSession, let index = editingIndex else { return }
        let text = editingText
        editingIndex = nil
        guard model.rows.indices.contains(index), model.rows[index].text != text else { return }
        model.replaceInlineRow(at: index, with: text)
    }

    private func splitRow(_ row: AnchorRow, text: String, selection: NSRange) {
        guard editingIndex == row.index - 1 else { return }
        let index = row.index - 1
        editingSession = UUID()
        model.splitInlineRow(at: index, text: text, selection: selection)
        editingIndex = index + 1
        editingText = model.rows[index + 1].text
        editingCursor = 0
        pendingScrollRowID = model.rows[index + 1].id
    }

    private func mergeRow(_ row: AnchorRow, text: String) {
        guard editingIndex == row.index - 1 else { return }
        let index = row.index - 1
        guard index > 0 else { return }
        editingSession = UUID()
        guard let cursor = model.mergeInlineRowWithPrevious(at: index, text: text) else { return }
        editingIndex = index - 1
        editingText = model.rows[index - 1].text
        editingCursor = cursor
        pendingScrollRowID = model.rows[index - 1].id
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
                            .fixedSize(horizontal: true, vertical: false)
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
                .frame(minWidth: 150, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
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
            Spacer(minLength: 8)
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
    @Binding var editingText: String
    let editingCursor: Int
    let editingSession: UUID
    let beginEditing: () -> Void
    let finishEditing: (UUID) -> Void
    let splitAtSelection: (String, NSRange) -> Void
    let mergeWithPrevious: (String) -> Void
    @StateObject private var dropState = AnchorDropState()
    @State private var isNoteEditorPresented = false
    @State private var noteDraft = ""

    private var assets: [BrollAsset] { model.assets(for: row.id) }
    private var rowNote: String { model.note(for: row.id) }
    private var isDropTarget: Bool { dropState.isActive }
    private var isPendingBinding: Bool {
        model.rollType(for: row.id) == .bRoll && assets.isEmpty
    }
    private var isBroll: Bool { model.rollType(for: row.id) == .bRoll }

    private var rowFill: Color {
        isDropTarget ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.025)
    }

    private var rowBorder: Color {
        isDropTarget ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.07)
    }

    private var rowBorderWidth: CGFloat {
        isDropTarget ? 1.5 : 0.5
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
                        if isBroll {
                            BrollProductionMethodMenu(
                                selection: model.brollProductionMethod(for: row.id),
                                onSelect: { model.setBrollProductionMethod($0, for: row.id) }
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
                        .frame(minHeight: 26)
                    } else {
                        Text(row.text.isEmpty ? "双击输入文案" : row.text)
                            .font(.system(size: 16))
                            .foregroundStyle(row.text.isEmpty ? .tertiary : .primary)
                            .lineSpacing(2)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2, perform: beginEditing)
                            .pointerCursor()
                    }
                    if !rowNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "note.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(rowNote)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .truncationMode(.tail)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .contentShape(Rectangle())

            if isPendingBinding {
                PendingAssetChip()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !assets.isEmpty {
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
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: rowBorderWidth)
        }
        .onDrop(
            of: [UTType.fileURL],
            delegate: FileDropDelegate(rowID: row.id, model: model, feedback: model.dropFeedback, rowState: dropState)
        )
        .animation(.snappy(duration: 0.2), value: assets.count)
        .animation(.snappy(duration: 0.2), value: isPendingBinding)
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

private struct BrollProductionMethodFilterMenu: View {
    @Binding var selection: Set<BrollProductionMethod>
    @State private var isPresented = false

    private var selectionSummary: String {
        BrollProductionMethod.allCases
            .filter(selection.contains)
            .map(\.title)
            .joined(separator: "、")
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(selection.isEmpty ? Color.secondary : Color.accentColor)
                Text(selection.isEmpty ? "制作方式" : "制作方式（\(selection.count)）")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(selection.isEmpty ? 0.06 : 0.15), lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("制作方式")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if !selection.isEmpty {
                        Button("清除") {
                            selection.removeAll()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .pointerCursor()
                    }
                }

                Divider()

                ForEach(BrollProductionMethod.allCases) { method in
                    let isSelected = selection.contains(method)
                    Button {
                        toggle(method)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            Text(method.title)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
            .padding(12)
            .frame(width: 220)
        }
        .help(selection.isEmpty ? "按制作方式筛选 B-roll" : "制作方式：\(selectionSummary)")
        .accessibilityLabel("按制作方式筛选")
        .accessibilityValue(selection.isEmpty ? "全部制作方式" : selectionSummary)
        .pointerCursor()
    }

    private func toggle(_ method: BrollProductionMethod) {
        if selection.contains(method) {
            selection.remove(method)
        } else {
            selection.insert(method)
        }
    }
}

private struct BrollProductionMethodMenu: View {
    let selection: BrollProductionMethod
    let onSelect: (BrollProductionMethod) -> Void

    private var title: String { selection.title }

    var body: some View {
        Menu {
            ForEach(BrollProductionMethod.allCases) { method in
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
        .help("选择这个 B-roll 的制作方式")
        .accessibilityLabel("制作方式：\(selection.title)")
        .pointerCursor()
    }
}

/// Leading status circle, Reminders-style: gray hollow = 待准备, blue check = 素材就绪, green link = 已绑定.
private struct BrollStatusIndicator: View {
    let isBroll: Bool
    let selection: BrollPreparationStatus
    let isBound: Bool
    let onToggle: (BrollPreparationStatus) -> Void

    private var displayedStatus: BrollPreparationStatus {
        isBound ? .bound : selection
    }

    private var nextStatus: BrollPreparationStatus {
        selection == .pending ? .ready : .pending
    }

    private var tint: Color {
        switch displayedStatus {
        case .pending: return Color.secondary.opacity(0.6)
        case .ready: return .accentColor
        case .bound: return .green
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
                Button {
                    onToggle(nextStatus)
                } label: {
                    icon
                }
                .buttonStyle(.plain)
                .help("\(selection.title) · 点击标记为\(nextStatus.title)")
                .accessibilityLabel("B-roll 准备进度：\(selection.title)")
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
            .animation(.snappy(duration: 0.18), value: displayedStatus)
    }
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
        return CGSize(width: width, height: max(26, ceil(bounds.height) + 4))
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
                HStack(spacing: 8) {
                    Image(systemName: mediaSymbol)
                        .foregroundStyle(isSelected ? Color.orange : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.outputName)
                            .font(.system(size: 13, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("源文件：\(model.sourceOriginLabel(for: asset))")
                            .font(.system(size: 12))
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
                        .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)
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
                .frame(height: 40)
                .padding(.horizontal, 10)
                .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
                }
                .modifier(DirectoryDropTargetModifier { model.acceptSourceDirectoryDrop($0) })

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

    private var paneHeaderActions: [PaneHeaderAction] {
        var actions = [
            PaneHeaderAction(systemImage: "arrow.clockwise", help: "刷新素材列表", usesAnimation: false) {
                model.refreshSourceFiles()
            }
        ]

        if !isMediaPreviewVisible {
            actions.append(
                PaneHeaderAction(systemImage: "chevron.left", help: "展开当前媒体栏", usesAnimation: false) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isMediaPreviewVisible = true
                    }
                }
            )
        }

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
                        ForEach(model.sourceDirectories) { directory in
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
                            .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                .frame(height: min(CGFloat(model.sourceDirectories.count) * 46, 160))
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
    @Binding var isMediaPreviewVisible: Bool
    @State private var selectedSourceFileURLs: Set<URL> = []
    @State private var isDirectoryPopoverPresented = false
    @FocusState private var isMaterialListFocused: Bool
    @StateObject private var previewController = MediaPreviewController()

    private var selectedSourceFileURL: URL? {
        selectedSourceFileURLs.first
    }

    var body: some View {
        let visibleFiles = model.visibleSourceFiles

        HSplitView {
            VStack(spacing: 0) {
                MaterialListHeader(
                    model: model,
                    isDirectoryPopoverPresented: $isDirectoryPopoverPresented,
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
                            ? "选择目录后即可浏览其中的视频和图片"
                            : "调整筛选条件，或添加其他素材目录")
                    } actions: {
                        Button("添加素材目录") {
                            model.chooseSourceDirectory()
                        }
                        .buttonStyle(.bordered)
                        .pointerCursor()
                        .modifier(DirectoryDropTargetModifier { model.acceptSourceDirectoryDrop($0) })
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
            .frame(minWidth: 420, idealWidth: 440, maxWidth: .infinity)
            .background(SplitViewAutosaveInstaller(
                name: isMediaPreviewVisible
                    ? "com.keyknock.BrollNamer.media-columns-with-preview"
                    : "com.keyknock.BrollNamer.media-columns-without-preview"
            ))

            if isMediaPreviewVisible {
                MediaPreviewView(
                    file: selectedSourceFileURL.flatMap(model.sourceFile(at:)),
                    controller: previewController,
                    model: model,
                    isMediaPreviewVisible: $isMediaPreviewVisible
                )
                .frame(minWidth: 340, idealWidth: 480, maxWidth: .infinity)
            }
        }
        .background(.windowBackground)
        .onChange(of: model.sourceFiles) { _, files in
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
                    PaneHeaderAction(systemImage: "chevron.right", help: "收起当前媒体栏", usesAnimation: false) {
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
