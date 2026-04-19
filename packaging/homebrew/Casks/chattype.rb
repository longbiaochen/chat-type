cask "chattype" do
  version "0.1.2"
  sha256 "7c7678669b5c39ecbdbfe3498de1a5766adb52363ffec562d06a898254fc503f"

  url "https://github.com/longbiaochen/chat-type/releases/download/v#{version}/ChatType-#{version}-macos-arm64.zip"
  name "ChatType"
  desc "Push-to-talk macOS dictation for signed-in ChatGPT desktop users"
  homepage "https://github.com/longbiaochen/chat-type"

  depends_on macos: ">= :ventura"

  app "ChatType.app"
end
