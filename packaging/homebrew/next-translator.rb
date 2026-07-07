cask "next-translator" do
  version "1.0.3"
  sha256 "f4497afff8b0c96057965586e74bac4b45a5744e616661901a666fe444660666"

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
