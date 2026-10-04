import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Analysis and import; production tasks live in the filtered script list. Configuration lives in a secondary sheet so
/// the primary surface is about progress, not about editing long prompt text.
struct AnimationWorkspaceView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var issueSelections: [UUID: String] = [:]
    @State private var settingsDestination: AnimationSettingsDestination?
    @State private var isAnalysisHelpPresented = false
    @State private var isDropTargeted = false

    private var hasKey: Bool { !model.deepSeekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var scriptRowCount: Int { model.animationScriptRowCount }
    private var boundCount: Int { model.activeAnimationTasks.count - model.pendingAnimationTasks.count }
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
                switch model.animationPanelTab {
                case 1: importPage
                default: analyzePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 820, height: 640)
        .disabled(model.isAnalyzingAnimations)
        .accessibilityHidden(model.isAnalyzingAnimations)
        .blur(radius: model.isAnalyzingAnimations ? 2 : 0)
        .overlay {
            if model.isAnalyzingAnimations {
                analysisLoadingOverlay
            }
        }
        .interactiveDismissDisabled(model.isBusy || model.isAnalyzingAnimations)
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
                    Text("筛选动画文案，在文案列表中制作，再把成品自动绑定回文案。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                stepButton(0, title: "分析文案", detail: model.isAnalyzingAnimations ? "DeepSeek 分析中…" : (isReviewing ? "\(model.animationReviewItems.count) 段待确认" : "\(scriptRowCount) 条文案 · 全文分析"),
                           done: !model.activeAnimationTasks.isEmpty)
                Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                stepButton(1, title: "导入匹配",
                           detail: model.animationImportIssues.isEmpty ? "已绑定 \(boundCount) 条" : "\(model.animationImportIssues.count) 个待处理",
                           done: !model.activeAnimationTasks.isEmpty && model.pendingAnimationTasks.isEmpty)
            }
        }
    }

    private func stepButton(_ tab: Int, title: String, detail: String, done: Bool) -> some View {
        let selected = model.animationPanelTab == tab
        let isLoading = tab == 0 && model.isAnalyzingAnimations
        return Button {
            withAnimation(.snappy(duration: 0.2)) { model.animationPanelTab = tab }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(selected || isLoading ? Color.accentColor : (done ? Color.green : Color.secondary.opacity(0.18)))
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .environment(\.colorScheme, .dark)
                            .accessibilityLabel("正在分析全文")
                    } else if done && !selected {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text("\(tab + 1)").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.secondary)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第 \(tab + 1) 步：\(title)，\(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isTestingDeepSeek || model.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(model.animationFeedback.isEmpty ? footerHint : model.animationFeedback)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("完成") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isBusy)
            Button("复制全部提示词") { model.copyAllAnimationPrompts() }
                .disabled(model.activeAnimationTasks.isEmpty || model.isBusy)
            primaryAction
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }

    private var footerHint: String {
        switch model.animationPanelTab {
        case 1: return "成品按文案文件名模糊匹配，复制到项目 B-roll 目录，原件保留。"
        default: return isReviewing ? "勾选要做动画的段落；应用后会拆分并标记，可 ⌘Z 撤销。" : "整篇文案会发送给 DeepSeek；所有有文字的条目都参与判断，勾选应用后才修改。"
        }
    }

    @ViewBuilder private var primaryAction: some View {
        switch model.animationPanelTab {
        case 1:
            Button("选择动画文件夹…") { model.chooseAnimationDirectory() }
                .disabled(model.isBusy || model.isAnalyzingAnimations || model.activeAnimationTasks.isEmpty)
        default:
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
}

// MARK: - Step 1 · 分析

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
                    Divider().padding(.leading, 46)
                    SettingsRow(systemImage: "text.badge.star", tint: .pink, title: "制作提示词模板",
                                value: model.animationTemplate == AnimationWorkflow.defaultTemplate ? "默认" : "已自定义") { settingsDestination = .template }
                    Divider().padding(.leading, 46)
                    AnimationCharacterReferenceEditor(model: model)
                    Divider().padding(.leading, 46)
                    SettingsRow(systemImage: "folder", tint: .blue, title: "视频输出目录",
                                value: model.animationOutputDirectoryPath.isEmpty ? "未设置" : (model.animationOutputDirectoryPath as NSString).lastPathComponent) { settingsDestination = .outputDirectory }
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

// MARK: - Step 2 · 导入

extension AnimationWorkspaceView {
    var importPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            dropZone
            if !model.animationImportIssues.isEmpty {
                HStack {
                    Text("需要手动指定 · \(model.animationImportIssues.count) 个文件")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("尚缺动画 \(model.pendingAnimationTasks.count) 条").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.animationImportIssues.enumerated()), id: \.element.id) { index, issue in
                            if index > 0 { Divider().padding(.leading, 46) }
                            issueRow(issue)
                        }
                    }
                    .cardBackground()
                }
            }
        }
        .padding(24)
        .animation(.snappy(duration: 0.2), value: model.animationImportIssues.count)
    }

    private var dropZone: some View {
        let compact = !model.animationImportIssues.isEmpty
        let canImport = !model.activeAnimationTasks.isEmpty && !model.isBusy
        return VStack(spacing: compact ? 6 : 12) {
            Image(systemName: isDropTargeted ? "folder.fill.badge.plus" : "folder.badge.plus")
                .font(.system(size: compact ? 26 : 40, weight: .light))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(model.activeAnimationTasks.isEmpty ? "先生成动画任务，再导入成品" : "把动画成品文件夹拖到这里")
                .font(compact ? .callout.weight(.medium) : .title3.weight(.medium))
            if !compact {
                Text("按文案文件名模糊匹配，复制到项目 B-roll 目录并保留原件；已有绑定会跳过，多个候选可手动指定。\n尚缺动画 \(model.pendingAnimationTasks.count) 条。")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 96 : 300)
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { if canImport { model.chooseAnimationDirectory() } }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard canImport else { return false }
            FileURLDropLoader.loadURLs(from: providers) { urls in
                guard let folder = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) else { return }
                model.importDroppedAnimationDirectory(folder)
            }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("拖入文件夹，或按下以选择动画文件夹")
    }

    private func issueRow(_ issue: AnimationImportIssue) -> some View {
        let pending = model.pendingAnimationTasks
        // A manual choice wins; otherwise preselect the suggestion while it is still bindable.
        let current = issueSelections[issue.id] ?? issue.suggestedTaskID ?? ""
        let chosen = pending.contains(where: { $0.id == current }) ? current : ""
        let selection = Binding(get: { chosen }, set: { issueSelections[issue.id] = $0 })
        let ranked = pending
            .map { ($0, AnimationWorkflow.score(file: issue.url, task: $0)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let canBind = !model.isBusy && !chosen.isEmpty
        return HStack(spacing: 12) {
            Image(systemName: "film")
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.url.lastPathComponent).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                if let suggested = issue.suggestedTaskID, suggested == chosen {
                    Label("已按文件名相似度预选，请确认后绑定", systemImage: "wand.and.stars")
                        .font(.caption).foregroundStyle(Color.accentColor)
                } else {
                    Text(issue.message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button { NSWorkspace.shared.open(issue.url) } label: { Image(systemName: "play.circle") }
                .buttonStyle(.borderless)
                .help("预览视频")
            Picker("对应文案", selection: selection) {
                Text("选择文案…").tag("")
                ForEach(ranked) { task in
                    Text(task.id == issue.suggestedTaskID ? "★ " + task.text : task.text).lineLimit(1).tag(task.id)
                }
            }
            .labelsHidden()
            .frame(width: 230)
            .accessibilityLabel("为 \(issue.url.lastPathComponent) 选择对应文案")
            Button("绑定") { Task { await model.bindAnimationIssue(issue.id, to: chosen) } }
                .disabled(!canBind)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Settings

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
                Text("复制提示词时自动加入角色替换说明")
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

private enum AnimationSettingsDestination: String, Identifiable {
    case overview, deepSeek, rules, template, character, outputDirectory
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: return "动画助手设置"
        case .deepSeek: return "DeepSeek 连接"
        case .rules: return "动画判断规则"
        case .template: return "制作提示词模板"
        case .character: return "角色参考图"
        case .outputDirectory: return "视频输出目录"
        }
    }
    var height: CGFloat {
        switch self {
        case .overview: return 410
        case .deepSeek: return 310
        case .rules, .template: return 560
        case .character: return 330
        case .outputDirectory: return 310
        }
    }
}

private struct AnimationSettingsSheet: View {
    @Bindable var model: AppModel
    @State var destination: AnimationSettingsDestination
    @Environment(\.dismiss) private var dismiss
    @State private var revealKey = false
    @State private var resetTarget: ResetTarget?

    enum ResetTarget: Identifiable {
        case rules, template
        var id: Self { self }
        var title: String { self == .rules ? "恢复默认判断规则？" : "恢复默认制作模板？" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(destination.title).font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(20)
            Divider()
            Form {
                if destination == .overview {
                    Section {
                        settingsLink(.deepSeek, icon: "key.fill", tint: .blue)
                        settingsLink(.rules, icon: "checklist", tint: .purple)
                        settingsLink(.template, icon: "text.badge.star", tint: .pink)
                        settingsLink(.character, icon: "person.crop.square", tint: .orange)
                        settingsLink(.outputDirectory, icon: "folder", tint: .blue)
                    }
                }
                if destination == .deepSeek {
                    Section {
                        HStack(spacing: 8) {
                            Group {
                                if revealKey {
                                    TextField("API Key", text: $model.deepSeekKeyDraft, prompt: Text("sk-…"))
                                } else {
                                    SecureField("API Key", text: $model.deepSeekKeyDraft, prompt: Text("sk-…"))
                                }
                            }
                            .accessibilityLabel("DeepSeek API Key")
                            Button { revealKey.toggle() } label: { Image(systemName: revealKey ? "eye.slash" : "eye") }
                                .buttonStyle(.borderless)
                                .help(revealKey ? "隐藏 API Key" : "显示 API Key")
                        }
                        LabeledContent("模型") {
                            HStack(spacing: 10) {
                                Text("deepseek-flash").font(.callout.monospaced()).foregroundStyle(.secondary)
                                if model.isTestingDeepSeek { ProgressView().controlSize(.small) }
                                Button("测试连接") { Task { await model.testDeepSeekConnection() } }
                                    .disabled(model.isTestingDeepSeek || model.deepSeekKeyDraft.isEmpty)
                            }
                        }
                    } header: {
                        Text("DeepSeek")
                    }

                }
                if destination == .rules {
                    Section {
                        promptEditor($model.animationRules, label: "动画判断规则", height: 320)
                    } header: {
                        sectionHeader("动画判断规则", isDefault: model.animationRules == AnimationWorkflow.defaultRules) { resetTarget = .rules }
                    }

                }
                if destination == .character {
                    Section {
                        AnimationCharacterReferenceEditor(model: model)
                    } header: {
                        Text("角色参考图")
                    }

                }
                if destination == .outputDirectory {
                    Section {
                        TextField("目录路径", text: $model.animationOutputDirectoryPath, prompt: Text("粘贴完整文件夹路径"))
                            .accessibilityLabel("视频输出目录路径")
                        HStack {
                            Spacer()
                            if !model.animationOutputDirectoryPath.isEmpty {
                                Button("清空") { model.animationOutputDirectoryPath = "" }
                            }
                            Button("选择文件夹…") { chooseOutputDirectory() }
                        }
                    } header: {
                        Text("视频输出目录")
                    }
                }
                if destination == .template {
                    Section {
                        promptEditor($model.animationTemplate, label: "动画制作提示词模板", height: 320)
                    } header: {
                        sectionHeader("制作提示词模板", isDefault: model.animationTemplate == AnimationWorkflow.defaultTemplate) { resetTarget = .template }
                    }
                }
            }
            .formStyle(.grouped)

            if let note = configurationNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Divider()
            HStack {
                Text(model.animationFeedback).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("完成") {
                    if model.saveAnimationConfiguration(saveAPIKey: destination == .deepSeek) { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.isTestingDeepSeek)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 640, height: destination.height)
        .interactiveDismissDisabled(model.isTestingDeepSeek)
        .confirmationDialog(resetTarget?.title ?? "", isPresented: Binding(get: { resetTarget != nil }, set: { if !$0 { resetTarget = nil } }),
                            presenting: resetTarget) { target in
            Button("恢复默认", role: .destructive) {
                if target == .rules { model.animationRules = AnimationWorkflow.defaultRules }
                else { model.animationTemplate = AnimationWorkflow.defaultTemplate }
            }
        } message: { _ in
            Text("当前的自定义内容将被覆盖。")
        }
    }

    private var configurationNote: String? {
        switch destination {
        case .overview: return nil
        case .deepSeek: return "API Key 只保存在本机钥匙串，不写入项目文件或导出的 JSON。"
        case .rules: return "告诉 DeepSeek 什么样的段落值得做动画。输出格式由软件自动约束，表格要求会被忽略。"
        case .template: return "{{text}} 替换为该条文案，{{character}} 替换为角色参考图；非空的表达重点和已设置的视频输出目录会自动追加。"
        case .character: return "替换模板中的 {{character}}；模板里没有该占位符时会追加到提示词末尾。未设置时，会保留使用你提供的角色参考图的说明。"
        case .outputDirectory: return "复制单条或全部提示词时，会自动加上这个输出目录。可以粘贴尚未创建的目录路径；未设置时省略该要求。"
        }
    }

    private func settingsLink(_ target: AnimationSettingsDestination, icon: String, tint: Color) -> some View {
        SettingsRow(systemImage: icon, tint: tint, title: target.title, value: "") {
            destination = target
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择视频输出目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let path = model.animationOutputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.animationOutputDirectoryPath = url.path
    }

    private func sectionHeader(_ title: String, isDefault: Bool, reset: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if !isDefault {
                Button("恢复默认", action: reset).buttonStyle(.link).font(.callout)
            }
        }
    }

    private func promptEditor(_ text: Binding<String>, label: String, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .frame(height: height)
            .accessibilityLabel(label)
    }
}
