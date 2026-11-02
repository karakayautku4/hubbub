cask "hubbub" do
  version "0.1.2"
  sha256 "3029e6a78c51dec7724ed402cc41bfb548d5bafa1f29228ce24c76ed2889384e" # from SHA256SUMS.txt of the release

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
