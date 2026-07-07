# Next Translator（原生版）— 项目指南

macOS 26 原生翻译应用，SwiftUI + Liquid Glass。菜单栏常驻（LSUIElement，无 Dock 图标），划词/PopClip/快捷键触发流式 LLM 翻译。GitHub：RainGiving/next-translator，Homebrew tap：RainGiving/homebrew-tap。许可 AGPL-3.0，提示词工程承自上游 nextai-translator。

## 会话开始：环境预检与开场提问

下面的路径和假设都是「默认值」。开工前先逐项检查，**对不上的不要猜，把问题集中列出来一次性询问作者**，得到答复后再动手。

| 检查项 | 默认假设 | 检查方式 | 对不上时问什么 |
|---|---|---|---|
| Xcode + XcodeGen | Xcode 26+、xcodegen 已装 | `xcodebuild -version`、`xcodegen version` | 提示安装命令，问是否现在装 |
| codex 外包 | 封装脚本在 `~/.claude/bin/codex-task.sh` | `ls` 该路径 | 脚本存在→问「本次会话是否启用 codex 外包机械任务」；不存在→告知不可用，全部自己做 |
| GitHub 推送 | gh CLI 已登录 RainGiving | `gh auth status` | 未登录→问是否需要推送/发版，需要则引导 `gh auth login --web` |
| tap 仓库 | `~/Developer/homebrew-tap` | `ls` 该路径 | 不存在→问路径，或本次是否跳过 tap 更新 |
| Tauri 旧版参考 | `~/Developer/next-translator`（只读，已停止演进） | `ls` 该路径 | 不存在不影响开发，涉及移植参考时再问 |
| 安装验证 | 构建后替换 `/Applications/Next Translator.app` 并重启验证 | — | 会话内首次替换前问一次「是否允许本会话自动替换安装」，之后沿用 |
| 推送与发版 | 提交常规改动后直接 push；创建 Release、更新 tap、改写历史、强推需作者明确指示 | — | 拿不准就问 |

另外两个惯例：改动落盘前如果发现工作区有非本次会话产生的未知修改，先报告再继续；用户可见的字符串新增后必须同步补 `Resources/Localizable.xcstrings`（en 为 key，zh-Hans 必填）。

## 构建与运行

工程由 XcodeGen 管理。**永远不要手改 NextTranslator.xcodeproj**（在 gitignore 里，随时重生成），改 project.yml 后跑 `xcodegen generate`。

```bash
xcodegen generate
xcodebuild -project NextTranslator.xcodeproj -scheme NextTranslator -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Next Translator.app"
```

改动验证惯例：构建成功 → `pkill -f "Next Translator"` → 打开新构建 → `curl --silent -H "Expect:" -d "测试文本" --unix-socket /tmp/next-translator.sock http://next-translator` 模拟 PopClip，应立即返回 ok 并弹窗开始翻译。

发版：`./scripts/release.sh 1.0.x`（升版本号、Release 构建、打 dmg、算 sha256、更新 cask），脚本末尾会打印后续手动步骤（commit、tag、`gh release create`、拷 cask 到 tap 仓库推送）。

## 文件地图

