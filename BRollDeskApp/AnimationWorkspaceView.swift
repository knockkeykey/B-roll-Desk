import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Independent animation production and full-script analysis workspace.
struct AnimationWorkspaceView: View {
    @Bindable var model: AppModel
    @AppStorage("broll-namer-animation-always-on-top") private var isPinned = false
    @AppStorage("broll-namer-theme") private var themeRawValue = AppTheme.system.rawValue
    @State private var page = AnimationPage.production
    @State private var isScriptDropTargeted = false
    @State private var settingsDestination: AnimationSettingsDestination?
    @State private var isAnalysisHelpPresented = false
    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?
    @FocusState private var isScriptListFocused: Bool

    private var hasKey: Bool { !model.deepSeekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var scriptRowCount: Int { model.animationScriptRowCount }
    private var selectedReviewCount: Int { model.animationReviewItems.filter(\.isSelected).count }
    private var isReviewing: Bool { !model.animationReviewItems.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if page == .production { productionPage }
                else {
                    analyzePage
                        .disabled(model.isAnalyzingAnimations)
                        .overlay { if model.isAnalyzingAnimations { analysisLoadingOverlay } }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .toolbar { toolbarContent }
        .background(AuxiliaryWindowLevelController(isFloating: isPinned).frame(width: 0, height: 0))
        .preferredColorScheme(preferredColorScheme)
        .onAppear { normalizeTemplate() }
        .onDisappear { copyResetTask?.cancel() }
        .alert("如何加入这条文案？", isPresented: Binding(
            get: { model.pendingAnimationDrop != nil },
            set: { if !$0 { model.cancelAnimationDrop() } }
        )) {
            Button("替换当前") { model.resolveAnimationDrop(keepingOthers: false) }
            Button("保留多条") { model.resolveAnimationDrop(keepingOthers: true) }
            Button("取消", role: .cancel) { model.cancelAnimationDrop() }
        } message: {
            Text("替换当前选中的文案，或保留已有条目并加入新文案。")
        }
        .sheet(item: $settingsDestination) { destination in
            AnimationSettingsSheet(model: model, destination: destination)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("工作区", selection: $page) {
                Text("制作提示词").tag(AnimationPage.production)
                Text("全文分析").tag(AnimationPage.analysis)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        ToolbarItem(placement: .primaryAction) {
            Button { isPinned.toggle() } label: {
                Label("置顶", systemImage: isPinned ? "pin.fill" : "pin")
            }
            .help(isPinned ? "取消窗口置顶" : "让窗口保持在最前")
            .accessibilityLabel("动画助手窗口置顶")
            .accessibilityValue(isPinned ? "已开启" : "已关闭")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if page == .analysis, isReviewing {
                Button("放弃结果", role: .destructive) { model.discardAnimationReview() }
            }
            if model.isTestingDeepSeek || model.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(model.animationFeedback.isEmpty ? (page == .production ? "复制当前选中文案的完整提示词；修改会自动保存。" : footerHint) : model.animationFeedback)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if page == .production { copyButton } else { primaryAction.buttonStyle(.borderedProminent) }
        }
        .controlSize(.large)
    }

    private var copyButton: some View {
        Button(action: copyPrompt) {
            Label(didCopy ? "已复制" : "复制提示词", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                .frame(minWidth: 96)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(model.selectedAnimationWorkspaceTask == nil || model.isBusy)
        .help("复制完整提示词（⌘↩）")
    }

    private func copyPrompt() {
        guard let task = model.selectedAnimationWorkspaceTask, model.copyAnimationPrompt(task) else { return }
        withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { didCopy = false }
        }
    }

    private var footerHint: String {
        isReviewing ? "勾选要做动画的段落；应用后会拆分并标记，可 ⌘Z 撤销。" : "整篇文案会发送给 DeepSeek；勾选应用后才修改。"
    }

    private enum AnimationPage { case production, analysis }

    private var preferredColorScheme: ColorScheme? {
        switch AppTheme(rawValue: themeRawValue) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Ensures every resource anchor exists in the saved template, as the inline editor used to.
    private func normalizeTemplate() {
        let normalized = AnimationTemplateSection.parse(model.animationTemplate).map(\.raw).joined()
        if normalized != model.animationTemplate { model.animationTemplate = normalized }
    }

    // MARK: Production

    private var productionPage: some View {
        Form {
            Section {
                scriptList
            } header: {
                Text("文案")
            } footer: {
                if !model.animationWorkspaceTasks.isEmpty {
                    Text("继续拖入可替换当前文案或保留多条；按 Delete 移除选中项。")
                }
            }

            Section("角色参考图") {
                AnimationCharacterReferenceEditor(model: model)
            }

            Section {
                AnimationOutputDirectoryEditor(model: model)
            } header: {
                Text("输出目录")
            } footer: {
                Text("代码等文件夹按“【文案】-【时间】”命名，视频以文案命名。")
            }

            Section {
                SettingsRow(systemImage: "text.alignleft", tint: .orange, title: "提示词模板",
                            value: model.animationTemplate == AnimationWorkflow.defaultTemplate ? "默认" : "已自定义") {
                    settingsDestination = .template
                }
            }
        }
        .formStyle(.grouped)
    }

    private var scriptList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.animationWorkspaceTasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(isScriptDropTargeted ? Color.accentColor : .secondary)
                    Text("把动画条目拖到这里").font(.body.weight(.medium))
                    Text("拖动主列表动画条目上的拖拽柄；不会改变原条目。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isScriptDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            } else {
                ForEach(model.animationWorkspaceTasks) { task in
                    AnimationScriptRow(
                        text: task.text,
                        note: model.note(for: task.rowID),
                        isSelected: task.rowID == model.selectedAnimationWorkspaceRowID,
                        select: {
                            model.selectedAnimationWorkspaceRowID = task.rowID
                            isScriptListFocused = true
                        },
                        remove: { model.removeAnimationWorkspaceRow(task.rowID) }
                    )
                }
            }
        }
        .background {
            if isScriptDropTargeted, !model.animationWorkspaceTasks.isEmpty {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .padding(-4)
            } else if isScriptDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.08))
            }
        }
        .animation(.easeOut(duration: 0.15), value: isScriptDropTargeted)
        .focusable(!model.animationWorkspaceTasks.isEmpty)
        .focused($isScriptListFocused)
        .focusEffectDisabled()
        .onDeleteCommand {
            if let rowID = model.selectedAnimationWorkspaceRowID { model.removeAnimationWorkspaceRow(rowID) }
        }
        .onMoveCommand(perform: moveSelection)
        .accessibilityIdentifier("animation-script-drop-zone")
        .onDrop(of: [AnimationRowDrag.type], isTargeted: $isScriptDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: AnimationRowDrag.type.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in _ = model.receiveAnimationDrop(data) }
            }
            return true
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let ids = model.animationWorkspaceTasks.map(\.rowID)
        guard !ids.isEmpty else { return }
        let current = model.selectedAnimationWorkspaceRowID.flatMap { ids.firstIndex(of: $0) } ?? 0
        switch direction {
        case .up: model.selectedAnimationWorkspaceRowID = ids[max(current - 1, 0)]
        case .down: model.selectedAnimationWorkspaceRowID = ids[min(current + 1, ids.count - 1)]
        default: break
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if isReviewing {
            Button("应用 \(selectedReviewCount) 段") { model.applyAnimationReview() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selectedReviewCount == 0 || model.isBusy)
        } else if model.isAnalyzingAnimations {
            Button { model.cancelAnimationAnalysis() } label: {
                Text("取消分析").frame(minWidth: 84)
            }
        } else {
            Button { model.startAnimationAnalysis() } label: {
                Text("分析动画段落").frame(minWidth: 84)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!hasKey || scriptRowCount == 0 || model.isTestingDeepSeek || model.isBusy)
        }
    }

    private var analysisLoadingOverlay: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.65)
                .contentShape(Rectangle())

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("分析进行中")

