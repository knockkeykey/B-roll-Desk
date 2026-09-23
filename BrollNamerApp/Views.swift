import AppKit
import AVKit
import AVFoundation
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

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
        NavigationSplitView {
            SidebarView(model: model, themeRawValue: $themeRawValue)
                .navigationSplitViewColumnWidth(min: 238, ideal: 276, max: 340)
        } content: {
            AnchorListView(model: model)
                .navigationSplitViewColumnWidth(min: 390, ideal: 540, max: 760)
        } detail: {
            DetailView(model: model)
                .navigationSplitViewColumnWidth(min: 680, ideal: 820, max: 1100)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.isScriptEditorPresented = true
                } label: {
                    Label("编辑文案", systemImage: "doc.text")
                }
                .help("编辑或导入视频文案")
                .accessibilityLabel("编辑或导入视频文案")
                .pointerCursor()

                Button {
                    model.refreshSourceFiles()
                } label: {
                    Label("刷新素材", systemImage: "arrow.clockwise")
                }
                .help("重新读取素材目录")
                .accessibilityLabel("刷新素材目录")
                .pointerCursor()
            }
        }
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
        .animation(.snappy(duration: 0.24), value: model.assignedCount)
        .animation(.snappy(duration: 0.24), value: model.activeDropAnchorID)
        .animation(.easeOut(duration: 0.16), value: model.isFileDragActive)
        .preferredColorScheme(preferredColorScheme)
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Binding var themeRawValue: String

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "film.stack")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("B-roll 配对台")
                            .font(.title3.weight(.bold))
                        Text("LOCAL / NATIVE")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                    }
                    Spacer(minLength: 0)

                    Button {
                        themeRawValue = theme.next.rawValue
                    } label: {
                        Image(systemName: theme.icon)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("当前主题：\(theme.title)，点击切换")
                    .accessibilityLabel("切换主题，当前为\(theme.title)")
                    .pointerCursor()
                }

                SidebarSection(title: "目录", systemImage: "folder") {
                    VStack(alignment: .leading, spacing: 0) {
                        DirectoryChoiceRow(
                            title: "素材来源",
                            value: model.sourceDirectoryName,
                            systemImage: "folder",
                            actionSystemImage: "folder.badge.plus",
                            action: model.chooseSourceDirectory,
                            openAction: model.revealSourceDirectory
                        )

                        Divider()
                            .padding(.vertical, 9)

                        DirectoryChoiceRow(
                            title: "归档位置",
                            value: model.destinationDirectoryName,
                            systemImage: "archivebox",
                            actionSystemImage: "archivebox",
                            action: model.chooseDestinationDirectory,
                            openAction: model.revealDestinationDirectory
                        )
                    }
                }

                SidebarSection(title: "命名规则", systemImage: "pencil.and.list.clipboard") {
                    VStack(alignment: .leading, spacing: 12) {
                        SidebarFieldRow(title: "期数 / 前缀", systemImage: "number") {
                            TextField("例如 第15期", text: $model.prefix)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
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

                        Text("[prefix_]BR###_文案短句.ext")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                SidebarSection(title: "进度", systemImage: "chart.bar") {
                    HStack(spacing: 18) {
                        StatTile(value: model.assignedCount, label: "已绑定", systemImage: "checkmark.circle", tint: .accentColor)
                        Divider()
                            .frame(height: 38)
                        StatTile(value: model.pendingCount, label: "待绑定", systemImage: "clock", tint: .secondary)
                    }
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
        .background(.windowBackground)
        .scrollIndicators(.hidden)
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
        model.destinationDirectoryURL != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "circle")
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
    let systemImage: String
    let actionSystemImage: String
    let action: () -> Void
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Button(action: action) {
                    Image(systemName: actionSystemImage)
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .help("选择\(title)目录")
                .accessibilityLabel("选择\(title)目录")
                .pointerCursor()
            }
            if value == "未选择" {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Button(action: openAction) {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("在 Finder 中打开\(title)目录")
                .accessibilityLabel("在 Finder 中打开\(title)目录：\(value)")
                .pointerCursor()
            }
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
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .lineLimit(1)
                .frame(minWidth: 88, alignment: .leading)

            Spacer(minLength: 0)

            control()
                .frame(width: 104, alignment: .trailing)
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

private struct StatTile: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(value, format: .number)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnchorListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "文案锚点",
                systemImage: "text.badge.checkmark",
                subtitle: nil,
                subtitleSystemImage: nil,
                count: "\(model.filteredRows.count) / \(model.rows.count) 句"
            )

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
            } else {
                List(selection: $model.selectedAnchorID) {
                    ForEach(model.filteredRows) { row in
                        AnchorRowView(row: row, model: model)
                            .tag(row.id)
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if model.isFileDragActive {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1.25)
                            .padding(2)
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [UTType.fileURL], delegate: AnchorListDropDelegate(model: model))
            }
        }
        .searchable(text: $model.anchorSearchText, placement: .toolbar, prompt: "搜索文案")
        .background(.windowBackground)
    }
}

