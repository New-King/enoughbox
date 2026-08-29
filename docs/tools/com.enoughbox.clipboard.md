# `com.enoughbox.clipboard` 内置剪贴板工具

## 基本信息

- 源码：`EnoughBox/Features/Clipboard/`
- 快捷键：`com.enoughbox.clipboard.panel`
- 权限：读取系统剪贴板；自动粘贴需要辅助功能
- 历史存储：`~/Library/Application Support/EnoughBox/clipboard/`

快捷键呼出浮窗，支持搜索、分类（最近 / 全部 / 文本 / 图片 / 其他）、列表选用与删除。点击条目会粘贴到打开浮窗前的应用，浮窗保持打开；再次按快捷键或 `Esc` / `⌘W` / `⌘Q` 关闭。自动粘贴需要辅助功能权限。

浮窗跟随宿主外观设置，与翻译浮窗相同：打开时读取当前主题，关掉再开才会更新。使用 `DesignTokens` 与 `appleShadow`；关闭时清空搜索状态并释放缩略图缓存。大文本（>4KB）与图片落盘，列表只加载可见缩略图。

默认保留最近 50 条历史。「最近」显示在浮窗里操作过的 20 条；「全部」按复制时间排序，最新在前。

## 验证

1. 工具中心启用「剪贴板」，设置页录制快捷键。
2. `Cmd+B` / `Cmd+R`。
3. 复制几段文本与一张图片，按快捷键打开浮窗。
4. 切换分类与搜索，点击条目应粘贴到原应用。
5. 删除条目后不再出现；再次按快捷键可关闭浮窗。
6. 工具「移除」后热键失效、监听停止。

## 参考

- 监听与图片落盘思路参考 [vorssaint-utils](https://github.com/vorssaintapp/vorssaint-utils) `ClipboardHistoryService`
- 浮窗交互对齐 EnoughBox 翻译工具，但点外不关闭
