# ChatType

[English README](README.md)

`ChatType` 是一个原生 macOS 听写工具，面向已经在这台 Mac 上登录 ChatGPT / Codex Desktop 的用户，目标就是把 `F5 -> 说话 -> 回填` 这条链路做到尽可能快、尽可能稳。

公开落地页：[longbiaochen.github.io/chat-type](https://longbiaochen.github.io/chat-type/)

它的产品取向很明确：

- 全局 `F5` 热键
- 原生菜单栏应用
- 默认走本机 Codex 桌面登录态，不要求额外 API key
- 主路径保持单阶段 STT，结果优先直接可用
- 回填策略保守：只有检测到可编辑目标时才粘贴，不行就留在剪贴板
- 默认保留最后一次转写结果在剪贴板里，方便光标丢失时手动 `Cmd+V`
- 支持手动导入 TypeWhisper 术语表，增强术语对齐
- `OpenAI-Compatible Recovery` 只作为高级恢复路径

## 产品承诺

- 不额外订阅新的听写服务
- 默认路径不要求 API key
- 不要求下载或维护本地模型
- 在这台 Mac 上装好、登录好 Codex Desktop，按下 `F5` 就能开始用

## 当前版本

`ChatType` `v0.1.2` 是当前公开版本。`./scripts/package_app.sh` 会生成本地签名、未 notarize 的 `.app`，以及 GitHub Release 用的 `.zip` 和 `.dmg`。

## 使用流程

1. 安装 `ChatType`
2. 把打包后的应用安装到 `/Applications/ChatType.app`，并从这个已安装路径启动
3. 确保这台 Mac 上已经安装并登录了 Codex Desktop / ChatGPT Desktop
4. 首次录音时授予麦克风权限；如果之前拒绝过，可在设置页点 `Open Microphone Settings`
5. 如果希望自动回填到当前输入框，在设置页点 `Guide Accessibility Access`
6. `ChatType` 会打开正确的 Accessibility 页面，并用拖拽式引导帮助你把已安装应用授权进去
7. 如果列表里还是没有 `ChatType`，就在 Accessibility 页点击 `+`，手动添加 `/Applications/ChatType.app`
8. 把光标放到 Notes、Mail、Slack、Codex 等可编辑位置
9. 按一次 `F5` 开始录音，再按一次 `F5` 结束录音
10. `ChatType` 通过本地桌面登录态把音频送到 ChatGPT 转写路径
11. 可选：在设置页里导入一份 TypeWhisper 术语快照，增强 STT 后的术语对齐
12. `ChatType` 会做本地确定性术语对齐，并叠加隐藏的精确 `hintTerms`
13. 只有检测到可编辑目标时，结果才会直接回填到当前输入位置；否则保留在剪贴板，方便手动 `Cmd+V`

## 安装

### 下载版

1. 构建并打包：

```bash
./scripts/package_app.sh
```

2. 安装到 `/Applications`：

```bash
./scripts/install_app.sh
```

如果你只是为了临时调试、确实需要 ad-hoc 签名，可以显式打开：

```bash
CHATTYPE_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
```

但这不适合作为正常使用路径。较新的 macOS 上，ad-hoc build 可能会导致 Accessibility 设置里没有可切换的 `ChatType` 项；新的引导式权限修复也依赖 `/Applications/ChatType.app` 这个真实安装路径。

3. 启动已安装应用：

```bash
open -n /Applications/ChatType.app
```

不要直接运行 `dist/ChatType.app`。`dist` 里的副本只是打包产物，权限和运行时验证都必须绑定到 `/Applications/ChatType.app`。

4. 如果首次启动被 macOS 拦截：

```bash
xattr -dr com.apple.quarantine /path/to/ChatType.app
```

### Homebrew Cask 元数据

Homebrew 的 cask 元数据位于：

```text
packaging/homebrew/Casks/chattype.rb
```

目前仓库还没有单独的 Homebrew tap，但 cask 文件会跟随 release 资产保持同步。

### Release 下载

- Releases: [github.com/longbiaochen/chat-type/releases](https://github.com/longbiaochen/chat-type/releases)
- 当前版本页面：[v0.1.2](https://github.com/longbiaochen/chat-type/releases/tag/v0.1.2)

## TypeWhisper 术语导入

`ChatType` 依然坚持默认主路径不做第二轮 AI cleanup。

`v0.1.2` 新增的是本地确定性术语对齐能力：

- 在设置页里点 `Import from TypeWhisper`，导入一份 TypeWhisper 术语快照
- 导入后的词表由 ChatType 自己保存在本地配置里，不依赖运行时一直读取 TypeWhisper
- 在 STT 之后对工具名、产品名和技术术语做本地对齐，不增加第二次模型调用
- `transcription.hintTerms` 仍然保留，用于文件名等关键字的 exact-only 保留

## 高级恢复路径

如果桌面登录态路径不可用，`ChatType` 仍然保留 `OpenAI-Compatible Recovery`。

但它不是默认 onboarding 的一部分。使用它需要：

- 你自己的 endpoint
- 你自己的模型配置
- 你自己的 API key 环境变量

## 构建与验证

```bash
swift build --package-path .
swift test --package-path .
./scripts/check.sh
./script/build_and_run.sh
```

如果你要测打包后的真实路径性能：

```bash
./scripts/benchmark_stt.sh ~/bench/3s.wav ~/bench/10s.wav ~/bench/30s.wav
```

如果你要发 X，现在走 `chrome-use` 和受管的 Chrome for Testing 会话：

```bash
scripts/post_x.sh --print "ChatType update"
scripts/post_x.sh "ChatType update"
```

真正发送时会在同一个 Chrome for Testing 会话里完成发布和帖子页面验证。如果那个受管浏览器里还没登录 X，需要先在那里登录。

## 配置

`ChatType` 的运行时配置保存在：

```text
~/Library/Application Support/ChatType/config.json
```

术语相关的高级选项：

- 在设置页中用 `Import from TypeWhisper` 导入 TypeWhisper 术语
- 用 `transcription.hintTerms` 保留不想被改动的 exact-only 自定义术语

## 权限修复

`ChatType Settings` 现在把首次系统弹窗和后续修复动作分开处理：

- 麦克风首次授权仍然走 macOS 原生系统弹窗
- 如果麦克风之前被拒绝，可点 `Open Microphone Settings` 直接跳到 `Privacy & Security > Microphone`
- 如果 Accessibility 没开，可点 `Guide Accessibility Access`，打开正确的设置页并显示针对 `/Applications/ChatType.app` 的拖拽式授权引导
- `Open Accessibility Settings` 仍然保留，作为只想直接跳转设置页时的次级入口
- `Refresh Status` 会在你从系统设置返回后重新检测实时权限状态

## 风险与边界

`ChatType` V1 默认依赖本地已登录的 Codex Desktop 会话和上游私有转写路径。

这意味着：

- 对已经在用 ChatGPT Desktop 的个人用户来说，它很快也很省事
- 一旦上游桌面登录态或私有后端行为变化，这条路径可能会失效
- 它不是企业级、长期稳定的公开 API 集成方案
- 桌面桥接里的 prompt 路径是 best-effort，必要时会自动回退到 plain transcription

## 相关文档

- [English README](README.md)
- [架构说明](docs/architecture.md)
- [发布流程](docs/release.md)
- [Release Notes](docs/releases/v0.1.2.md)
- [产品 PRD](docs/chattype-v1-prd.md)

## License

MIT。见 [LICENSE](LICENSE)。
