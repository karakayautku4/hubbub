cask "hubbub" do
  version "0.1.3"
  sha256 "689cae44110e0ddc72bb3903f9db3c86822cd3934ecf5d6ec6062d054812143e" # from SHA256SUMS.txt of the release

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
