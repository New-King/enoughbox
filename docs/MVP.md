# EnoughBox MVP 方案

> 版本：v0.1 · 2026-08-25  
> Slogan：**I don't need much.**  
> 目标：**可运行的空壳宿主 + 插件中心 + 1 个示例插件**，验证「装完 App 无业务功能 → 安装插件后才出现侧栏项与设置」全流程。  
> 翻译 / 截图插件 **不在 MVP 内**，紧接 MVP 验收后作为 Phase 2（你会提供参考项目）。

---

## 1. 产品定义（MVP 边界）

### 做什么

| 能力 | MVP |
|------|-----|
| 空壳主窗口（左列表 + 右设置） | ✅ |
| 浅色 / 深色 / 跟随系统 | ✅ |
| 多语言（zh-Hans + en，String Catalog） | ✅ Phase 1 起全 key 化 |
| App 内语言切换 | ⏸ Phase 1.1（MVP 先跟随系统） |
| 插件中心：浏览 manifest、安装、卸载 | ✅ |
| 动态加载 `.plugin` bundle | ✅ |
| 示例插件：设置页 + 1 个全局热键 | ✅ |
| 登录时启动（LaunchAtLogin） | ⏸ 可选 1.1 |
| 翻译（划词/OCR） | ❌ Phase 2 |
| 截图（区域/长截） | ❌ Phase 2 |
| Sparkle 自动更新 | ❌ Phase 1.1 |
| 官方插件 curated 审核 + CI 构建 | ✅ 政策见 [插件发布.md](插件发布.md) |
| 用户随意上传插件 / 开放 sideload | ❌ Phase 3 可选，默认关 |

### 不做什么（避免 scope 膨胀）

- 不做搜索框启动器（不是 uTools/Rubick 形态）
- 不预装任何「系统插件」
- 不做 Web 插件 / JS 运行时
- 不做 iCloud 同步

### 成功标准（验收）

1. 全新安装打开 App：**左侧为空**，右侧为空状态引导「打开插件中心」。
2. 从插件中心安装「示例插件」后：左侧出现一项，右侧展示该插件设置（含快捷键录制）。
3. 卸载后：侧栏项消失，热键失效。
4. 切换深/浅色：全局令牌一致，无硬编码色块穿帮。
5. 重启 App：已装插件自动加载，设置与热键保留。

---

## 2. 界面设计（极简 · 黑白双主题）

布局参考 **系统设置**：安静、分区清晰、无多余 chrome。

```
┌──────────────────────────────────────────────────────────────┐
│  EnoughBox          [插件中心]              [◐ 主题] [— □ ×]   │  ← 顶栏 nav
├─────────────┬────────────────────────────────────────────────┤
│             │                                                │
│  工具        │   （空状态 或 插件设置）                          │
│             │                                                │
│  ─────────  │   eyebrow: 插件                                │
│             │                                                │
│  ○ 示例插件  │   ┌─────────────────────────────────────┐      │
│    （选中）  │   │ 快捷键                               │      │
│             │   │  [ ⌥ + ⇧ + T          ]  Recorder    │      │
│             │   └─────────────────────────────────────┘      │
│             │   ┌─────────────────────────────────────┐      │
│             │   │  演示                               │      │
│             │   │  [ 触发一次 Toast ]                  │      │
│             │   └─────────────────────────────────────┘      │
│             │                                                │
│  220pt      │   shell 内容区，卡片分区 shadow-apple           │
└─────────────┴────────────────────────────────────────────────┘
```

### 空状态（零插件）

- 居中：
  - slogan：`I don't need much`（`ink-faint`，14pt italic，**仅此处出现一次**）
  - 标题：`还没有安装工具`（`ink`，20pt semibold）
  - 说明：`从插件中心安装需要的功能`（`ink-muted`，14pt）
  - 按钮：`打开插件中心`（`accent` 胶囊，白字）

### 插件中心（Sheet，宽 560pt）

- 顶：标题「插件中心」+ 关闭
- 列表：卡片行（图标 32pt SF Symbol + 名称 + 一行描述 + 版本）
- 已安装：显示「卸载」文字按钮（`ink-muted`）
- 未安装：「安装」`accent` 小胶囊
- MVP manifest 仅 **1 个示例插件** + 预留 2 个「即将推出」占位（灰色 disabled，无安装按钮）——可选，用于传达产品方向而不违背「零预装」

### 顶栏

- 左：系统窗口标题 **EnoughBox**（不再在工具栏重复）
- 中右：`插件中心` 文字按钮
- 右：主题循环按钮（系统 → 浅 → 深），样式见 [`设计规范.md`](设计规范.md)

### 菜单栏（可选 MVP）

- `LSUIElement = false`：保留 Dock 图标，方便开发调试
- Phase 1.1 可加「仅菜单栏模式」

---

## 3. 技术 MVP

### 平台

- macOS **14.0+**
- Swift 5.9+ / SwiftUI 为主，AppKit 用于 `NSPanel`、插件 `NSViewController` 桥接
- Xcode 15+

### 里程碑

