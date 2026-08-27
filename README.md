# EnoughBox

**I don't need much.**

macOS 超轻量工具箱：**内置工具 + 按需启用**。

## 状态

**Phase 1 UI 已 scaffold** — 打开 Xcode 按 ⌘R 即可运行（需完整 Xcode，不能只有 Command Line Tools）。

## 快速开始

### 1. 安装 Xcode（必需）

从 App Store 安装 **Xcode**，然后：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

### 2. 打开工程

```bash
cd /Users/nujabes/projects/enoughbox
open EnoughBox.xcodeproj
```

选 **My Mac** → **⌘R** Run。

若修改了 `project.yml` 或新增源文件，重新生成工程：

```bash
brew install xcodegen   # 一次性
xcodegen generate
```

### 3. 当前可体验

- 系统设置式 **NavigationSplitView**（侧栏 + 详情）
- 空状态 → **内置工具中心** 启用工具 → 侧栏出现项 → 右侧设置
- 翻译已作为内置工具随 App 发布
- **浅色 / 深色 / 跟随系统**（工具栏菜单）
- 文案集中在 `UIStrings.swift`

## 文档

| 文档 | 说明 |
|------|------|
| [docs/开发前必读.md](docs/开发前必读.md) | 修改代码前的架构与验证约定 |
| [docs/MVP.md](docs/MVP.md) | MVP 范围与里程碑 |
| [docs/架构.md](docs/架构.md) | 内置工具架构 |
| [docs/设计规范.md](docs/设计规范.md) | UI 令牌 |
| [docs/tools/README.md](docs/tools/README.md) | 内置工具说明与排障 |

## 工程结构

```
EnoughBox/              # 宿主 SwiftUI 源码与内置工具
EnoughBox.xcodeproj     # xcodegen 生成
project.yml             # XcodeGen 配置
EnoughBox/Features/Translate/ # 内置翻译工具源码
```

## 技术栈

Swift + SwiftUI · macOS 14+ · KeyboardShortcuts