                VStack(spacing: 4) {
                    Text("正在分析全文")
                        .font(.headline)
                    Text("DeepSeek 正在筛选适合动画的段落")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("\(scriptRowCount) 条文案 · 通常需要几十秒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("取消分析") { model.cancelAnimationAnalysis() }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)
            .frame(width: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("全文分析进行中")
    }
}

// MARK: - 文案分析

extension AnimationWorkspaceView {
    @ViewBuilder var analyzePage: some View {
        if isReviewing { reviewPage } else { overviewPage }
    }

    private var reviewPage: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DeepSeek 推荐了 \(model.animationReviewItems.count) 段").font(.headline)
                    Text("取消勾选不需要的段落，文案在应用前不会改动。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(selectedReviewCount == model.animationReviewItems.count ? "全不选" : "全选") {
                    let target = selectedReviewCount != model.animationReviewItems.count
                    for index in model.animationReviewItems.indices { model.animationReviewItems[index].isSelected = target }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            List {
                ForEach($model.animationReviewItems) { $item in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: $item.isSelected)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .accessibilityLabel("选择：\(item.candidate.text)")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.candidate.text)
                                .font(.body.weight(.medium))
                                .foregroundStyle(item.isSelected ? Color.primary : Color.secondary)
                            Label(item.candidate.reason, systemImage: "lightbulb")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.vertical, 5)
                    .opacity(item.isSelected ? 1 : 0.6)
                    .contentShape(Rectangle())
                    .onTapGesture { item.isSelected.toggle() }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
        }
    }

