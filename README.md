# B-roll 配对台

一个本地 macOS 小工具：把拍摄素材目录里的视频或图片拖到对应的文案句子上，自动复制到归档目录、生成稳定文件名，并生成供 Codex 使用的 `broll-manifest.json`。

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

7. 同一目录会自动生成：

   - `broll-manifest.json`：给 Codex / ChatCut 读取的精简映射，只列出已绑定素材的文案
   - `broll-manifest.md`：人可以直接查看的表格

JSON 中每条映射包含 `id`、完整 `text` 和归档文件名数组 `files`。轨道由 Codex 根据 ChatCut 当前时间线安排；视频默认静音。`BR001` 是文案锚点的顺序编号，用来核对文案与文件，不是时间码；实际匹配以完整文案为准。

```json
{
  "defaultAudio": "mute",
  "placements": [
    {
      "id": "BR001",
      "text": "文案的完整句子",
      "files": ["BR001_文案的完整句子.mp4", "BR001_文案的完整句子_02.png"]
    }
  ]
}
```

刷新网页不会丢失已绑定的素材：配对记录、素材目录和归档目录都会记在当前浏览器；如果浏览器本地记录不可用，重新授权归档目录后，工具还会尝试从 `broll-manifest.json` 恢复。

## 给 Codex 的固定要求

```text
读取 B-roll 目录中的 broll-manifest.json。
读取当前 ChatCut 项目的最终 A-roll 文字稿和时间线。
根据 placements 中的 text 找到对应口播位置，
把 files 中的素材放到该位置上方的可用轨道；同一句有多个文件时，根据当前时间线安排轨道。
视频默认静音，不修改 A-roll。
完成后检查每个素材是否真正出现在正确时间线上。
```

## 重要限制

这是浏览器本地工具，采用“复制”模式：原始 Finder 文件不会被删除或移动。这样更安全，也避免误操作丢失相机原片。

如果清除了浏览器网站数据，浏览器本地缓存会被清空；目标目录中的 `broll-manifest.json` 仍可用于恢复配对记录。

Chrome / Edge 才支持选择本地目录并写入文件。若后续需要“拖入后直接移动原文件”，应改做原生 macOS 小应用或 Finder Quick Action，而不是纯 HTML。

## 原生 macOS 版本

项目现在同时包含一个 SwiftUI 原生 macOS App：

- 打开 `BrollNamer.xcodeproj`，用 Xcode 16.4 或更新版本运行 `BrollNamer` target。
- 最低支持 macOS 14；界面使用 `HSplitView`、系统 `List`、`TextEditor`、SF Symbols 和标准目录选择面板。
- 原有的复制模式和文件名规则保留；JSON 使用精简映射格式，Codex 根据 ChatCut 当前时间线选择 A-roll 上方的可用轨道，视频默认静音。
- 第一次选择素材来源和归档位置时，App 会请求用户选择目录权限，并通过安全作用域书签记住目录；原始 Finder 文件不会被移动或删除。
- 绑定素材前必须选择“素材来源”和“归档位置”，并填写“期数 / 前缀”。取消单条绑定时会删除归档目录里的那份复制文件，并同步更新 JSON 与 Markdown 清单；原始素材保留。
- “清空配对记录”只清除绑定数据，保留归档目录中的复制文件，适合重置清单但继续保留素材。
- 素材目录操作集中在当前目录所在行，可更换、打开目录，并通过“…”管理常用目录和收藏；“全部 / 视频 / 图片”筛选显示在素材列表上方。
- `BrollNamerApp/` 中是 SwiftUI 源码，`BrollNamer.entitlements` 开启了“用户选择的文件读写”沙盒权限。
