import Foundation

/// 用户可见文案。
enum UIStrings {
  enum App {
    static let slogan = "I don't need much"
  }

  enum Shell {
    static let toolsSection = "工具"
    static let noToolsEnabled = "尚未启用工具"
    static let emptyTitle = "还没有启用工具"
    static let emptySubtitle = "启用你需要的工具"
    static let openBuiltInTools = "打开内置工具"
    static let builtInTools = "内置工具"
    static let appearance = "外观"
  }

  enum Theme {
    static let system = "跟随系统"
    static let light = "浅色"
    static let dark = "深色"
  }

  enum ToolStore {
    static let title = "内置工具"
    static let install = "启用"
    static let uninstall = "移除"
  }

  enum Tool {
    static let translateName = "翻译"
    static let translateDescription = "在任意 App 里划词翻译"
    static let screenshotName = "截图"
    static let screenshotDescription = "区域截图、长截图、钉图与取色"
    static let clipboardName = "剪贴板"
    static let clipboardDescription = "浏览剪贴板历史，搜索并粘贴"
    static let missingBundle = "工具不可用，请从内置工具中重新启用。"
    static let reinstallHint = "在工具中心启用或移除内置工具。"
    static let reinstall = "打开内置工具"
    static let translateShortcutFooter =
      "优先翻译选中文字；没有划词则翻译剪贴板。只有划词需要辅助功能权限。"
    static let screenshotShortcutFooter =
      "悬停吸附窗口、单击选中；拖动可自定义区域。C 复制颜色并结束；/ 切换 HEX、RGB、HSL。"
    static let clipboardShortcutFooter =
      "再次按下快捷键可关闭浮窗。点击条目会粘贴到打开浮窗前的应用；自动粘贴需要辅助功能权限。"
  }

  enum Shortcut {
    static let section = "快捷键"
    static let placeholder = "全局快捷键"
    static let press = "按下快捷键"
    static let set = "设置快捷键"
    static let savedFormat = "快捷键已设为 %@"
    static let conflictDuplicate = "此快捷键已被 EnoughBox 的其他功能使用"
    static let conflictSystem = "此快捷键已被 macOS 使用"
    static let conflictMenuFormat = "此快捷键已被菜单“%@”使用"
  }

  enum Screenshot {
    static let settingsSection = "屏幕录制"
    static let permissionHint = "截图功能需要此权限，若无效果请在录屏设置中移除 EnoughBox.app 后重新添加。"
    static let openScreenRecording = "打开屏幕录制设置"
    static let pin = "钉在桌面"
    static let save = "保存"
    static let cancel = "取消"
    static let confirm = "复制到剪贴板"
    static let ocr = "识别文字"
    static let ocrCopied = "文字已复制到剪贴板"
    static let ocrNoText = "未识别到文字"
    static let ocrFailed = "文字识别失败"
    static let ocrProcessing = "正在识别文字…"
    static let ocrResultTitle = "识别结果"
    static let ocrCopy = "复制"
    static let ocrClose = "关闭"
    static let colorHints = "C 复制 · / 切换"
    static let toastCopied = "已复制到剪贴板"
    static let toastColorCopied = "已复制颜色信息"
    static let toastFailed = "无法截取屏幕"
    static let toastSavedFormat = "已保存 %@"
    static let scrolling = "长截图"
    static let scrollingProgress = "使用鼠标或触控板滚动。按下回车键完成。"
    static let scrollingDone = "完成"
    static let scrollingPreview = "长截图预览"
    static let scrollingPartial = "页面有变化，已保留已完成的部分"
    static let scrollingLimited = "已达到安全上限，已停止捕获"
  }

  enum Translate {
    static let action = "翻译"
    static let sourceAuto = "自动检测"
    static let swap = "切换目标语言（中/英）"
    static let cycleEngine = "切换下一个翻译平台"
    static let resultEmpty = "译文会显示在这里"
    static let pin = "钉住窗口"
    static let unpin = "取消钉住"
    static let toastCopied = "已复制到剪贴板"
    static let noSelection = "没有选中文字，剪贴板里也没有文本"
    static let settingsSection = "翻译"
    static let targetLanguage = "目标语言"
    static let engine = "引擎"
    static let credentials = "密钥"
    static let appID = "应用 ID"
    static let appSecret = "应用密钥"
    static let apiKey = "API Key"
    static let model = "模型 ID"
    static let baseURL = "接口 URL"
    static let accessibility = "辅助功能"
    static let accessibilityHint = "翻译功能需要此权限，若无效果请在辅助功能中移除 EnoughBox.app 后重新添加。"
    static let openAccessibility = "打开辅助功能设置"
    static let footer = "优先翻译划词；没有选中则用剪贴板。"
    static let systemHint = "使用 macOS 15 及以上的系统翻译。首次使用时系统可能会下载语言包。优先划词，没有选中则用剪贴板。"
    static let youdaoHint = "使用有道文本翻译（NMT）。应用 ID 和应用密钥必填；若控制台把应用 ID 标成 API Key，填其中一个即可。"
    static let deepseekHint = "请填写完整接口 URL，例如 https://api.deepseek.com/chat/completions。默认模型为 deepseek-v4-flash。"
    static let apply = "申请"
    static let engineYoudao = "有道翻译"
    static let engineDeepSeek = "DeepSeek"
    static let engineSystem = "系统翻译"
    static let languageZhHans = "中文"
    static let languageEn = "英语"
    static let languageAuto = "自动检测"
    static let errorEmpty = "请输入要翻译的文本"
    static let errorMissingYoudao = "请先在工具设置里填写有道应用 ID 和应用密钥"
    static let errorMissingDeepSeek = "请先在工具设置里填写 DeepSeek API Key"
    static let errorInvalidURL = "接口 URL 无效"
    static let errorNetwork = "网络请求失败"
    static let errorTimeout = "翻译超时"
    static let errorCancelled = "已取消翻译"
    static let errorSystemUnavailable = "系统翻译需要 macOS 15 或更高版本"
    static let errorSystemFailed = "翻译失败"
    static let errorHTTPFormat = "HTTP %d"
    static let errorYoudaoSign = "有道签名失败，请检查应用 ID 和应用密钥"
    static let errorYoudaoQuota = "有道额度不足或请求过于频繁"
    static let errorYoudaoCodeFormat = "有道错误 %@"
  }

  enum Clipboard {
    static let settingsSection = "剪贴板"
    static let historyLimit = "历史条数上限"
    static let historyLimitFormat = "%d 条"
    static let settingsHint = "最近显示最近操作过的 20 条。全部按复制时间排序，最新在前。"
    static let searchPlaceholder = "按 / 搜索"
    static let categoryRecent = "最近"
    static let categoryAll = "全部"
    static let categoryText = "文本"
    static let categoryImage = "图片"
    static let categoryOther = "其他"
    static let empty = "还没有剪贴板历史"
    static let delete = "删除"
    static let copy = "复制"
    static let pin = "钉住窗口"
    static let unpin = "取消钉住"
    static let close = "关闭"
    static let clearAll = "清空"
    static let toastCopied = "已复制到剪贴板"
    static let imageEntry = "图片"
    static let otherEntry = "其他内容"
  }
}
