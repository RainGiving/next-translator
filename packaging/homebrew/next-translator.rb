cask "next-translator" do
  version "1.0.2"
  sha256 "43096d3f9491eea1d228c652b2961af99e9f90e5e9ce3b04f47ce833e366d6bb"

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
