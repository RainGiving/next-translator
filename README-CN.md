# Next Translator

[English](README.md)

原生 macOS 翻译应用，SwiftUI 编写，采用 macOS 26 的 Liquid Glass 设计语言。在任意应用里选中文字，按快捷键或点 PopClip 按钮，流式翻译立即出现。

Next Translator 是对 [nextai-translator](https://github.com/nextai-translator/nextai-translator)（openai-translator 的续作）的原生重写。提示词设计和核心工作流承自该项目，应用本身为全新的 SwiftUI 实现。

## 功能

- **五种内置动作**：翻译、润色、总结、分析、代码解释，另可无限添加自定义动作，配自己的提示词、图标和状态词（支持 `${text}`、`${sourceLang}`、`${targetLang}` 模板变量）
- **任意 OpenAI 兼容供应商**：OpenAI、DeepSeek、Moonshot、Groq、本地 Ollama 或自定义地址，模型列表从 `/v1/models` 实时拉取，一键切换
- **流式输出**，支持 markdown 渲染
- **全局划词翻译**：⌥⌘D 翻译任意应用中选中的文字（无障碍接口取词，剪贴板兜底）；⌥⌘T 呼出窗口
- **PopClip 集成**：选中文字点一下，翻译即刻开始
- **翻译历史**：可恢复、可单条删除
- **原生 Liquid Glass 界面**：玻璃动作胶囊带流体形变选中效果、手绘笔画动画、窗口置顶
- 菜单栏应用，开机自启，自动亮暗色

## 系统要求

- macOS 26 (Tahoe) 及以上
- 任意 OpenAI 兼容供应商的 API Key（或本地 Ollama）

## 安装

### DMG 安装

1. 从 Releases 下载 `Next-Translator-x.y.z.dmg`，打开后把 **Next Translator** 拖进 **Applications**。
2. 应用未经公证，首次启动请右键 → 打开，或执行：
   ```bash
   xattr -cr "/Applications/Next Translator.app"
   ```
3. 启动后应用驻留在菜单栏（对话气泡图标），没有 Dock 图标。
4. 点窗口左下角齿轮打开设置，填入 API Key。

### 授权

划词翻译（⌥⌘D）和 PopClip 冷启动需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能 → 勾选 Next Translator。

### PopClip 扩展

1. 安装 [PopClip](https://pilotmoon.com/popclip/)。
2. 双击 `dist/next-translator.popclipextz`（或从 `clip-extensions/popclip` 自行打包），在 PopClip 弹窗中确认安装。
3. 选中任意文字，点对话气泡按钮，翻译窗口弹出时结果已经在流式输出。

## 源码构建

需要 Xcode 26+ 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
git clone <本仓库>
cd next-translator-native
xcodegen generate
xcodebuild -project NextTranslator.xcodeproj -scheme NextTranslator -configuration Release build
```

## Homebrew

仓库和 Release 发布到 GitHub 后，可通过个人 tap 发布 `packaging/homebrew/next-translator.rb` 里的 cask：

```bash
brew tap <你的用户名>/tap
brew install --cask --no-quarantine <你的用户名>/tap/next-translator
```

完整发布步骤见 [packaging/homebrew/README.md](packaging/homebrew/README.md)。

## 致谢

- [nextai-translator](https://github.com/nextai-translator/nextai-translator) 及其前身 openai-translator，本应用的功能设计与提示词工程承自该项目。

## 许可

AGPL-3.0，继承自上游项目。