- `App/NextTranslatorApp.swift` — @main：Window 场景 + MenuBarExtra（自绘 A 气泡模板图标）+ Settings 场景
- `App/AppState.swift` — 核心单例：查询状态、流式翻译、窗口行为、IPC/快捷键生命周期
- `Models/AppSettings.swift` + `Services/SettingsStore.swift` — 设置（`~/Library/Application Support/com.nexttranslator.native/settings.json`，0600），首启从 Tauri 版 config.json 迁移
- `Models/ActionStore.swift` — 动作系统（actions.json），五个内置 + 无限自定义
- `Models/HistoryStore.swift` — 历史（history.json，上限 500，后台队列写盘）
- `Services/OpenAIClient.swift` — OpenAI 兼容 SSE 流式客户端 + listModels
- `Services/PromptBuilder.swift` — 内置动作的智能提示词组装（含单词词典模式）
- `Services/IPCServer.swift` — unix socket 微型 HTTP 服务（PopClip 入口）
- `Services/SelectionReader.swift` — AX 取词 + 剪贴板兜底（全类型保存恢复）
- `Services/HotkeyManager.swift` — Carbon 全局快捷键
- `Views/TranslatorView.swift` — 主窗口（动作胶囊、编辑器、结果卡、底栏），含 WritingIndicator/DrawnCheckmark 手绘动画组件
- `Views/SettingsView.swift`（General/Actions 两 tab）、`ActionsSettingsView.swift`、`SymbolPicker.swift`、`KeyRecorderView.swift`、`HistoryView.swift`
- `Resources/Localizable.xcstrings` — 字符串目录（en + zh-Hans）
- `Resources/MenuBarIcon.png` — 菜单栏模板图标（A 气泡，脚本 `scripts/draw_menubar_icon.swift`）
- `scripts/draw_icon.swift` — 应用图标绘制脚本（改参数重跑生成 icns 源图）
- `clip-extensions/popclip/` — PopClip 扩展源（打包：拷成 .popclipext 目录再 zip 成 .popclipextz）

## 关键语义（改动前必读）

1. **内置动作的双轨提示词**：内置动作 rolePrompt/commandPrompt 等于 ActionStore.canonicalBuiltin 的出厂模板、或两者皆空时，运行时走 PromptBuilder 智能组装（语言感知、单词自动切词典模式）；用户改过模板则按模板字面执行（变量 `${text}`/`${sourceLang}`/`${targetLang}`）。加载时会把空提示词的内置动作自动填成出厂模板。
2. **翻译竞态防护**：AppState.translationGeneration 代数计数器。任何让当前翻译作废的路径（新查询、restore、stop、early return 前的 cancel）必须走 invalidateTranslation()；流回调、完成、报错、收尾全部先校验代数。
3. **IPC 契约**：socket `/tmp/next-translator.sock`，先回 ok 再做窗口工作（PopClip 转圈体验取决于此）。PopClip 脚本的 curl 必须带 `-H "Expect:"`（否则长文本多等 1 秒）。
4. **本地端点豁免**：API key 为空但 host 是 127.0.0.1/localhost/*.local 时放行（Ollama），Authorization 头相应省略。
5. **窗口行为**：跟随鼠标所在屏幕、collectionBehavior 含 moveToActiveSpace、失焦隐藏受 settings.hideOnFocusLoss 与置顶状态控制、置顶持久化在 settings.pinned。
6. **defaultMode 语义**：内置动作存 builtinMode 字符串，自定义动作存 UUID 字符串。
7. **图标三套，各有讲究**：应用图标必须满幅画布（macOS 26 给留白图标垫灰底板，系统自己裁 squircle）；菜单栏用自绘 A 气泡模板 PNG（系统符号 character.bubble 在中文环境渲染成「字」，所以不能用）；PopClip 图标与菜单栏同图。

## 协作惯例（作者偏好）

- 中文交流，直接正向表达，在意 token 消耗。机械、样板、大批量代码活在作者同意后外包 codex（prompt 必须自包含：文件路径、接口签名、验证命令、禁改清单）；架构、SwiftUI 细节、动画品味、所有要写的文字内容自己做。
- UI 标准很高：真 Liquid Glass（.glassEffect/.glassProminent/GlassEffectContainer）、弹簧动画、手绘线条动画、状态词随动作变化、按钮定宽防跳动。改 UI 先想动效和对齐。
- 每个阶段独立 git 提交（信息英文，尾注 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`），验证通过才提交。提交身份用仓库本地 git config（noreply 邮箱保证 GitHub 归属）。

## 未完成清单

TTS 朗读、OCR 截图翻译、Writing 模式（译文键入原输入框）、生词本、Quick Translator、Icon Composer 分层图标、CI 和单元测试、API key 迁移 Keychain、开发者签名与公证（现为 ad-hoc，每次升级需重授辅助功能权限）。
