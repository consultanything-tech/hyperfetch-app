cask "hyperfetch" do
  version "1.1.3"
  sha256 "d2d8be2ab0d7faf03000e1bc9d651a2bacca6fd47bb2438faba3ac6b81276fbe"

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
