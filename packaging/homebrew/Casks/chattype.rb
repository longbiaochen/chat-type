cask "chattype" do
  version "0.1.1"
  sha256 "d26e4d1090b5e4ba8aef3e844307962d1f95624774627dcd9beca613cfb38656"

  url "https://github.com/longbiaochen/chattype/releases/download/v#{version}/ChatType-#{version}-macos-arm64.zip"
  name "ChatType"
  desc "Push-to-talk macOS dictation for signed-in ChatGPT desktop users"
  homepage "https://github.com/longbiaochen/chattype"

  depends_on macos: ">= :ventura"

  app "ChatType.app"
end
