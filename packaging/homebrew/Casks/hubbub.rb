cask "hubbub" do
  version "0.1.0"
  sha256 "948d75721cf10dca4dbde5f4594af29a390182f04d118c8e1d3bddff8179e24a" # from SHA256SUMS.txt of the release

  url "https://github.com/karakayautku4/hubbub/releases/download/v#{version}/Hubbub-#{version}.dmg"
  name "Hubbub"
  desc "Menu bar app that shows your AI coding agent sessions as a tiny 3D world"
  homepage "https://github.com/karakayautku4/hubbub"

  depends_on macos: ">= :sonoma"

  app "Hubbub.app"

  zap trash: [
    "~/Library/Preferences/dev.hubbub.app.plist",
    "~/Library/Application Support/Hubbub",
    "~/.hubbub",
  ]

end
