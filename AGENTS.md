# EnoughBox — Agent 约定

## 项目是什么

macOS 空壳工具箱宿主 + 插件中心。Slogan：**I don't need much.** MVP 方案见 `docs/MVP.md`，架构见 `docs/架构.md`，UI 见 `docs/设计规范.md`（对齐 newking 深灰极简令牌）。

## 分派

- **改 UI / 设计** → 先读 `docs/设计规范.md`，令牌只改 `DesignTokens.swift`（工程就绪后）。
- **改文案 / 多语言** → 先读 `docs/MVP.md` §10–§11；只改 key 与 `Localizable.xcstrings`，禁止 Swift 硬编码。
- **改插件协议 / 加载** → 先读 `docs/架构.md`。
- **改官方插件收录 / manifest** → 先读 `docs/插件发布.md`（curated 审核，非随意上传）。
- **改范围 / 里程碑** → 先读 `docs/MVP.md`，重大 scope 变更先与用户确认。

## 守则

- 宿主不写翻译、截图等业务逻辑；能力进插件或 `HostServices`。
- 不引入 Electron；优先 Swift 原生 + 已选 SPM 依赖。
- 禁止彩色 UI 强调；只用设计令牌灰阶。
- 用户可见文案走 String Catalog key（zh-Hans + en），见 `docs/MVP.md` §10。
- 禁止主动 git commit / push，除非用户明确要求。
