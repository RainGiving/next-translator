cask "next-translator" do
  version "1.0.1"
  sha256 "b960e4d79ce205fb1ef0aca667742c953b3e09ff86666dfc64dd5b7f327852b3"

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