#### Phase 0 — 文档与令牌（当前）

- [x] MVP / 架构 / 设计规范
- [x] `DesignTokens.swift` + `Theme` Environment
- [x] `plugin-registry/manifest.json` 占位

#### Phase 1 — 宿主壳（约 3–5 天）

- [x] Xcode 工程 + `EnoughBoxPluginSDK` Package
- [x] `Localizable.xcstrings`（zh-Hans + en，见 §10 / §11）
- [x] 主窗口：Sidebar + Detail + EmptyState
- [x] 主题切换（system/light/dark）
- [x] 插件中心 UI（mock 安装/卸载 + **下载/安装进度**）
- [x] `PluginRegistry` 本地 JSON（重启保留）
- [ ] `PluginLoader` 动态加载 `.plugin` bundle

#### Phase 2 — 插件中心 + 示例插件（进行中）

- [x] 安装状态 UI：下载进度 / 安装中 / 卸载中 / 失败重试
- [x] `PluginRegistry` 持久化 + `Application Support/EnoughBox/`
- [ ] manifest 拉取 + **真实** URLSession 下载 + SHA256 + 解压
- [ ] SamplePlugin：Toast + 热键 + 设置页
- [ ] 卸载流程
- [ ] KeyboardShortcuts + Defaults + KeychainAccess 接入

#### Phase 3 — 业务插件（你提供参考后）

- [ ] TranslatePlugin：划词 / OCR / API
- [ ] ScreenshotPlugin：区域截图 → 长截
- [ ] HostServices 补齐 selection / ocr / capture / floatingPanel

#### Phase 1.1 —  polish

- [ ] **语言**：设置内「跟随系统 / 简体中文 / English」
- [ ] LaunchAtLogin
- [ ] Sparkle
- [ ] FloatingPermissions 权限引导
- [ ] 菜单栏迷你入口

---

## 4. 示例插件（MVP 唯一内置产物）

> 「内置」指仓库里 **带源码**，用户仍须从插件中心 **点击安装** 才会出现在侧栏；打包 App 时 **不** 复制进 `Plugins` 目录。

| 字段 | 值 |
|------|-----|
| id | `com.enoughbox.sample` |
| 名称 | 示例 / Sample（见 manifest `nameLocalized`） |
| 图标 | `puzzlepiece.extension` |
| 设置 | 一组快捷键 + 「触发 Toast」按钮 |
| 热键默认 | 无（用户自行录制） |

用途：验证协议、加载、设置 UI、热键、卸载；给 Phase 3 插件当模板。

---

## 5. 插件中心 manifest（MVP）

路径：`plugin-registry/manifest.json`。**官方 registry 为审核制**，字段与流程见 [`插件发布.md`](插件发布.md)。

```json
{
  "version": 1,
  "hostMinVersion": "0.1.0",
  "plugins": [
    {
      "id": "com.enoughbox.sample",
      "name": "Sample",
      "nameLocalized": {
        "en": "Sample",
        "zh-Hans": "示例"
      },
      "description": "Verify install, settings, and shortcuts",
      "descriptionLocalized": {
        "en": "Verify install, settings, and shortcuts",
        "zh-Hans": "验证插件安装、设置与快捷键"
      },
      "version": "0.1.0",
      "icon": "puzzlepiece.extension",
      "downloadUrl": "PLACEHOLDER",
      "sha256": "PLACEHOLDER",
      "minHostVersion": "0.1.0",
      "minMacOS": "14.0",
      "architectures": ["arm64", "x86_64"],
      "capabilities": ["hotkey", "clipboard"]
    }
  ]
}
```

---

## 6. 设计实现清单

从 newking 映射到 SwiftUI（详见 [`设计规范.md`](设计规范.md)）：

| newking | EnoughBox |
|---------|---------|
| `:root` / `.dark` CSS 变量 | `DesignTokens.light` / `.dark` |
| `bg-page` | `Color.page` |
| `surface-chat` / 右栏 | `Color.shell` |
| `site-nav` | `TopBar` 实色 nav |
| `list-card` hover | 侧栏行 hover → `accent-soft` |
| `shadow-apple` | `View.shadowApple()` modifier |
| `rounded-2xl` (11px) | `cornerRadius(11)` |
| `prefers-reduced-motion` | `@Environment(\.accessibilityReduceMotion)` |

**禁止**：SwiftUI 默认 `.blue` accent、Material 滥用、浅色半透明顶栏在深色下发灰。

---

## 7. 配置与存储

| Key | 位置 | 说明 |
|-----|------|------|
| `appearance` | UserDefaults | system / light / dark |
| `appLanguage` | UserDefaults | system / zh-Hans / en（Phase 1.1） |
| `installedPlugins` | Application Support/…/registry.json | 已装 id + 版本 |
| `plugin.<id>.*` | Defaults 命名空间 | 各插件设置 |
| API 密钥 | Keychain `enoughbox.plugin.<id>` | Phase 3 |

插件目录：

```
~/Library/Application Support/EnoughBox/
├── Plugins/*.plugin
├── registry.json
└── Cache/          # 下载缓存
```

