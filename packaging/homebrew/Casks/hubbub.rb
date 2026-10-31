cask "hubbub" do
  version "0.1.1"
  sha256 "61d7cf6044e6d5fcba92e4ed70b9d257aaa62d2ddc2eac4f8a0354fd1471e20a" # from SHA256SUMS.txt of the release

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
