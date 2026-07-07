# Next Translator（原生版）— 项目指南

macOS 26 原生翻译应用，SwiftUI + Liquid Glass。菜单栏常驻（LSUIElement，无 Dock 图标），划词/PopClip/快捷键触发流式 LLM 翻译。GitHub：RainGiving/next-translator，Homebrew tap：RainGiving/homebrew-tap。

前身是 Tauri 版（~/Developer/next-translator，仓库保留但已停止演进），本原生版已完全取代它，/Applications/Next Translator.app 就是本项目的 Release 构建。提示词工程承自上游 nextai-translator（openai-translator 续作），许可 AGPL-3.0。

## 构建与运行

工程由 XcodeGen 管理。**永远不要手改 NextTranslator.xcodeproj**（gitignore 里，随时重生成），改 project.yml 后跑 `xcodegen generate`。

```bash
xcodegen generate
xcodebuild -project NextTranslator.xcodeproj -scheme NextTranslator -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Next Translator.app"
```

改动验证的惯例：构建成功后 `pkill -f "Next Translator"`，打开新构建，然后 `curl --silent -H "Expect:" -d "测试文本" --unix-socket /tmp/next-translator.sock http://next-translator` 模拟 PopClip（应立即返回 ok 并弹窗开始翻译）。

发版：`./scripts/release.sh 1.0.x`（升版本号、Release 构建、打 dmg、算 sha256、更新 cask），然后 git tag、`gh release create`、把 packaging/homebrew/next-translator.rb 拷到 ~/Developer/homebrew-tap/Casks/ 提交推送。gh CLI 已登录 RainGiving。

## 文件地图

- `App/NextTranslatorApp.swift` — @main，Window 场景 + MenuBarExtra + Settings 场景
- `App/AppState.swift` — 核心单例：查询状态、流式翻译、窗口行为、IPC/快捷键生命周期
- `Models/AppSettings.swift` + `Services/SettingsStore.swift` — 设置（JSON，~/Library/Application Support/com.nexttranslator.native/settings.json，0600 权限），首启从 Tauri 版 config.json 迁移
- `Models/ActionStore.swift` — 动作系统（actions.json），五个内置 + 无限自定义
- `Models/HistoryStore.swift` — 历史（history.json，上限 500，后台队列写盘）
- `Services/OpenAIClient.swift` — OpenAI 兼容 SSE 流式客户端 + listModels
- `Services/PromptBuilder.swift` — 内置动作的智能提示词组装（移植自 Tauri 版 translate.ts，含单词词典模式）
- `Services/IPCServer.swift` — unix socket 微型 HTTP 服务（PopClip 入口）
- `Services/SelectionReader.swift` — AX 取词 + 剪贴板兜底（全类型保存恢复）
- `Services/HotkeyManager.swift` — Carbon 全局快捷键
- `Views/TranslatorView.swift` — 主窗口（动作胶囊、编辑器、结果卡、底栏），含手绘动画组件
- `Views/SettingsView.swift`（General/Actions 两个 tab）、`ActionsSettingsView.swift`、`SymbolPicker.swift`、`KeyRecorderView.swift`、`HistoryView.swift`
- `Resources/Localizable.xcstrings` — 字符串目录（en + zh-Hans），新增用户可见字符串必须补进目录
- `scripts/draw_icon.swift` — 应用图标的绘制脚本（swift 脚本直接跑，改参数重新生成）
- `clip-extensions/popclip/` — PopClip 扩展源（打包：cp 成 .popclipext 目录再 zip 成 .popclipextz）

## 关键语义（改动前必读）

1. **内置动作的双轨提示词**：内置动作 rolePrompt/commandPrompt 等于 ActionStore.canonicalBuiltin 的出厂模板、或两者皆空时，运行时走 PromptBuilder 智能组装（语言感知、单词自动切词典模式）；用户改过模板则按模板字面执行（变量 ${text}/${sourceLang}/${targetLang}）。加载时会把空提示词的内置动作自动填成出厂模板。
2. **翻译竞态防护**：AppState.translationGeneration 代数计数器。任何让当前翻译作废的路径（新查询、restore、stop、early return 前的 cancel）必须走 invalidateTranslation()。流回调、完成、报错、收尾全部先校验代数。
3. **IPC 契约**：socket /tmp/next-translator.sock，先回 ok 再做窗口工作（PopClip 的转圈体验取决于此）；窗口操作必须 run_on_main… 这里是原生版，直接在 MainActor 回调里做。PopClip 脚本 curl 带 `-H "Expect:"`（不带会多 1 秒）。
4. **本地端点豁免**：API key 为空但 host 是 127.0.0.1/localhost/*.local 时放行（Ollama），Authorization 头相应省略。
5. **窗口行为**：跟随鼠标所在屏幕、collectionBehavior 加 moveToActiveSpace、失焦隐藏受 settings.hideOnFocusLoss 和置顶状态控制、置顶持久化在 settings.pinned。
6. **defaultMode 语义**：内置动作存 builtinMode 字符串，自定义动作存 UUID 字符串。
7. **图标**：必须满幅画布（macOS 26 给留白图标垫灰底板），系统自己裁squircle。菜单栏图标是 SF Symbol character.bubble，PopClip 图标是它的单色渲染，应用图标由 scripts/draw_icon.swift 生成（当前：深石板靛蓝底 + 白「文」气泡 + 琥珀「A」气泡，曲线尾巴）。

## 协作惯例（用户偏好）

- 中文交流，直接正向表达。用户在意 token 消耗：机械、样板、大批量的代码活外包给 codex CLI（`~/.claude/bin/codex-task.sh -w -C <dir> "自包含 prompt"`，冷启动无上下文，要写明文件路径、接口签名、验证命令、禁改清单）；架构决策、SwiftUI 细节、动画品味自己做。用户最近一次要求"不要再用 codex"时则全部自己做，以当次指示为准。
- UI 标准很高：真 Liquid Glass（.glassEffect/.glassProminent/GlassEffectContainer）、弹簧动画、手绘线条动画（TranslatorView 里的 WritingIndicator/DrawnCheckmark 是范例）、状态词随动作变化、按钮定宽防跳动。改 UI 先想动效和对齐。
- 每个阶段独立 git 提交（信息用英文，Co-Authored-By: Claude Fable 5 尾注），验证通过才提交。用户确认后才发 Release。

## 未完成清单

TTS 朗读、OCR 截图翻译、Writing 模式（译文键入原输入框）、生词本、Quick Translator、Icon Composer 分层图标、CI 和单元测试、API key 迁移 Keychain、开发者签名与公证（现为 ad-hoc，每次升级需重授辅助功能权限）。
