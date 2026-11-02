cask "hubbub" do
  version "0.1.4"
  sha256 "a8f8286b474f0820c151ea9d5d34ca0932d383a3079eb71c9f05b674ab24e3a6" # from SHA256SUMS.txt of the release

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
