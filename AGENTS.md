# EnoughBox — Agent 约定

## 项目是什么

macOS 轻量工具箱 + 内置工具中心。Slogan：**I don't need much.** MVP 方案见 `docs/MVP.md`，架构见 `docs/架构.md`，UI 见 `docs/设计规范.md`（对齐 newking 深灰极简令牌）。

## 分派

- **改 UI / 设计** → 先读 `docs/设计规范.md`，令牌只改 `DesignTokens.swift`（工程就绪后）。
- **改文案 / 多语言** → 先读 `docs/MVP.md` §10–§11；只改 key 与 `Localizable.xcstrings`，禁止 Swift 硬编码。
- **改内置工具 / 工具中心** → 先读 `docs/架构.md`（工具代码随宿主编译；用户只管理启用状态）。
- **改工具目录 / 工具启用状态** → 先读 `docs/架构.md` 和 `docs/MVP.md`。
- **改范围 / 里程碑** → 先读 `docs/MVP.md`，重大 scope 变更先与用户确认。

## 守则

- 轻量工具直接写在宿主的 `Features/` 中；不要为轻量功能新增动态插件。
- 不引入 Electron；优先 Swift 原生 + 已选 SPM 依赖。
- 禁止彩色 UI 强调；只用设计令牌灰阶。
- 用户可见文案走 String Catalog key（zh-Hans + en），见 `docs/MVP.md` §10。
- 禁止主动 git commit / push，除非用户明确要求。

## 技术方案守则（对齐 newking，禁止堆补丁）

- 遇问题先判断**根因**，再决定修法；同一处已修超过 2 次仍未解决，停下重新审视整体方案，**先向用户说明**再改。
- **SPM 依赖（如 KeyboardShortcuts）只用其 public API**；禁止调用 `internal` 扩展（如 `NSEvent.modifiers`）。动手前查源码或文档确认可见性；拿不准时**直接问用户**或请用户在 Xcode 里验证编译。
- 优先用依赖库的现成能力；库不提供的（如无效快捷键回调）再自研，并在代码注释写明「库无此能力，自研原因」——禁止 swizzle、私有通知名等脆弱 hack，除非用户明确同意。
- 改完须在 Xcode **Build 通过**后再交付；本地无法用 `xcodebuild` 时，应请用户帮忙编译确认，而不是假设能过。
- 重大方向性 / 架构性修复（换录制方案、换全局热键库等），先说明「根因 + 方案 + 推荐」，征得同意后再动手。
