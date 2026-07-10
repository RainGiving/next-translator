cask "next-translator" do
  version "1.0.5"
  sha256 "0c58f8d7cad7f8040905754c4313d9946ef28d0323e50eb5aeb103b4c4132d3c"

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
