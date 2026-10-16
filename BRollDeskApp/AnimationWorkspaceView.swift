import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Independent animation production and full-script analysis workspace.
struct AnimationWorkspaceView: View {
    @Bindable var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("broll-namer-animation-always-on-top") private var isPinned = false
    @AppStorage("broll-namer-theme") private var themeRawValue = AppTheme.system.rawValue
    @State private var page = AnimationPage.production
    @State private var sections: [AnimationTemplateSection] = []
    @State private var isScriptDropTargeted = false
    @State private var resetTemplate = false
    @State private var settingsDestination: AnimationSettingsDestination?
    @State private var isAnalysisHelpPresented = false

    private var hasKey: Bool { !model.deepSeekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var scriptRowCount: Int { model.animationScriptRowCount }
    private var selectedReviewCount: Int { model.animationReviewItems.filter(\.isSelected).count }
    private var isReviewing: Bool { !model.animationReviewItems.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            Divider()
            Group {
                if page == .production { productionPage }
                else {
                    analyzePage
                        .disabled(model.isAnalyzingAnimations)
                        .overlay { if model.isAnalyzingAnimations { analysisLoadingOverlay } }
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .background(AuxiliaryWindowLevelController(isFloating: isPinned).frame(width: 0, height: 0))
        .preferredColorScheme(preferredColorScheme)
        .onAppear { loadTemplate() }
        .onChange(of: model.animationTemplate) { _, value in
            if sections.map(\.raw).joined() != value { loadTemplate() }
        }
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
        .confirmationDialog("恢复默认制作提示词？", isPresented: $resetTemplate) {
            Button("恢复默认", role: .destructive) { model.animationTemplate = AnimationWorkflow.defaultTemplate }
        } message: { Text("当前自定义提示词将被覆盖，角色图和输出目录保留。") }
        .sheet(item: $settingsDestination) { destination in
            AnimationSettingsSheet(model: model, destination: destination)
        }
    }

    private var analysisLoadingOverlay: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.65)
                .contentShape(Rectangle())

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.4)
                    .frame(width: 52, height: 52)
                    .accessibilityLabel("分析进行中")

                VStack(spacing: 6) {
                    Text("正在分析全文")
                        .font(.title3.weight(.semibold))
                    Text("DeepSeek 正在筛选适合动画的段落")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("\(scriptRowCount) 条文案 · 通常需要几十秒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("取消分析") { model.cancelAnimationAnalysis() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(28)
            .frame(width: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("全文分析进行中")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 动画助手").font(.title3.weight(.semibold))
                    Text("拖入动画文案，配置并复制制作提示词。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(isOn: $isPinned) {
                    Label("置顶", systemImage: isPinned ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .accessibilityLabel("动画助手窗口置顶")
            }
            Picker("工作区", selection: $page) {
                Text("制作提示词").tag(AnimationPage.production)
                Text("全文分析").tag(AnimationPage.analysis)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isTestingDeepSeek || model.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(model.animationFeedback.isEmpty ? (page == .production ? "仅复制当前选中文案的完整提示词；修改会自动保存。" : footerHint) : model.animationFeedback)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("关闭") { dismissWindow(id: "animation-assistant") }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isBusy)
            if page == .production {
                Button("复制提示词") {
                    if let task = model.selectedAnimationWorkspaceTask { model.copyAnimationPrompt(task) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedAnimationWorkspaceTask == nil || model.isBusy)
            } else {
                primaryAction.buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
    }

    private var footerHint: String {
        isReviewing ? "勾选要做动画的段落；应用后会拆分并标记，可 ⌘Z 撤销。" : "整篇文案会发送给 DeepSeek；所有有文字的条目都参与判断，勾选应用后才修改。"
    }

    private enum AnimationPage { case production, analysis }

    private var preferredColorScheme: ColorScheme? {
        switch AppTheme(rawValue: themeRawValue) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private func loadTemplate() {
        sections = AnimationTemplateSection.parse(model.animationTemplate)
        let normalized = sections.map(\.raw).joined()
        if normalized != model.animationTemplate { model.animationTemplate = normalized }
    }

    private func sectionBinding(_ index: Int) -> Binding<String> {
        Binding {
            guard sections.indices.contains(index) else { return "" }
            return sections[index].editableText.trimmingCharacters(in: .newlines)
        } set: { value in
            guard sections.indices.contains(index) else { return }
            let old = sections[index].raw
            let prefix = String(old.prefix(while: { $0 == "\n" }))
            let suffix = String(old.reversed().prefix(while: { $0 == "\n" }).reversed())
            sections[index].updateText(prefix + value + suffix)
            model.animationTemplate = sections.map(\.raw).joined()
        }
    }

    private var productionPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("动画制作提示词").font(.headline)
                    Spacer()
                    Text("自动保存").font(.caption).foregroundStyle(.secondary)
                    Button("恢复默认") { resetTemplate = true }.buttonStyle(.link)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sections.indices, id: \.self) { index in
                        if sections[index].kind != .text || !sections[index].raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("输入提示词", text: sectionBinding(index), axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14))
                                    .lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityLabel("提示词正文第\(index + 1)段")
                                switch sections[index].kind {
                                case .text: EmptyView()
                                case .character: AnimationCharacterReferenceEditor(model: model).cardBackground()
                                case .script: scriptDropCard
                                case .outputDirectory: AnimationOutputDirectoryEditor(model: model).cardBackground()
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
    }

    private var scriptDropCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("动画文案", systemImage: "text.badge.plus").font(.subheadline.weight(.semibold))
            if model.animationWorkspaceTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.title2)
                    Text("把动画条目拖到这里").font(.body.weight(.medium))
                    Text("拖动主列表动画条目上的拖拽柄；不会改变原条目。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ForEach(model.animationWorkspaceTasks) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            model.selectedAnimationWorkspaceRowID = task.rowID
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: task.rowID == model.selectedAnimationWorkspaceRowID ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(Color.accentColor)
                                Text(task.text).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("选择文案：\(task.text)")
                        .accessibilityValue(task.rowID == model.selectedAnimationWorkspaceRowID ? "已选择" : "未选择")
                        Button { model.removeAnimationWorkspaceRow(task.rowID) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除文案：\(task.text)")
                    }
                    .padding(10)
                    .background(task.rowID == model.selectedAnimationWorkspaceRowID ? Color.accentColor.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
                if let task = model.selectedAnimationWorkspaceTask, !model.note(for: task.rowID).isEmpty {
                    Text("表达重点：" + model.note(for: task.rowID)).font(.callout).foregroundStyle(.secondary)
                }
                Text("继续拖入，可选择替换当前文案或保留多条。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(isScriptDropTargeted ? 0.12 : 0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(isScriptDropTargeted ? 0.8 : 0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
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

    @ViewBuilder private var primaryAction: some View {
        if isReviewing {
            Button("应用 \(selectedReviewCount) 段") { model.applyAnimationReview() }
                .disabled(selectedReviewCount == 0 || model.isBusy)
        } else if model.isAnalyzingAnimations {
            Button { model.cancelAnimationAnalysis() } label: {
                Text("取消分析").frame(minWidth: 84)
            }
        } else {
            Button { model.startAnimationAnalysis() } label: {
                Text("分析动画段落").frame(minWidth: 84)
            }
                .disabled(!hasKey || scriptRowCount == 0 || model.isTestingDeepSeek || model.isBusy)
        }
    }
}

// MARK: - 文案分析

extension AnimationWorkspaceView {
    @ViewBuilder var analyzePage: some View {
        if isReviewing { reviewPage } else { overviewPage }
    }

    private var reviewPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DeepSeek 推荐了 \(model.animationReviewItems.count) 段").font(.headline)
                    Text("取消勾选不需要的段落，文案在应用前不会改动。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(selectedReviewCount == model.animationReviewItems.count ? "全不选" : "全选") {
                    let target = selectedReviewCount != model.animationReviewItems.count
                    for index in model.animationReviewItems.indices { model.animationReviewItems[index].isSelected = target }
                }
                Button("放弃结果", role: .destructive) { model.discardAnimationReview() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            List {
                ForEach($model.animationReviewItems) { $item in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("", isOn: $item.isSelected)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .accessibilityLabel("选择：\(item.candidate.text)")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.candidate.text)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(item.isSelected ? Color.primary : Color.secondary)
                            Label(item.candidate.reason, systemImage: "lightbulb")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.vertical, 6)
                    .opacity(item.isSelected ? 1 : 0.6)
                    .contentShape(Rectangle())
                    .onTapGesture { item.isSelected.toggle() }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var overviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    StatTile(value: scriptRowCount, title: "全文分析", systemImage: "wand.and.stars", tint: .accentColor) {
                        Button { isAnalysisHelpPresented.toggle() } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("全文分析说明")
                        .help("查看分析范围及应用后的变化")
                        .popover(isPresented: $isAnalysisHelpPresented) {
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

                GroupCard(title: "分析配置") {
                    SettingsRow(systemImage: "key.fill", tint: .blue, title: "DeepSeek",
                                value: hasKey ? "已保存在钥匙串 · deepseek-flash" : "未设置 API Key",
                                valueTint: hasKey ? .secondary : .orange) { settingsDestination = .deepSeek }
                    Divider().padding(.leading, 46)
                    SettingsRow(systemImage: "checklist", tint: .purple, title: "动画判断规则",
                                value: model.animationRules == AnimationWorkflow.defaultRules ? "默认" : "已自定义") { settingsDestination = .rules }

                }
            }
            .padding(24)
        }
    }
}

struct StatTile<Accessory: View>: View {
    let value: Int
    let title: String
    let systemImage: String
    let tint: Color
    let accessory: Accessory

    init(value: Int, title: String, systemImage: String, tint: Color, @ViewBuilder accessory: () -> Accessory) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
    }

    init(value: Int, title: String, systemImage: String, tint: Color) where Accessory == EmptyView {
        self.init(value: value, title: title, systemImage: systemImage, tint: tint) { EmptyView() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.callout)
                    .foregroundStyle(tint == .secondary ? Color.secondary : tint)
                accessory
            }
            Text("\(value)")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }
}

struct GroupCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) { content }.cardBackground()
        }
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
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                Spacer()
                Text(value).foregroundStyle(valueTint)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

extension View {
    func cardBackground(cornerRadius: CGFloat = 10) -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - Settings

private struct AnimationOutputDirectoryEditor: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("动画输出目录").font(.system(size: 14, weight: .medium))
            HStack {
                TextField("填写输出文件夹的完整路径", text: $model.animationOutputDirectory)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("动画输出目录")
                Button("选择文件夹…") { chooseDirectory() }
                if !model.animationOutputDirectory.isEmpty {
                    Button("清除") { model.animationOutputDirectory = "" }
                }
            }
            Text("复制时加入此目录；代码等文件夹按“【文案】-【时间】”命名，视频以文案命名。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("角色参考图").font(.system(size: 14, weight: .medium))
                Text(model.animationCharacterPath.isEmpty ? "拖入图片，或点击选择图片" : (model.animationCharacterPath as NSString).lastPathComponent)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text("由制作 AI 判断是否需要角色，需要时使用此参考图")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !model.animationCharacterPath.isEmpty {
                Button("移除") { model.removeAnimationCharacterImage() }
                    .accessibilityLabel("移除角色参考图")
            }
            Button(model.animationCharacterPath.isEmpty ? "选择图片…" : "更换图片…") { chooseCharacter() }
                .accessibilityLabel("选择角色参考图")
        }
        .padding(12)
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
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
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.08))
            if let image = model.animationCharacterImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: model.animationCharacterPath.isEmpty ? "photo.badge.plus" : "exclamationmark.triangle")
                    .font(.system(size: 24)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private enum AnimationSettingsDestination: Identifiable {
    case deepSeek, rules
    var id: Self { self }
    var title: String { self == .deepSeek ? "DeepSeek 连接" : "动画判断规则" }
}

private struct AnimationSettingsSheet: View {
    @Bindable var model: AppModel
    let destination: AnimationSettingsDestination
    @Environment(\.dismiss) private var dismiss
    @State private var revealKey = false
    @State private var resetRules = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(destination.title).font(.title3.weight(.semibold))
                Spacer()
                if destination == .rules {
                    Button("恢复默认") { resetRules = true }.buttonStyle(.link)
                }
            }.padding(20)
            Divider()
            Form {
                if destination == .deepSeek {
                    Section("DeepSeek") {
                        HStack {
                            Group {
                                if revealKey { TextField("API Key", text: $model.deepSeekKeyDraft) }
                                else { SecureField("API Key", text: $model.deepSeekKeyDraft) }
                            }.accessibilityLabel("DeepSeek API Key")
                            Button { revealKey.toggle() } label: {
                                Image(systemName: revealKey ? "eye.slash" : "eye")
                            }.buttonStyle(.borderless)
                        }
                        LabeledContent("模型") {
                            Text("deepseek-flash").font(.callout.monospaced()).foregroundStyle(.secondary)
                            if model.isTestingDeepSeek { ProgressView().controlSize(.small) }
                            Button("测试连接") { Task { await model.testDeepSeekConnection() } }
                                .disabled(model.isTestingDeepSeek || model.deepSeekKeyDraft.isEmpty)
                        }
                    }
                } else {
                    TextEditor(text: $model.animationRules)
                        .font(.system(size: 13)).lineSpacing(3)
                        .frame(minHeight: 300)
                        .accessibilityLabel("动画判断规则")
                }
            }.formStyle(.grouped)
            Text(destination == .deepSeek ? "API Key 只保存在本机钥匙串，不写入项目或导出的 JSON。" : "告诉 DeepSeek 哪些段落值得做动画；输出格式由软件自动约束。")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 16)
            Divider()
            HStack {
                Text(model.animationFeedback).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("完成") {
                    if model.saveAnimationConfiguration(saveAPIKey: destination == .deepSeek) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isTestingDeepSeek)
            }.padding(16)
        }
        .frame(width: 640, height: destination == .deepSeek ? 320 : 550)
        .interactiveDismissDisabled(model.isTestingDeepSeek)
        .confirmationDialog("恢复默认判断规则？", isPresented: $resetRules) {
            Button("恢复默认", role: .destructive) { model.animationRules = AnimationWorkflow.defaultRules }
        } message: { Text("当前自定义判断规则将被覆盖。") }
    }
}