private struct PaneHeader: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    let subtitleSystemImage: String?
    let count: String
    let actionSystemImage: String?
    let actionHelp: String?
    let action: (() -> Void)?

    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        subtitleSystemImage: String? = nil,
        count: String,
        actionSystemImage: String? = nil,
        actionHelp: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.subtitleSystemImage = subtitleSystemImage
        self.count = count
        self.actionSystemImage = actionSystemImage
        self.actionHelp = actionHelp
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(count)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                if let action, let actionSystemImage {
                    Button(action: action) {
                        Image(systemName: actionSystemImage)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(actionHelp ?? title)
                    .accessibilityLabel(actionHelp ?? title)
                    .pointerCursor()
                }
            }

            if let subtitle, let subtitleSystemImage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: subtitleSystemImage)
                        .imageScale(.small)
                    Text(subtitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: subtitle == nil ? 54 : 70, alignment: .top)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct AnchorRowView: View {
    let row: AnchorRow
    @ObservedObject var model: AppModel

    private var assets: [BrollAsset] { model.assets(for: row.id) }
    private var isDropTarget: Bool { model.activeDropAnchorID == row.id }

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
                        if assets.isEmpty {
                            Text("待绑定")
                                .font(.caption2)
                                .foregroundStyle(isDropTarget ? Color.accentColor : Color.secondary)
                        } else {
                            Label("\(assets.count) 个已归档", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(isDropTarget ? Color.accentColor : Color.green)
                        }
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
                .fill(isDropTarget ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTarget ? Color.accentColor.opacity(0.7) : Color.clear,
                    lineWidth: isDropTarget ? 1.5 : 0
                )
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], delegate: FileDropDelegate(rowID: row.id, model: model))
        .pointerCursor()
    }
}

private struct AssetChip: View {
    let asset: BrollAsset
    @ObservedObject var model: AppModel
    let isDropTarget: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
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
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("取消绑定")
            .accessibilityLabel("取消绑定 \(asset.sourceName)")
            .pointerCursor()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.16)
                : (isDropTarget ? Color.accentColor.opacity(0.11) : Color.accentColor.opacity(0.07)),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.72) : Color.clear,
                    lineWidth: isSelected ? 1 : 0
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

private struct SavedDirectoryTabs: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("常用目录", systemImage: "folder.badge.gearshape")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if model.sourceDirectoryURL != nil && !model.isCurrentSourceDirectorySaved {
                    Button("保存当前") {
                        model.saveCurrentSourceDirectory()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .help("把当前素材目录保存为常用目录")
                    .pointerCursor()
                }

                Button {
                    model.chooseAndSaveSourceDirectory()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .help("选择并保存常用目录")
                .accessibilityLabel("选择并保存常用目录")
                .pointerCursor()
            }

            if model.savedDirectories.isEmpty {
                Text("保存后可从这里快速切换素材目录")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(model.savedDirectories) { directory in
                            SavedDirectoryTab(
                                directory: directory,
                                isSelected: isSelected(directory),
                                select: { model.selectSavedDirectory(directory.id) },
                                remove: { model.removeSavedDirectory(directory.id) }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func isSelected(_ directory: SavedDirectory) -> Bool {
        directory.path == model.sourceDirectoryURL?.standardizedFileURL.path
    }
}

private struct SavedDirectoryTab: View {
    let directory: SavedDirectory
    let isSelected: Bool
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .imageScale(.small)
                Text(directory.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.16),
                        lineWidth: 0.75
                    )
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .help("切换到素材目录：\(directory.name)")
        .pointerCursor()
        .contextMenu {
            Button("移除常用目录", role: .destructive, action: remove)
        }
        .accessibilityLabel("素材目录 \(directory.name)")
        .accessibilityValue(isSelected ? "当前目录" : "未选中")
    }
}

private struct DetailView: View {
    @ObservedObject var model: AppModel
    @State private var selectedSourceFileURLs: Set<URL> = []
    @FocusState private var isMaterialListFocused: Bool
    @StateObject private var previewController = MediaPreviewController()

    private var selectedSourceFileURL: URL? {
        selectedSourceFileURLs.first
    }

    private var selectedRow: AnchorRow? {
        guard let selectedAnchorID = model.selectedAnchorID else { return nil }
        return model.rows.first(where: { $0.id == selectedAnchorID })
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
            PaneHeader(
                title: "素材目录",
                systemImage: "film.stack",
                subtitle: model.sourceDirectoryName == "未选择" ? "请在左侧选择素材来源" : model.sourceDirectoryName,
                subtitleSystemImage: "folder",
                count: "\(model.visibleSourceFiles.count)",
                actionSystemImage: "arrow.clockwise",
                actionHelp: "刷新素材目录",
                action: model.refreshSourceFiles
            )

            SavedDirectoryTabs(model: model)

            HStack {
                MediaFilterPicker(selection: $model.mediaFilter)
                Spacer()
                if let selectedSourceFileURL {
                    Button {
                        QuickLookPreviewController.shared.preview(url: selectedSourceFileURL)
                    } label: {
                        Label("Quick Look", systemImage: "eye")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("使用 Quick Look 打开素材")
                    .pointerCursor()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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

            Divider()

            if let selectedRow {
                SelectedAnchorSummary(row: selectedRow, model: model)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.circle")
                        .foregroundStyle(.secondary)
                    Text("选择一个文案锚点查看已归档素材")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
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
                subtitle: file?.name ?? "未选择",
                subtitleSystemImage: file?.kind.systemImage ?? "film",
                count: file.map { MediaFormatting.bytes($0.byteCount) } ?? "未选择",
                actionSystemImage: file == nil ? nil : "eye",
                actionHelp: file == nil ? nil : "使用 Quick Look 打开素材",
                action: file.map { selectedFile in
                    {
                        QuickLookPreviewController.shared.preview(url: selectedFile.url)
                    }
                }
            )

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
            model.isFileDragActive = true
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

private struct SelectedAnchorSummary: View {
    let row: AnchorRow
    @ObservedObject var model: AppModel

    private var assets: [BrollAsset] { model.assets(for: row.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("当前锚点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("BR\(String(format: "%03d", row.index))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Text(row.text)
                .font(.callout)
                .lineLimit(3)
                .textSelection(.enabled)
            if assets.isEmpty {
                Label("尚未绑定素材", systemImage: "circle.dashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("已归档 \(assets.count) 个镜头 · V2 · 静音", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35))
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
