cask "openelsewhere" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_build-dmg.sh"

  url "https://github.com/LubosBury/OpenElsewhere/releases/download/v#{version}/OpenElsewhere-#{version}.dmg"
  name "OpenElsewhere"
  desc "Route links from specific macOS apps to the browser you actually want"
  homepage "https://github.com/LubosBury/OpenElsewhere"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "OpenElsewhere.app"

  zap trash: [
    "~/Library/Preferences/com.openelsewhere.app.plist",
    "~/Library/Saved Application State/com.openelsewhere.app.savedState",
  ]

  caveats <<~EOS
    On first use of a rule that targets Arc or Dia, macOS will ask permission
    to control that app via Apple Events. Click OK to allow.
  EOS
end
