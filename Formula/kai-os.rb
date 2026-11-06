cask "kai-os" do
  version "1.0.0"
  sha256 "dd06dd106ee2c5950f8c1d34465e23b73fd693b2c3226be6c4f2f457c420f1bf"

  url "https://github.com/kai-os/kai-os/releases/download/v#{version}/Kai-OS-#{version}.dmg"
  name "Kai OS"
  desc "On-device personal AI for macOS"
  homepage "https://github.com/kai-os/kai-os"

  app "Kai OS.app"

  uninstall quit: "ai.kai"

  zap trash: [
    "~/Kai OS - Knowledge Base/",
    "~/Library/Preferences/ai.kai.plist",
    "~/Library/Application Support/ai.kai",
    "~/Library/Caches/ai.kai",
    "~/Library/Containers/ai.kai",
  ]

  caveats <<~CAVEATS
    Kai OS requires:
    - macOS 15.4+ (Sequoia)
    - Apple Silicon M1 or newer
    - Accessibility permission in System Settings
    - Full Disk Access for knowledge base
  CAVEATS
end
