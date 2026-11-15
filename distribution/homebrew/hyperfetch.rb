cask "hyperfetch" do
  version "1.1.1"
  sha256 "ad96a7131a8ce4b6409dc7ca163bb7d991fdab377038fd2631b0e1788d180a72"

  url "https://github.com/consultanything-tech/hyperfetch-app/releases/download/v#{version}/HyperFetch.dmg",
      verified: "github.com/consultanything-tech/hyperfetch-app/"
  name "HyperFetch"
  desc "Lightweight, high-speed native download manager"
  homepage "https://consultanything-tech.github.io/hyperfetch-app/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "HyperFetch.app"

  zap trash: [
    "~/Library/Application Support/HyperFetch",
    "~/Library/Caches/com.hyperfetch.app",
    "~/Library/Preferences/com.hyperfetch.app.plist",
    "~/Library/Saved Application State/com.hyperfetch.app.savedState",
  ]
end
