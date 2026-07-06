# 发布到 Homebrew（个人 tap）

未经公证的个人应用进不了官方 homebrew-cask，走个人 tap，用户照样一条命令安装。

## 一次性准备

1. 在 GitHub 建两个仓库：
   - `next-translator`：本项目代码仓库
   - `homebrew-tap`：tap 仓库（名字必须以 `homebrew-` 开头）
2. 推送本项目：
   ```bash
   cd ~/Developer/next-translator-native
   git remote add origin git@github.com:你的用户名/next-translator.git
   git push -u origin main
   ```

## 每次发版

1. 打 tag 并创建 GitHub Release，上传 dmg：
   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   gh release create v1.0.0 dist/Next-Translator-1.0.0.dmg --title "v1.0.0"
   ```
2. 计算 dmg 的 sha256（本版本已算好，见 cask 文件）：
   ```bash
   shasum -a 256 dist/Next-Translator-1.0.0.dmg
   ```
3. 把 `next-translator.rb` 里的 `YOUR_GITHUB_USERNAME` 换成你的用户名，`version`/`sha256` 更新为本次值，提交到 tap 仓库：
   ```bash
   mkdir -p ~/Developer/homebrew-tap/Casks
   cp packaging/homebrew/next-translator.rb ~/Developer/homebrew-tap/Casks/
   cd ~/Developer/homebrew-tap && git add -A && git commit -m "next-translator 1.0.0" && git push
   ```

## 用户安装

```bash
brew tap 你的用户名/tap
brew install --cask --no-quarantine 你的用户名/tap/next-translator
```

`--no-quarantine` 让 brew 跳过隔离属性，未公证的应用可直接启动。以后升级：`brew upgrade --cask next-translator`。

## 想去掉 --no-quarantine

需要 Apple Developer 付费账号（99 美元/年）做签名和公证：Developer ID 证书签名 + `xcrun notarytool` 公证 + `stapler` 装订，之后普通 `brew install --cask` 即可。
