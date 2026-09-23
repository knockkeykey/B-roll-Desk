import AppKit
import AVKit
import AVFoundation
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
            SidebarView(model: model, themeRawValue: $themeRawValue)
                .frame(minWidth: 238, idealWidth: 276, maxWidth: 340)
            AnchorListView(model: model)
                .frame(minWidth: 390, idealWidth: 540, maxWidth: 760)
            DetailView(model: model)
                .frame(minWidth: 680, idealWidth: 820)
        }
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $model.isScriptEditorPresented) {
            ScriptEditorSheet(model: model)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
        .confirmationDialog(
            "清空本次配对记录？",
            isPresented: $model.isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
                    Button("清空配对记录", role: .destructive) {
                        model.clearAssignments()
                    }
                    .pointerCursor()
                    Button("取消", role: .cancel) {}
        } message: {
            Text("只清空本机记录和 manifest 中的绑定，不会删除目标目录里的视频。")
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

private struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Binding var themeRawValue: String

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "B-roll 配对台",
                systemImage: "film.stack",
                actions: [
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
                    SidebarSection(title: "目录", systemImage: "folder") {
                        VStack(alignment: .leading, spacing: 8) {
                            DirectoryChoiceRow(
                                title: "归档位置",
                                value: model.destinationDirectoryName,
                                isConfigured: model.destinationDirectoryURL != nil,
                                systemImage: "archivebox",
                                action: model.chooseDestinationDirectory,
                                openAction: model.revealDestinationDirectory
                            )
                        }
                    }

                    SidebarSection(title: "命名规则", systemImage: "pencil.and.list.clipboard") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Label("期数 / 前缀", systemImage: "number")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("必填")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(model.isPrefixValid ? Color.green : Color.orange)
                                }
                                HStack(spacing: 7) {
                                    TextField("例如 第15期", text: $model.prefix)
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                    Image(systemName: model.isPrefixValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundStyle(model.isPrefixValid ? Color.green : Color.orange)
                                        .help(model.isPrefixValid ? "绑定前缀已填写" : "绑定素材前请填写期数或前缀")
                                }
                                if !model.isPrefixValid {
                                    Text("填写后才能绑定素材")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }

                            SidebarFieldRow(title: "默认模式", systemImage: "rectangle.on.rectangle") {
                                Picker(selection: $model.defaultMode) {
                                    ForEach(BrollMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                label: {
                                    EmptyView()
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .controlSize(.small)
                                .pointerCursor()
                            }

                            Text("示例：\(model.isPrefixValid ? ScriptParser.sanitizePart(model.prefix, maxLength: 30) : "期数")_BR001_文案短句.ext")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .textSelection(.enabled)
                        }
                    }

                    SidebarSection(title: "统计", systemImage: "chart.bar") {
                        VStack(spacing: 2) {
                            StatMetric(
                                value: model.scriptCharacterCount,
                                unit: "字",
                                label: "文案字数",
                                detail: "含标点，不计空白",
                                systemImage: "text.alignleft",
                                tint: .secondary
                            )

                            Divider().padding(.leading, 28)

                            StatMetric(
                                value: model.aRollAnchorCount,
                                unit: "条",
                                label: "A-roll 锚点",
                                detail: "尚未绑定素材",
                                systemImage: "waveform",
                                tint: .secondary
                            )

                            Divider().padding(.leading, 28)

                            StatMetric(
                                value: model.bRollAnchorCount,
                                unit: "条",
                                label: "B-roll 锚点",
                                detail: "已绑定 \(model.assignedCount) 个素材",
                                systemImage: "film",
                                tint: .green
                            )
                        }
                        .animation(.snappy(duration: 0.24), value: model.assignedCount)
                        .animation(.snappy(duration: 0.24), value: model.scriptCharacterCount)
                    }

                    SidebarSection(title: "清单", systemImage: "doc.text") {
                        VStack(alignment: .leading, spacing: 8) {
                            SidebarActionButton(title: "导出 JSON 清单", systemImage: "arrow.down.doc") {
                                model.exportManifest()
                            }

                            Divider()

                            SidebarActionButton(title: "清空配对记录", systemImage: "trash", role: .destructive) {
                                model.requestClearAssignments()
                            }
                        }
                    }

                    SidebarStatusView(model: model)

                    Label("默认复制，原始 Finder 文件不会被移动或删除。", systemImage: "lock.shield")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
        }
        .background(.windowBackground)
        .onChange(of: model.prefix) { _, _ in
            model.persistPreferences()
        }
        .onChange(of: model.defaultMode) { _, _ in
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
    let systemImage: String
    let action: () -> Void
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Label(isConfigured ? "已就绪" : "必填", systemImage: isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isConfigured ? Color.green : Color.orange)
                    }
                    Text(value == "未选择" ? "请选择归档文件夹" : value)
                        .font(.caption)
                        .foregroundStyle(isConfigured ? Color.secondary : Color.orange)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Button(action: action) {
                    Label(isConfigured ? "更换目录" : "选择归档目录", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("选择或更换归档位置")
                .accessibilityLabel("选择或更换归档位置，当前：\(value)")
                .pointerCursor()

                Spacer(minLength: 0)

                if isConfigured {
                Button(action: openAction) {
                    Image(systemName: "arrow.up.forward.app")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(IconActionButtonStyle())
                .foregroundStyle(.secondary)
                .help("在 Finder 中打开归档目录")
                .accessibilityLabel("在 Finder 中打开归档目录")
                .pointerCursor()
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.55), lineWidth: 0.75)
        }
    }
}

private struct SidebarFieldRow<Control: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let control: () -> Control

    init(
        title: String,
        systemImage: String,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.systemImage = systemImage
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

private struct SidebarActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(
                tint.opacity(configuration.isPressed ? 0.17 : 0.08),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tint.opacity(0.12), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

private struct StatMetric: View {
    let value: Int
    let unit: String
    let label: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value, format: .number)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct AnchorListView: View {
    @ObservedObject var model: AppModel
    @FocusState private var isAnchorListFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "文案锚点",
                systemImage: "text.badge.checkmark",
                count: "\(model.filteredRows.count) / \(model.rows.count) 句",
                actions: [
                    PaneHeaderAction(
                        systemImage: "doc.text",
                        help: "编辑或导入视频文案"
                    ) {
                        model.isScriptEditorPresented = true
                    }
                ]
            )

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
                    .help("清除搜索")
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
                ScrollViewReader { proxy in
                    List {
                        ForEach(model.filteredRows) { row in
                            AnchorRowView(row: row, model: model)
                                .id(row.id)
                        }
                    }
                    .listStyle(.inset)
                    .focusable()
                    .focused($isAnchorListFocused)
                    .onKeyPress(keys: [.upArrow, .downArrow]) { keyPress in
                        let rows = model.filteredRows
                        guard !rows.isEmpty else { return .ignored }
                        let currentIndex = rows.firstIndex { $0.id == model.selectedAnchorID } ?? 0
                        let offset = keyPress.key == .upArrow ? -1 : 1
                        let nextIndex = min(max(currentIndex + offset, 0), rows.count - 1)
                        let nextID = rows[nextIndex].id
                        model.selectedAnchorID = nextID
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(nextID, anchor: .center)
                        }
                        return .handled
                    }
                    .onChange(of: model.selectedAnchorID) { _, selectedID in
                        guard isAnchorListFocused, let selectedID else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                    .overlay {
                        AnchorListDropOutline(feedback: model.dropFeedback)
                    }
                    .onDrop(of: [UTType.fileURL], delegate: AnchorListDropDelegate(feedback: model.dropFeedback))
                }
            }
        }
        .background(.windowBackground)
        .onChange(of: model.filteredRows.map(\.id)) { _, ids in
            if let selectedAnchorID = model.selectedAnchorID, !ids.contains(selectedAnchorID) {
                model.selectedAnchorID = ids.first
            } else if model.selectedAnchorID == nil {
                model.selectedAnchorID = ids.first
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
                .help(headerAction.help)
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
    private var isSelected: Bool { model.selectedAnchorID == row.id }

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
                        RollTypeTag(isBroll: isAssigned, assetCount: assets.count)
                    }
                    Text(row.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
            }

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
                .fill(
                    isDropTarget
                        ? Color.accentColor.opacity(0.13)
                        : (isAssigned
                            ? Color.green.opacity(isSelected ? 0.17 : 0.075)
                            : Color.accentColor.opacity(isSelected ? 0.10 : 0.02))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTarget
                        ? Color.accentColor.opacity(0.78)
                        : (isAssigned
                            ? Color.green.opacity(isSelected ? 0.72 : 0.28)
                            : Color.accentColor.opacity(isSelected ? 0.58 : 0)),
                    lineWidth: isDropTarget || isSelected ? 1.5 : (isAssigned ? 1 : 0)
                )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedAnchorID = row.id
        }
        .onDrop(
            of: [UTType.fileURL],
            delegate: FileDropDelegate(rowID: row.id, model: model, feedback: model.dropFeedback, rowState: dropState)
        )
        .help("从素材目录或 Finder 拖入图片 / 视频，绑定到这条文案锚点")
        .animation(.snappy(duration: 0.2), value: assets.count)
        .pointerCursor()
    }
}

