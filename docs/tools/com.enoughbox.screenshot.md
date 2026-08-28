# `com.enoughbox.screenshot` 内置截图工具

## 基本信息

- 源码：`EnoughBox/Features/Screenshot/`
- 采集：宿主 `ScreenCapture`（ScreenCaptureKit 冻结当前各屏，再裁切）
- 快捷键：`com.enoughbox.screenshot.region`
- 权限：屏幕录制（`CGRequestScreenCaptureAccess`）

第一期只做区域截图：框选、八向缩放、马赛克、钉图、保存、取消、打勾复制。指针旁显示颜色，`/` 复制 HEX/RGB 并结束。不做长截图、录屏、OCR、窗口智能吸附。

交互参考 ShotX 的选区+锚点+工具条；采集与裁切坐标参考 Aurora（MIT）的冻结帧 / `CropGeometry` 思路，实现为 EnoughBox 本地代码。

## 验证

1. 工具中心启用「截图」，设置页录制快捷键。
2. `Cmd+B` / `Cmd+R`。
3. 首次应出现屏幕录制权限。
4. 快捷键后拖选区域，调大小，勾选复制；再试用马赛克、钉图、保存、Esc。
5. 未框选时移动指针看色值，按 `/` 应复制颜色并退出。

## 代码借鉴

- https://github.com/vorssaintapp/vorssaint-utils
- https://github.com/SunnyCapturer/ShotX
- https://github.com/KiZmzz/Aurora
