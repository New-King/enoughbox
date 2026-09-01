# `com.enoughbox.translate` 内置翻译工具

## 基本信息

- 源码：`EnoughBox/Features/Translate/`
- 运行时：`EnoughBox.app` 内置工具
- 启用状态：`~/Library/Application Support/EnoughBox/registry.json`
- 当前翻译引擎：有道 NMT / DeepSeek / 系统翻译
- 密钥：UserDefaults，与目标语言等设置相同
- 快捷键：`com.enoughbox.translate.selection`

内置翻译工具负责快捷键、翻译流程和面板 UI；选区读取由宿主服务提供。钉住状态会记住：再次按快捷键翻译新内容时不会取消钉住，已打开的浮窗也不移位。复制原文/译文时在屏幕中央提示「已复制到剪贴板」。

## 正常开发流程

1. 打开 `EnoughBox.xcodeproj`。
2. 确认左侧 `Package Dependencies` 中的 `KeyboardShortcuts` 已完成解析。
3. 用 `Cmd+B` 编译。
4. 用 `Cmd+R` 运行宿主。
5. 源码再次变化时直接 `Cmd+R`；工具代码随宿主一起更新。
6. 在其他 App（例如备忘录、Chrome）选中文字，再按翻译快捷键验证。

翻译工具是宿主内置代码，修改后随宿主一起编译。

## 刚才这类问题的处理顺序

### 1. 先看 Xcode 是否真的在编译

- `Missing package product 'KeyboardShortcuts'`

这些不是普通警告，不能忽略。

先确认仓库状态：

```sh
git status
git rev-parse HEAD
```

再确认目标文件是否被改动。不要一看到编译失败就继续改业务代码。

### 2. 区分源码回退和 Xcode 状态

`git reset` 或切换提交只会恢复仓库中的跟踪文件，不会恢复：

- `~/Library/Developer/Xcode/DerivedData/`
- 项目里的 `xcuserdata`
- Swift Package 下载缓存
- Application Support 里的工具启用状态
- macOS 辅助功能/自动化权限

因此，源码已经回到某个提交，不代表 Xcode 的缓存也已经同步。

### 3. Package 解析失败时

如果显示 `Fetching KeyboardShortcuts...`，先等几十秒；正常解析不应持续数分钟。

如果显示：

```text
The server SSL certificate failed to verify
Resolving Package Graph Failed
```

这是 Xcode 拉取 GitHub 依赖时的网络/证书问题，不是 Swift 代码问题。此时：

1. 停止当前解析，避免一直转圈。
2. 确认网络或 VPN 能访问 GitHub；VPN 的 HTTPS 代理也可能造成证书校验失败。
3. 重新打开工程，让 Xcode 使用同一份 `Package.resolved` 解析。
4. 不要为了这个问题改 `project.yml`、把 SPM 包临时改成 Framework，或随意删除整个 Xcode 安装目录。

如果需要清理，只清当前项目的 DerivedData 和项目级 `xcuserdata`，并在删除前确认路径确实属于 EnoughBox。清理后要关闭并重新打开 Xcode。

### 4. 工具状态异常时

如果侧栏状态与预期不一致，先检查 registry：

```sh
cat "$HOME/Library/Application Support/EnoughBox/registry.json"
```

在工具中心点击“移除”再“启用”即可。不要删除整个 Application Support。

### 5. 辅助功能失败时

如果没有读到选区，说明 macOS 可能没有授权当前正在运行的那份 `EnoughBox.app`，或者当前 App 不支持 AX 选区读取。辅助功能授权绑定的是具体 App 路径和签名，不是显示名称。

在系统设置 → 隐私与安全性 → 辅助功能中：

1. 找到 EnoughBox；如果当前授权无效，移除这个条目。
2. 退出 EnoughBox 后，重新打开并勾选。
3. 回到辅助功能中确认当前 EnoughBox 已出现并打开。
4. 再在其他 App 中测试，不要只在翻译浮窗自己的编辑器里测试。

更换 DerivedData 目录、Clean 后签名变化、修改 entitlements，都可能让 macOS 把它视为另一份 App。

## 验证矩阵

- [ ] Xcode 包依赖已解析，没有 `Missing package product`
- [ ] `Cmd+B` 成功
- [ ] EnoughBox 能启动
- [ ] 翻译工具能正常打开
- [ ] 翻译浮窗内输入文字可以得到译文
- [ ] 可在设置中切换有道 / DeepSeek / 系统翻译
- [ ] 有道与 DeepSeek 的密钥可在设置中保存并用于翻译
- [ ] 在外部 App 选中文字后按快捷键可以翻译
- [ ] 没有选区且剪贴板为空时显示无选区提示
- [ ] 辅助功能未授权时不会把剪贴板旧内容误当成当前选区

## 代码借鉴
- https://github.com/pot-app/pot-desktop
