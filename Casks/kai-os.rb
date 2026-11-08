# Homebrew cask for Kai OS. It needs a tap repository (named homebrew-kai-os) that contains this file:
#   brew install --cask jgonzalez007/kai-os/kai-os
# Kai OS is ad-hoc signed and not notarized, so the postflight step clears the download quarantine
# flag on this one app, the same thing scripts/install.sh does.
cask "kai-os" do
  version "1.1.0"
  # The checksum changes with every build. scripts/package-release.sh prints it, and the release
  # also carries Kai-OS.zip.sha256. Put it here when you publish the tap.
  sha256 :no_check

  url "https://github.com/jgonzalez007/Kai-os/releases/download/v#{version}/Kai-OS.zip"
  name "Kai OS"
  desc "Personal AI in the Mac's notch, local first"
  homepage "https://github.com/jgonzalez007/Kai-os"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Kai OS.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Kai OS.app"]
  end

  uninstall quit: "ai.kai"

  zap trash: [
    "~/Library/Application Support/Kai OS",
    "~/Library/Preferences/ai.kai.plist",
    "~/Library/Caches/ai.kai",
  ]

  caveats <<~CAVEATS
    Kai OS asks for permissions on first launch (Calendar, Mail, Notes, Microphone,
    Accessibility, Screen Recording). All are optional.
    For local chat, install Ollama (https://ollama.com/download). The first-run guide helps.
    Your knowledge base in ~/Kai OS - Knowledge Base is not removed on uninstall.
  CAVEATS
end
