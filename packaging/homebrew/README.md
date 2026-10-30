# Homebrew tap

`Casks/hubbub.rb` is a template for a tap repository named `homebrew-hubbub`.

## Publish the tap (done: github.com/karakayautku4/homebrew-hubbub)

1. Create the GitHub repo `<owner>/homebrew-hubbub` and copy `Casks/hubbub.rb` into its `Casks/` folder.
2. Replace `karakayautku4/hubbub` in the cask with the real `<owner>/<repo>`.
3. Per release: `scripts/release.sh` updates `version`/`sha256` in this cask (the release workflow also attaches `cask-snippet.txt`). Copy it into the tap and push.
4. Users install with `brew tap <owner>/hubbub && brew install --cask hubbub`.

Test locally with `brew install --cask ./Casks/hubbub.rb`.
