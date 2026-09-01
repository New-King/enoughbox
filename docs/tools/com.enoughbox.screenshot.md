# `com.enoughbox.screenshot` 内置截图工具

## 基本信息

- 源码：`EnoughBox/Features/Screenshot/`
- 采集：宿主 `ScreenCapture`（ScreenCaptureKit 冻结当前各屏，再裁切）
- 快捷键：`com.enoughbox.screenshot.region`
- 权限：屏幕录制（`CGRequestScreenCaptureAccess`）

当前支持区域截图与长截图：框选、八向缩放、钉图、保存、取消、复制和 OCR。长截图：框选后点工具条「长截图」，滚动页面，点「完成」后复制拼接图到剪贴板。位移使用 Vision 图像配准（ScrollSnap MIT）。OCR 使用 macOS Vision 本地识别；不做马赛克、录屏。

交互参考 ShotX 的选区+锚点+工具条；采集与裁切坐标参考 Aurora（MIT）的冻结帧 / `CropGeometry` 思路，实现为 EnoughBox 本地代码。

## 验证

1. 工具中心启用「截图」，设置页录制快捷键。
2. `Cmd+B` / `Cmd+R`。
3. 首次应出现屏幕录制权限。
4. 快捷键后拖选区域，调大小，勾选复制；再试用 OCR、钉图、保存、Esc。复制后屏幕中央应出现「已复制到剪贴板」。
5. 未框选时移动指针看色值，按 `/` 应复制颜色并退出。
6. **长截图**：框选后点「长截图」→ 不应把 EnoughBox 主窗口带到前台 → 选区外暗罩、选区与预览原亮度 → 滚动 → 顶栏图标：取消 / 保存 / 完成（回车完成）→ 复制后中央提示「已复制到剪贴板」。

## 代码借鉴
- https://github.com/Brkgng/ScrollSnap
- https://github.com/SunnyCapturer/ShotX
- https://github.com/KiZmzz/Aurora
