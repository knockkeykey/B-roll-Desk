# B-roll 配对台

一个本地 macOS 小工具：把拍摄素材目录里的视频拖到对应的文案句子上，自动复制到归档目录、生成稳定文件名，并生成供 Codex 使用的 `broll-manifest.json`。

## 使用方法

1. 用 Chrome 或 Edge 双击运行 `run.command`。
2. 在网页中粘贴文案，默认一行对应一个 B-roll 锚点。
3. 点击“选择素材目录”，选择拍摄后存放原片的目录；右侧会列出其中的视频。
4. 点击“选择归档目录”，选择 ChatCut 后续使用的 B-roll 目录。
5. 从右侧素材列表拖到左侧对应的文案行；也可以继续从 Finder 直接拖入。
6. 工具会生成类似下面的文件：

   ```text
   BR001_我打开ChatCut之后.mp4
   BR002_到了剪映里面.mov
   ```

6. 同一目录会自动生成：

   - `broll-manifest.json`：给 Codex / ChatCut 读取的结构化映射
   - `broll-manifest.md`：人可以直接查看的表格

刷新网页不会丢失已绑定的素材：配对记录、素材目录和归档目录都会记在当前浏览器；如果浏览器本地记录不可用，重新授权归档目录后，工具还会尝试从 `broll-manifest.json` 恢复。

## 给 Codex 的固定要求

```text
读取 B-roll 目录中的 broll-manifest.json。
读取当前 ChatCut 项目的最终 A-roll 文字稿和时间线。
根据 manifest 中的 anchorText 找到对应口播位置，
把 assets 中的 outputName 放到 V2，默认静音，不修改 A-roll。
完成后检查每个素材是否真正出现在正确时间线上。
```

## 重要限制

这是浏览器本地工具，采用“复制”模式：原始 Finder 文件不会被删除或移动。这样更安全，也避免误操作丢失相机原片。

如果清除了浏览器网站数据，浏览器本地缓存会被清空；目标目录中的 `broll-manifest.json` 仍可用于恢复配对记录。

Chrome / Edge 才支持选择本地目录并写入文件。若后续需要“拖入后直接移动原文件”，应改做原生 macOS 小应用或 Finder Quick Action，而不是纯 HTML。

## 原生 macOS 版本

项目现在同时包含一个 SwiftUI 原生 macOS App：

- 打开 `BrollNamer.xcodeproj`，用 Xcode 16.4 或更新版本运行 `BrollNamer` target。
- 最低支持 macOS 14；界面使用 `NavigationSplitView`、系统 `List`、`TextEditor`、SF Symbols 和标准目录选择面板。
- 原有的复制模式、文件名规则、FS/PIP、V2、静音、`broll-manifest.json` / `.md` 契约保持不变。
- 第一次选择素材来源和归档位置时，App 会请求用户选择目录权限，并通过安全作用域书签记住目录；原始 Finder 文件不会被移动或删除。
- `BrollNamerApp/` 中是 SwiftUI 源码，`BrollNamer.entitlements` 开启了“用户选择的文件读写”沙盒权限。
