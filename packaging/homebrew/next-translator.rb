cask "next-translator" do
  version "1.0.0"
  sha256 "f181aa16e8b5d1f99bc192a2ce27b7bbe8a29e4932b2032723024bd633412876"

  url "https://github.com/RainGiving/next-translator/releases/download/v#{version}/Next-Translator-#{version}.dmg"
  name "Next Translator"
  desc "Native macOS translation app powered by LLMs, with Liquid Glass UI"
  homepage "https://github.com/RainGiving/next-translator"

  caveats "Requires macOS 26 (Tahoe) or later."

  app "Next Translator.app"

  zap trash: [
    "~/Library/Application Support/com.nexttranslator.native",
  ]
end
