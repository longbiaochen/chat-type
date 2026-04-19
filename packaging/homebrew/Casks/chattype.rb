cask "chattype" do
  version "0.1.1"
  sha256 "652041b63b775b0802ab94f529bfa4c852be8f1b2b0e6b9a67fb0efdf4fda33b"

  url "https://github.com/longbiaochen/chat-type/releases/download/v#{version}/ChatType-#{version}-macos-arm64.zip"
  name "ChatType"
  desc "Push-to-talk macOS dictation for signed-in ChatGPT desktop users"
  homepage "https://github.com/longbiaochen/chat-type"

  depends_on macos: ">= :ventura"

  app "ChatType.app"
end