---

## 8. 风险与决策

| 项 | 决策 |
|----|------|
| 插件动态加载 Swift 类型 | `@objc` 协议 + 共享 SDK dylib；MVP 不支持纯静态 SPM 插件 |
| 签名校验 | Release 强制；Debug 可 `--skip-plugin-verify` |
| 插件 UI | MVP 用 `NSHostingController` 包 SwiftUI；与 KeyboardShortcuts.Recorder 混排 |
| manifest 托管 | 先用 GitHub Releases；官方条目 **PR + CI 构建**（见 [插件发布.md](插件发布.md)） |

---

## 9. 下一步（实施顺序）

1. 初始化 Xcode 工程 + `Packages/EnoughBoxPluginSDK`
2. 实现 `DesignTokens` + 主窗口三栏布局 + 主题
3. 实现空状态 + 插件中心 UI（mock 数据）
4. 实现 PluginLoader + SamplePlugin + 真安装流
5. MVP 验收 → 再接入翻译/截图参考项目

---

## 10. 文案定稿（String Catalog）

> 代码中 **只使用 key**（`Text("empty.title")` / `String(localized: "empty.title")`），禁止硬编码。  
> 文件：`EnoughBox/Resources/Localizable.xcstrings`  
> MVP 语言：**en**、**zh-Hans**；Slogan 两语言均保持英文（品牌一致）。

| Key | 出现位置 | zh-Hans | en |
|-----|----------|---------|-----|
| `app.name` | 窗口标题栏 | EnoughBox | EnoughBox |
| `app.slogan` | 空状态 | I don't need much | I don't need much |
| `empty.title` | 空状态 | 还没有安装工具 | Nothing installed yet |
| `empty.subtitle` | 空状态 | 从插件中心安装需要的功能 | Install what you need from the Plugin Store |
| `empty.action.openStore` | 空状态 | 打开插件中心 | Open Plugin Store |
| `sidebar.section.tools` | 侧栏 | 工具 | Tools |
| `topbar.pluginStore` | 插件中心 | Plugin Store |
| `pluginStore.title` | 插件中心 | Plugin Store |
| `pluginStore.install` | 安装 | Install |
| `pluginStore.uninstall` | 卸载 | Uninstall |
| `pluginStore.comingSoon` | 即将推出 | Coming soon |
| `theme.system` | 跟随系统 | System |
| `theme.light` | 浅色 | Light |
| `theme.dark` | 深色 | Dark |
| `settings.language` | 语言 | Language |
| `settings.language.system` | 跟随系统 | Follow System |
| `plugin.sample.name` | 示例 | Sample |
| `plugin.sample.demoAction` | 触发一次 Toast | Show a Toast |
| `plugin.sample.section.shortcut` | 快捷键 | Shortcut |
| `plugin.sample.section.demo` | 演示 | Demo |

（与 newking 规范一致：增删改文案先更新本表与 `.xcstrings`，再改代码。）

---

## 11. 国际化（i18n）

### 实现方式

| 项 | 决策 |
|----|------|
| 宿主文案 | Xcode **String Catalog**（`.xcstrings`），key 见 §10 |
| MVP 语言 | **en** + **zh-Hans** |
| MVP 默认行为 | **跟随 macOS 系统语言** |
| Phase 1.1 | 设置页增加 `appLanguage`，可强制 zh-Hans / en |
| Slogan | 两语言均为 `I don't need much`（不翻译） |
| 插件 UI | 各插件 bundle 内自带 `Localizable.xcstrings` |
| 插件中心列表 | manifest 的 `*Localized` 字段，按当前 locale 选文案 |

### 宿主代码约定

```swift
// SwiftUI
Text("empty.title")

// 带注释（供翻译者理解）
String(localized: "empty.title", comment: "Empty state when no plugins installed")
```

- 新增 View **必须先加 key**，再写 §10 表与 `.xcstrings`。
- 禁止在 Swift 里写「还没有安装工具」等字面量。

### 插件 SDK 约定

```swift
@objc public protocol EnoughBoxPlugin: AnyObject {
    var id: String { get }
    /// 侧栏显示名：从插件 bundle 的 Localizable 读取
    func localizedName(for locale: Locale) -> String
    // ...
}
```

插件作者维护插件 bundle 内的 `.xcstrings`；宿主侧栏、插件中心分别读 **插件 bundle** / **manifest**。

### manifest 多语言字段

| 字段 | 说明 |
|------|------|
| `name` | 回退默认（建议 en） |
| `nameLocalized` | `{ "en": "...", "zh-Hans": "..." }` |
| `descriptionLocalized` | 同上 |

宿主解析：`Locale.current` 或用户 `appLanguage` → 优先匹配 → 回退 `name` / `description` → 再回退 `en`。

### 验收（i18n）

1. 系统语言 **简体中文**：空状态、插件中心、侧栏为中文。
2. 系统语言 **English**：同上为英文。
3. Slogan 在两种系统语言下均为 `I don't need much`。
4. （Phase 1.1）App 内改 English 后，不随系统语言变回中文。

