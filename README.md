# 拾笺 Jian

<p align="center">
  <img src="Sources/ClipFlow/Resources/JianAppIcon.png" width="144" alt="拾笺 App Icon">
</p>

<p align="center"><strong>把复制过的内容，随手捡回来。</strong></p>

拾笺是一款为键盘工作流设计的 macOS 剪贴板历史工具。复制过的文字、链接、文件和图片都会安静地留在本机；需要时按下快捷键呼出历史，用方向键选择，回车取回。

Jian is a local-first macOS clipboard history app built with SwiftUI. It helps you search, preview, and restore copied text, links, files, and images with a keyboard-first workflow.

它不是一个需要花时间整理的资料库，而是系统剪贴板缺失的“后退键”。

## 功能亮点

- macOS 原生菜单栏应用
- 本地优先，无账号、无云同步
- 快捷键呼出历史面板
- 输入即可搜索剪贴板历史
- `⌘1` 到 `⌘9` 快速取回最近记录
- `⌘Enter` 复制并粘贴回当前应用
- 支持文本、链接、文件、图片和截图
- 图片缩略图与完整窗口预览
- 历史默认保存 24 小时，可统一或按类型设置有效期

## 不打断正在做的事

你刚复制了一段文字，随后又复制了另一段。等想起前一段内容时，系统剪贴板已经把它覆盖了。

拾笺让找回它只需要三步：

1. 按下全局快捷键。
2. 用 `↑` / `↓` 找到那条记录。
3. 按 `Enter` 放回剪贴板。

不必离开当前应用，不必打开管理窗口，也不必伸手去找鼠标。面板打开后可以直接输入搜索，按 `⌘1` 到 `⌘9` 取最近记录，按 `⌘Enter` 复制并粘贴回当前应用，按 `Esc` 立即消失。

## 复制过的，不只有文字

拾笺可以保存：

- 文本与代码片段
- 网页链接
- 本地文件
- 图片与截图

图片会显示缩略图，也可以在完整窗口中预览。常用内容可以收藏，较早的记录可以搜索或按类型筛选。

## 平时安静，需要时出现

拾笺会在菜单栏保留一个轻量入口。全局快捷键只打开轻量历史面板；需要整理记录时，再从菜单栏进入完整管理界面。

默认快捷键为 `⇧⌘V`，也可以录制成自己习惯的组合键。

## 数据留在你的 Mac

拾笺不需要账号，没有网络请求，也不提供云同步。剪贴板历史与图片全部保存在本机。

历史默认保存 24 小时。你可以在设置中改成统一保存时长，也可以为文本、链接、图片和文件分别设置不同有效期。

现有数据位置：

- 历史记录：`~/Library/Application Support/ClipFlow/history.json`
- 图片：`~/Library/Application Support/ClipFlow/images/`

## 安装

前往 [Releases](https://github.com/l-mactools/clipflow/releases) 下载最新的 `Jian-*-macos-arm64.dmg`。打开后将 `Jian.app` 拖入“应用程序”目录即可。

如果 macOS 提示来自未识别开发者，可以在“系统设置 → 隐私与安全性”中选择“仍要打开”。当前发布包为本地签名版本，尚未进行 Apple 公证。

## 系统要求

- macOS 14 Sonoma 或更高版本
- Apple Silicon Mac

## 开发

要求 Xcode 15 或更高版本。

```bash
swift run
```

运行测试：

```bash
swift test
```

打包本地 release：

```bash
Scripts/package-app.sh 0.2.1
```

## 贡献

欢迎提交 issue 和 pull request。建议先在 issue 中说明场景、当前操作路径和期望体验，再提交实现。

适合优先贡献的方向：

- 快捷面板交互优化
- 剪贴板内容识别
- 历史保留策略
- 图片预览体验
- Homebrew Cask 分发

版本规划见 [docs/roadmap.md](docs/roadmap.md)。

## 许可

拾笺使用 [MIT License](LICENSE) 开源。