    private var overviewPage: some View {
        Form {
            Section {
                LabeledContent {
                    Text("\(scriptRowCount)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } label: {
                    HStack(spacing: 6) {
                        Text("参与分析的条目")
                        analysisHelpButton
                    }
                }
            } header: {
                Text("全文")
            } footer: {
                Text("所有有文字的条目都参与判断；勾选并应用后才会修改文案。")
            }

            Section("分析配置") {
                SettingsRow(systemImage: "key.fill", tint: .blue, title: "DeepSeek",
                            value: hasKey ? "已保存在钥匙串 · deepseek-flash" : "未设置 API Key",
                            valueTint: hasKey ? .secondary : .orange) { settingsDestination = .deepSeek }
                SettingsRow(systemImage: "checklist", tint: .purple, title: "动画判断规则",
                            value: model.animationRules == AnimationWorkflow.defaultRules ? "默认" : "已自定义") { settingsDestination = .rules }
            }
        }
        .formStyle(.grouped)
    }

    private var analysisHelpButton: some View {
        Button { isAnalysisHelpPresented.toggle() } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("全文分析说明")
        .help("查看分析范围及应用后的变化")
        .popover(isPresented: $isAnalysisHelpPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("哪些条目参与分析？").font(.headline)
                Text("所有有文字的文案条目都参与分析，不计空白条目。")
                Text("A-roll / B-roll 标签、制作方式、准备状态、已绑定素材和已有动画任务，都不会排除条目。AI 根据文案内容判断哪些段落适合动画。")
                Text("这里显示的是全文条目数。AI 会列出推荐段落，勾选并确认应用后，才会拆分文案、标记动画和更新制作备注。")
                Divider()
                Text("分析后会发生什么").font(.headline)
                VStack(alignment: .leading, spacing: 12) {
                    ExplainRow(systemImage: "checklist.checked", text: "先列出推荐段落供你勾选，确认后才改动文案。")
                    ExplainRow(systemImage: "scissors", text: "按原文逐字拆分出适合动画的段落，不改写文案。")
                    ExplainRow(systemImage: "tag", text: "自动标记为 B-roll · 动画，把表达重点放入备注；在文案列表筛选“动画 + 待准备”即可查看制作清单。")
                    ExplainRow(systemImage: "text.magnifyingglass", text: "所有有文字的条目都参与判断，不按已有标签或绑定状态过滤。")
                    ExplainRow(systemImage: "arrow.uturn.backward", text: "结果不满意可以 ⌘Z 一步撤销。")
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(18)
            .frame(width: 420, alignment: .leading)
        }
    }
}

// MARK: - Rows

private struct AnimationScriptRow: View {
    let text: String
    let note: String
    let isSelected: Bool
    let select: () -> Void
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected, !note.isEmpty {
                    Text("表达重点：" + note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .help("移除")
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contextMenu {
            Button("移除", role: .destructive, action: remove)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("文案：\(text)")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityAction(named: "移除", remove)
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.15) }
        return isHovering ? Color.primary.opacity(0.05) : .clear
    }
}

struct SettingsRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let value: String
    var valueTint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(title)
                Spacer()
                Text(value).foregroundStyle(valueTint)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ExplainRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 18)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Resource editors

private struct AnimationOutputDirectoryEditor: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            TextField("输出文件夹的完整路径", text: $model.animationOutputDirectory)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .accessibilityLabel("动画输出目录")
            if !model.animationOutputDirectory.isEmpty {
                Button { model.animationOutputDirectory = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("清除")
                .accessibilityLabel("清除输出目录")
            }
            Button("选择…") { chooseDirectory() }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择动画输出目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let path = model.animationOutputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.animationOutputDirectory = url.path
    }
}

