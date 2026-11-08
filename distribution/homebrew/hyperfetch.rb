cask "hyperfetch" do
  version "1.1.0"
  sha256 "82aa8fb770a264fe920946f1fd4113f6e8b2968ae6b684c8ff036e363b8f0842"

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
