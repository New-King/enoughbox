# `com.enoughbox.translate` 翻译插件

## 基本信息

- 源码：`Plugins/TranslatePlugin/`
- 构建目标：`TranslatePlugin`
- 运行时插件：`com.enoughbox.translate.plugin`
- 运行时目录：`~/Library/Application Support/EnoughBox/Plugins/`
- 当前翻译引擎：Mock，仅用于验证界面和流程
- 快捷键：`com.enoughbox.translate.selection`

宿主负责读取选区和提供浮窗能力，翻译插件负责快捷键、翻译流程和面板 UI。不要把翻译业务逻辑写回宿主。

## 正常开发流程

1. 打开 `EnoughBox.xcodeproj`。
2. 确认左侧 `Package Dependencies` 中的 `KeyboardShortcuts` 已完成解析。
3. 用 `Cmd+B` 编译。
4. 用 `Cmd+R` 运行宿主。
5. 插件安装后，源码再次变化时，先在插件中心卸载再安装，确保 Application Support 里的 `.plugin` 是最新构建产物。
6. 在其他 App（例如备忘录、Chrome）选中文字，再按翻译快捷键验证。

插件是和宿主同进程加载的动态 bundle。宿主或 SDK 接口变化后，不能只编译宿主而继续加载旧插件；否则可能出现插件无法载入、动态符号不匹配，甚至宿主在 SwiftUI 布局时崩溃。

## 刚才这类问题的处理顺序

### 1. 先看 Xcode 是否真的在编译

- `No such module 'EnoughBoxPluginSDK'`
- `Missing package product 'EnoughBoxPluginSDK'`
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
- Application Support 里的已安装插件
- macOS 辅助功能/自动化权限

因此，源码已经回到某个提交，不代表 Xcode 或已安装插件也回到了那个版本。

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

### 4. 插件加载失败时

如果出现：

```text
Failed to load com.enoughbox.translate.plugin
```

先检查 Application Support 中的插件是不是旧副本：

```sh
ls -l "$HOME/Library/Application Support/EnoughBox/Plugins/com.enoughbox.translate.plugin"
```

最安全的修复是退出 EnoughBox，在插件中心卸载翻译插件，再重新编译并安装。不要直接删除整个 Application Support；那会同时影响插件安装记录。

如果宿主启动即崩，无法进入插件中心，才删除**明确对应的**：

```text
~/Library/Application Support/EnoughBox/Plugins/com.enoughbox.translate.plugin
```

然后把 registry 中对应的翻译插件记录移除或通过宿主重新安装。删除前先备份或至少读取 registry，不能把其他插件一起清掉。

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
- [ ] 翻译插件能加载
- [ ] 翻译浮窗内输入文字可以得到 Mock 译文
- [ ] 在外部 App 选中文字后按快捷键可以翻译
- [ ] 没有选区且剪贴板为空时显示无选区提示
- [ ] 辅助功能未授权时不会把剪贴板旧内容误当成当前选区
