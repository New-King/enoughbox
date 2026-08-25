# EnoughBox

**I don't need much.**

macOS 超轻量工具箱：**空壳宿主 + 插件中心按需安装**。

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
- 空状态 → **插件中心** 安装「示例」→ 侧栏出现项 → 右侧设置
- 翻译 / 截图为「即将推出」占位（不可安装）
- **浅色 / 深色 / 跟随系统**（工具栏菜单）
- **zh-Hans + en**（跟随系统语言）

## 文档

| 文档 | 说明 |
|------|------|
| [docs/MVP.md](docs/MVP.md) | MVP 范围与里程碑 |
| [docs/架构.md](docs/架构.md) | 架构与插件加载 |
| [docs/设计规范.md](docs/设计规范.md) | UI 令牌 |
| [docs/插件发布.md](docs/插件发布.md) | 官方插件审核政策 |

## 工程结构

```
EnoughBox/              # 宿主 SwiftUI 源码
Packages/EnoughBoxPluginSDK/
EnoughBox.xcodeproj     # xcodegen 生成
project.yml             # XcodeGen 配置
plugin-registry/        # 官方 manifest
```

## 技术栈

Swift + SwiftUI · macOS 14+ · String Catalog · EnoughBoxPluginSDK