private struct AnimationCharacterReferenceEditor: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(model.animationCharacterPath.isEmpty ? "未设置" : (model.animationCharacterPath as NSString).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text(model.animationCharacterPath.isEmpty ? "拖入图片或点击选择；由制作 AI 判断是否需要角色" : "由制作 AI 判断是否需要角色，需要时使用此参考图")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !model.animationCharacterPath.isEmpty {
                Button("移除") { model.removeAnimationCharacterImage() }
                    .accessibilityLabel("移除角色参考图")
            }
            Button(model.animationCharacterPath.isEmpty ? "选择…" : "更换…") { chooseCharacter() }
                .accessibilityLabel("选择角色参考图")
        }
        .padding(4)
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            FileURLDropLoader.loadURLs(from: providers) { urls in
                model.setAnimationCharacterImage(urls.first(where: { $0.isFileURL && NSImage(contentsOf: $0) != nil }))
            }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.1))
            if let image = model.animationCharacterImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: model.animationCharacterPath.isEmpty ? "photo.badge.plus" : "exclamationmark.triangle")
                    .font(.system(size: 20)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityLabel(model.animationCharacterPath.isEmpty ? "未设置角色参考图" : "角色参考图预览")
        .help(model.animationCharacterPath.isEmpty ? "将图片文件拖入此行" : model.animationCharacterPath)
    }

    private func chooseCharacter() {
        let panel = NSOpenPanel()
        panel.title = "选择角色参考图"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if !model.animationCharacterPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: model.animationCharacterPath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setAnimationCharacterImage(url)
    }
}

// MARK: - Settings

private enum AnimationSettingsDestination: Identifiable {
    case deepSeek, rules, template
    var id: Self { self }
    var title: String {
        switch self {
        case .deepSeek: return "DeepSeek 连接"
        case .rules: return "动画判断规则"
        case .template: return "提示词模板"
        }
    }
}

/// Converts between the stored template (`{{…}}` anchors) and the editable text shown to the user.
enum AnimationTemplateText {
    static let variables: [(kind: AnimationTemplateSection.Kind, token: String, name: String)] = [
        (.script, "〔文案〕", "文案"),
        (.character, "〔角色参考图〕", "角色参考图"),
        (.outputDirectory, "〔输出目录〕", "输出目录"),
    ]

    static func display(_ template: String) -> String {
        let raw = AnimationTemplateSection.parse(template).map(\.raw).joined()
        return variables.reduce(raw) { $0.replacingOccurrences(of: $1.kind.marker, with: $1.token) }
    }

    static func template(fromDisplay text: String) -> String {
        let raw = variables.reduce(text) { $0.replacingOccurrences(of: $1.token, with: $1.kind.marker) }
        return AnimationTemplateSection.parse(raw).map(\.raw).joined()
    }
}

/// Holds the live text view so toolbar buttons can insert at the caret with undo support.
@MainActor
final class TemplateEditorProxy {
    weak var textView: NSTextView?

    func insert(_ text: String) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.insertText(text, replacementRange: textView.selectedRange())
    }
}

/// Plain-text editor that highlights template variables such as 〔文案〕 as tokens.
private struct TemplateTextEditor: NSViewRepresentable {
    @Binding var text: String
    let proxy: TemplateEditorProxy

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.font = Coordinator.baseFont
        textView.typingAttributes = Coordinator.baseAttributes
        textView.string = text
        textView.setAccessibilityLabel("提示词模板")
        Coordinator.highlight(textView)
        proxy.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        proxy.textView = textView
        if textView.string != text {
            textView.string = text
            Coordinator.highlight(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        static let baseFont = NSFont.systemFont(ofSize: 13)
        static var baseAttributes: [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            return [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        }
        private static let pattern = try! NSRegularExpression(
            pattern: AnimationTemplateText.variables.map { NSRegularExpression.escapedPattern(for: $0.token) }.joined(separator: "|"))

        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            Self.highlight(textView)
        }

        static func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: full)
            for match in pattern.matches(in: storage.string, range: full) {
                storage.addAttributes([
                    .foregroundColor: NSColor.controlAccentColor,
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.14),
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                ], range: match.range)
            }
            storage.endEditing()
            textView.typingAttributes = baseAttributes
        }
    }
}

private struct AnimationSettingsSheet: View {
    @Bindable var model: AppModel
    let destination: AnimationSettingsDestination
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var originalKey = ""
    @State private var revealKey = false
    @State private var resetDraft = false
    @State private var editorProxy = TemplateEditorProxy()

