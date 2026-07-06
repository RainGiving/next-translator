# Next Translator

[中文说明](README-CN.md)

A native macOS translation app built with SwiftUI and the macOS 26 Liquid Glass design language. Select text anywhere, hit a hotkey or a PopClip button, and a streaming LLM translation appears instantly.

Next Translator is a native rewrite inspired by [nextai-translator](https://github.com/nextai-translator/nextai-translator) (the continuation of openai-translator). The prompt design and core workflow come from that project; the app itself is a from-scratch SwiftUI implementation.

## Features

- **Five built-in actions**: Translate, Polish, Summarize, Analyze, Explain Code — plus unlimited custom actions with your own prompts, icons and status words (`${text}`, `${sourceLang}`, `${targetLang}` template variables)
- **Any OpenAI-compatible provider**: OpenAI, DeepSeek, Moonshot, Groq, Ollama (local) or a custom base URL; live model list fetched from `/v1/models`
- **Streaming output** with markdown rendering
- **System-wide selection translation**: ⌥⌘D translates the selection in any app (Accessibility API with clipboard fallback); ⌥⌘T shows the window
- **PopClip integration**: select text, tap once, translation starts immediately
- **Translation history** with restore, and per-item delete
- **Native Liquid Glass UI**: glass action pills with fluid morphing selection, hand-drawn stroke animations, window pinning
- Menu bar app, launch at login, automatic light/dark

## Requirements

- macOS 26 (Tahoe) or later
- An API key from any OpenAI-compatible provider (or a local Ollama)

## Install

### From DMG

1. Download `Next-Translator-x.y.z.dmg` from Releases, open it, drag **Next Translator** into **Applications**.
2. The app is not notarized. On first launch, right-click the app → Open, or run:
   ```bash
   xattr -cr "/Applications/Next Translator.app"
   ```
3. Launch it — the app lives in the menu bar (speech-bubble icon), no Dock icon.
4. Open Settings (gear button, bottom-left) and enter your API key.

### Grant permissions

For selection translation (⌥⌘D) and PopClip cold start, allow **Accessibility** when prompted: System Settings → Privacy & Security → Accessibility → enable Next Translator.

### PopClip extension

[PopClip](https://www.popclip.app) shows a small action bar whenever you select text with the mouse — the fastest way to translate.

1. **Get PopClip** (a third-party app, one-time setup):
   - Mac App Store: <https://apps.apple.com/app/popclip/id445189367>, or
   - Free download from the official site: <https://www.popclip.app>
   - Launch PopClip once and grant it Accessibility when prompted (System Settings → Privacy & Security → Accessibility → enable PopClip). Its icon appears in the menu bar.
2. **Add the Next Translator button**:
   - Download `next-translator.popclipextz` from [Releases](https://github.com/RainGiving/next-translator/releases) (or build it from `clip-extensions/popclip` in this repo)
   - Double-click the downloaded file — PopClip pops up a preview, click **Install Extension**
3. **Use it**: select any text in any app; the PopClip bar appears above the selection with a speech-bubble button. Tap it — the Next Translator window opens with the translation already streaming. If the app is not running, the button launches it in the background and retries automatically.

To disable or remove the button later: click the PopClip icon in the menu bar → the gear → Extensions.

## Build from source

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/RainGiving/next-translator.git
cd next-translator
xcodegen generate
xcodebuild -project NextTranslator.xcodeproj -scheme NextTranslator -configuration Release build
```

## Homebrew

Once the repo and a release are on GitHub, the cask in `packaging/homebrew/next-translator.rb` can be published via a personal tap:

```bash
brew tap RainGiving/tap
HOMEBREW_CASK_OPTS="--no-quarantine" brew install --cask RainGiving/tap/next-translator
```

See [packaging/homebrew/README.md](packaging/homebrew/README.md) for the step-by-step publishing guide.

## Credits

- [nextai-translator](https://github.com/nextai-translator/nextai-translator) and its predecessor openai-translator — the original cross-platform project whose features and prompt engineering this app inherits.

## License

AGPL-3.0, inherited from the upstream project.
