cask "chattype" do
  version "0.1.0"
  sha256 "c1ffe3391403cd9fe01c8705b6ce3c874f2e115863df2136428ad04d43383447"

  url "https://github.com/longbiaochen/voice-dex/releases/download/v#{version}/ChatType-#{version}-macos-arm64.zip"
  name "ChatType"
  desc "Push-to-talk macOS dictation for signed-in ChatGPT desktop users"
  homepage "https://github.com/longbiaochen/voice-dex"

  depends_on macos: ">= :ventura"

  app "ChatType.app"
end