    var body: some View {
        VStack(spacing: 0) {
            Text(destination.title)
                .font(.headline)
                .padding(.top, 18)
            Form { content }
                .formStyle(.grouped)
            Divider()
            HStack(spacing: 10) {
                Text(model.animationFeedback).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("取消", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isTestingDeepSeek)
                Button("完成", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isTestingDeepSeek)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 600, height: destination == .deepSeek ? 300 : 560)
        .interactiveDismissDisabled()
        .onAppear(perform: loadDraft)
        .confirmationDialog(destination == .rules ? "恢复默认判断规则？" : "恢复默认提示词模板？", isPresented: $resetDraft) {
            Button("恢复默认", role: .destructive) {
                draft = destination == .rules ? AnimationWorkflow.defaultRules : AnimationTemplateText.display(AnimationWorkflow.defaultTemplate)
            }
        } message: {
            Text(destination == .rules ? "当前自定义判断规则将被覆盖。" : "当前自定义模板将被覆盖，角色图和输出目录保留。")
        }
    }

    @ViewBuilder private var content: some View {
        switch destination {
        case .deepSeek:
            Section {
                HStack {
                    Group {
                        if revealKey { TextField("API Key", text: $model.deepSeekKeyDraft) }
                        else { SecureField("API Key", text: $model.deepSeekKeyDraft) }
                    }
                    .accessibilityLabel("DeepSeek API Key")
                    Button { revealKey.toggle() } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealKey ? "隐藏 API Key" : "显示 API Key")
                }
                LabeledContent("模型") {
                    HStack(spacing: 8) {
                        Text("deepseek-flash").font(.callout.monospaced()).foregroundStyle(.secondary)
                        if model.isTestingDeepSeek { ProgressView().controlSize(.small) }
                        Button("测试连接") { Task { await model.testDeepSeekConnection() } }
                            .disabled(model.isTestingDeepSeek || model.deepSeekKeyDraft.isEmpty)
                    }
                }
            } footer: {
                Text("API Key 只保存在本机钥匙串，不写入项目或导出的 JSON。")
            }
        case .rules:
            Section {
                TextEditor(text: $draft)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 340)
                    .accessibilityLabel(destination.title)
            } header: {
                editorHeader("规则")
            } footer: {
                Text("告诉 DeepSeek 哪些段落值得做动画；输出格式由软件自动约束。")
            }
        case .template:
            Section {
                variableBar
                TemplateTextEditor(text: $draft, proxy: editorProxy)
                    .frame(minHeight: 320)
            } header: {
                editorHeader("模板正文")
            } footer: {
                Text(missingVariables.isEmpty
                     ? "高亮的〔变量〕会在复制时替换为对应内容；点上方按钮可在光标处插入。"
                     : "缺少\(missingVariables.map { "〔\($0)〕" }.joined(separator: "、"))，保存时会自动补到末尾。")
                    .foregroundStyle(missingVariables.isEmpty ? Color.secondary : Color.orange)
            }
        }
    }

    private var missingVariables: [String] {
        AnimationTemplateText.variables.filter { !draft.contains($0.token) }.map(\.name)
    }

    private var variableBar: some View {
        HStack(spacing: 6) {
            Text("插入变量").foregroundStyle(.secondary)
            ForEach(AnimationTemplateText.variables, id: \.token) { variable in
                let isUsed = draft.contains(variable.token)
                Button { editorProxy.insert(variable.token) } label: {
                    Label(variable.name, systemImage: isUsed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(isUsed ? Color.accentColor : Color.orange)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(isUsed ? "在光标处插入〔\(variable.name)〕" : "模板中缺少〔\(variable.name)〕，点击在光标处插入")
                .accessibilityLabel("插入变量\(variable.name)")
                .accessibilityValue(isUsed ? "已使用" : "缺失")
            }
            Spacer()
        }
        .font(.callout)
    }

    private func editorHeader(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("恢复默认") { resetDraft = true }
                .buttonStyle(.link)
                .font(.callout)
        }
    }

    private func loadDraft() {
        switch destination {
        case .deepSeek: originalKey = model.deepSeekKeyDraft
        case .rules: draft = model.animationRules
        case .template: draft = AnimationTemplateText.display(model.animationTemplate)
        }
    }

    private func cancel() {
        if destination == .deepSeek { model.deepSeekKeyDraft = originalKey }
        dismiss()
    }

    private func commit() {
        switch destination {
        case .deepSeek:
            if model.saveAnimationConfiguration(saveAPIKey: true) { dismiss() }
        case .rules:
            let previous = model.animationRules
            model.animationRules = draft
            if model.saveAnimationConfiguration(saveAPIKey: false) { dismiss() } else { model.animationRules = previous }
        case .template:
            guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            model.animationTemplate = AnimationTemplateText.template(fromDisplay: draft)
            dismiss()
        }
    }
}