private struct RollTypeTag: View {
    let isBroll: Bool
    let assetCount: Int

    private var tint: Color { isBroll ? .green : .accentColor }

    var body: some View {
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
        .help(isBroll
            ? "已绑定 \(assetCount) 个视频或图片，文件已复制到归档目录"
            : "默认 A-roll，尚未绑定 B-roll 素材"
        )
        .accessibilityLabel(isBroll ? "B-roll，已绑定 \(assetCount) 个素材" : "A-roll，尚未绑定 B-roll 素材")
    }
}

private struct AssetChip: View {
    let asset: BrollAsset
    @ObservedObject var model: AppModel
    let isDropTarget: Bool
    let isSelected: Bool

    private var mediaSymbol: String {
        let ext = URL(fileURLWithPath: asset.sourceName).pathExtension.lowercased()
        return AppModel.imageExtensions.contains(ext) ? "photo" : "film"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: mediaSymbol)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.outputName)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("源文件：\(asset.sourceName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Text(asset.mode.rawValue)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())

            Button {
                model.unbind(asset)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(IconActionButtonStyle())
            .foregroundStyle(.secondary)
            .help("取消绑定并删除归档副本；原始素材保留")
            .accessibilityLabel("取消绑定并删除归档副本 \(asset.sourceName)")
            .pointerCursor()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
            .background(
            isSelected
                ? Color.accentColor.opacity(0.12)
                : (isDropTarget ? Color.accentColor.opacity(0.09) : Color.green.opacity(0.055)),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.48) : Color.green.opacity(0.18),
                    lineWidth: isSelected ? 1 : 0.6
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

private struct MaterialDirectoryHeader: View {
    @ObservedObject var model: AppModel
    @Binding var isDirectoryPopoverPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "素材目录",
                systemImage: "film.stack",
                count: "\(model.visibleSourceFiles.count) 个素材",
                actions: [
                    PaneHeaderAction(systemImage: "arrow.clockwise", help: "刷新素材列表") {
                        model.refreshSourceFiles()
                    }
                ]
            )

            HStack(spacing: 8) {
                Image(systemName: model.sourceDirectoryURL == nil ? "folder" : "folder.fill")
                    .foregroundStyle(.tint)
                Text(model.sourceDirectoryURL == nil ? "未选择目录" : model.sourceDirectoryName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.sourceDirectoryURL?.path ?? "尚未选择素材来源")
                Spacer(minLength: 4)
                Button(model.sourceDirectoryURL == nil ? "选择目录" : "更换目录") {
                    model.chooseSourceDirectory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("选择素材来源目录")
                .pointerCursor()

                if model.sourceDirectoryURL != nil {
                    Button {
                        model.revealSourceDirectory()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .help("在 Finder 中打开素材目录")
                    .accessibilityLabel("在 Finder 中打开素材目录")
                    .pointerCursor()
                }

                Button {
                    isDirectoryPopoverPresented = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(IconActionButtonStyle())
                .help("管理常用素材目录")
                .accessibilityLabel("管理常用素材目录")
                .pointerCursor()
                .popover(isPresented: $isDirectoryPopoverPresented, arrowEdge: .trailing) {
                    DirectoryManagerPopover(model: model) {
                        isDirectoryPopoverPresented = false
                    }
                    .frame(width: 330)
                }
            }
            .font(.caption)
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
        VStack(alignment: .leading, spacing: 10) {
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
                    .help("将当前目录加入常用目录")
                    .pointerCursor()
                }
            }

            Button {
                model.chooseSourceDirectory()
                dismiss()
            } label: {
                Label("选择素材目录…", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .pointerCursor()

            Button {
                model.chooseAndSaveSourceDirectory()
                dismiss()
            } label: {
                Label("选择并收藏新目录…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerCursor()

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
            .help("切换到素材目录：\(directory.name)")
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
            .help("管理常用目录")
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
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                MaterialDirectoryHeader(model: model, isDirectoryPopoverPresented: $isDirectoryPopoverPresented)

                HStack {
                    Text("筛选素材")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    MediaFilterPicker(selection: $model.mediaFilter)
                }
                .padding(.horizontal, 16)
                .frame(height: ListPaneMetrics.toolsHeight)
                .overlay(alignment: .bottom) {
                    Divider()
                }

                if model.visibleSourceFiles.isEmpty {
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
                    List(selection: $selectedSourceFileURLs) {
                        ForEach(model.visibleSourceFiles) { file in
                            SourceFileRow(
                                file: file,
                                model: model,
                                isAssigned: model.isAssigned(file),
                                isSelected: selectedSourceFileURLs.contains(file.url)
                            )
                            .tag(file.url)
                            .onTapGesture {
                                selectSourceFile(file.url)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .focusable()
                    .focused($isMaterialListFocused)
                    .onKeyPress(keys: [.upArrow, .downArrow, .space]) { keyPress in
                        switch keyPress.key {
                        case .upArrow:
                            moveSelection(by: -1)
                            return .handled
                        case .downArrow:
                            moveSelection(by: 1)
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
            .frame(minWidth: 300, idealWidth: 380, maxWidth: .infinity)

            Divider()

            MediaPreviewView(
                file: selectedSourceFileURL.flatMap { url in
                    model.sourceFiles.first(where: { $0.url == url })
                },
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

    private func selectSourceFile(_ url: URL) {
        selectedSourceFileURLs = [url]
        model.selectedSourceFileURL = url
        isMaterialListFocused = true
    }

    private func moveSelection(by offset: Int) {
        let visibleFiles = model.visibleSourceFiles
        guard !visibleFiles.isEmpty else { return }

        let currentIndex = selectedSourceFileURL.flatMap { selectedURL in
            visibleFiles.firstIndex { $0.url == selectedURL }
        }

        let targetIndex: Int
        if let currentIndex {
            targetIndex = min(max(currentIndex + offset, 0), visibleFiles.count - 1)
        } else {
            targetIndex = offset < 0 ? visibleFiles.count - 1 : 0
        }

        selectSourceFile(visibleFiles[targetIndex].url)
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
        .controlSize(.small)
        .frame(width: 164)
        .help("筛选素材类型")
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
                count: file == nil ? "未选择" : "已选择"
            )

            HStack(spacing: 8) {
                if let file {
                    Image(systemName: file.kind.systemImage)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(file.name)
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
                    .help("使用 Quick Look 打开素材")
                    .accessibilityLabel("使用 Quick Look 打开素材")
                    .pointerCursor()

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(IconActionButtonStyle())
                    .help("在 Finder 中显示素材")
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
                    VStack(spacing: 12) {
                        NativePlayerView(player: controller.player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.separator.opacity(0.75), lineWidth: 0.5)
                            }

                        HStack {
                            Button {
                                controller.togglePlayback()
                            } label: {
                                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                                    .frame(width: 16)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .help(controller.isPlaying ? "暂停视频" : "播放视频")
                            .accessibilityLabel(controller.isPlaying ? "暂停视频" : "播放视频")
                            .pointerCursor()

                            Spacer(minLength: 8)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .task(id: file.url) {
            image = NSImage(contentsOf: file.url)
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
            }
        }
    }

    func togglePlayback() {
        guard player.currentItem != nil else { return }

        if player.timeControlStatus == .playing || player.rate != 0 {
            pause()
        } else {
            player.play()
            isPlaying = true
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
    @ObservedObject var model: AppModel
    let isAssigned: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            MediaThumbnailView(file: file)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(isAssigned ? "已绑定" : MediaFormatting.bytes(file.byteCount))
                    .font(.caption2)
                    .foregroundStyle(isAssigned ? .green : .secondary)
            }
            Spacer(minLength: 5)
            if isAssigned {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .help("该素材已绑定")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrag {
            return NSItemProvider(object: file.url as NSURL)
        }
        .background(CursorRectView(cursor: .openHand).allowsHitTesting(false))
        .onHover { isHovering in
            if isHovering {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .help("点击选择，拖拽到文案锚点")
        .accessibilityValue(isSelected ? "已选中" : "未选中")
    }
}

private struct CursorRectView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectHostingView {
        CursorRectHostingView(cursor: cursor)
    }

    func updateNSView(_ nsView: CursorRectHostingView, context: Context) {
        nsView.cursor = cursor
        nsView.resetCursorRects()
    }
}

private final class CursorRectHostingView: NSView {
    var cursor: NSCursor

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        cursor = .arrow
        super.init(coder: coder)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }
}

private extension View {
    func pointerCursor(_ cursor: NSCursor = .pointingHand) -> some View {
        background(CursorRectView(cursor: cursor).allowsHitTesting(false))
            .onHover { isHovering in
                if isHovering {
                    cursor.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
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

    @State private var image: NSImage?
    @State private var isLoading = true

    private let thumbnailSize = CGSize(width: 92, height: 56)

    var body: some View {
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
        .task(id: file.url) {
            isLoading = true
            if file.kind == .image {
                image = NSImage(contentsOf: file.url)
            } else {
                image = await VideoThumbnailLoader.image(for: file.url)
            }
            isLoading = false
        }
    }
}

private final class VideoThumbnailCache {
    static let shared = VideoThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

private enum VideoThumbnailLoader {
    static func image(for url: URL) async -> NSImage? {
        if let cached = VideoThumbnailCache.shared.image(for: url) {
            return cached
        }

        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        let sampleSeconds: Double
        if duration.isFinite, duration > 0 {
            sampleSeconds = min(max(duration * 0.12, 0.05), 1.0)
        } else {
            sampleSeconds = 0.5
        }

        let requestedTime = CMTime(seconds: sampleSeconds, preferredTimescale: 600)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 368, height: 224)

        let image: NSImage? = await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: requestedTime)]) { [generator] _, cgImage, _, result, _ in
                guard result == .succeeded, let cgImage else {
                    continuation.resume(returning: nil)
                    return
                }

                _ = generator
                continuation.resume(returning: NSImage(cgImage: cgImage, size: .zero))
            }
        }

        if let image {
            VideoThumbnailCache.shared.insert(image, for: url)
        }
        return image
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
