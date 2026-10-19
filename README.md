# dsh-appshots

[![Awesome DSH Plugin](https://awesome-dsh-plugin.com/badge.svg)](https://awesome-dsh-plugin.com)

简体中文 | [English](README.en.md)

给官方 **DeepSeek Harness** 桌面端用的窗口截图，也兼容 [DSH Desktop](https://github.com/anywhere-labs/dsh-desktop)，支持 macOS 和 Windows。

默认热键是 **双击右 ⌘**（避开 Codex 的双 Command），也可以改成 **空格 + 右 ⌘** 或 **右 ⌘ + 右 ⌥**，或点输入框旁的相机，捕获当前前台窗口，并把截图和窗口文字作为一条消息直接发进当前会话。

- 只捕获最前面的窗口，不截整个屏幕
- 默认**自动发送**：截图和窗口文字合成一条用户消息，直接进入对话
- 输入框里已经有字时退回“只附加到草稿”，避免覆盖你正在写的内容
- 读取可用的窗口文字（macOS 辅助功能 / Windows UI Automation），作为消息正文
- 默认不跳过 DSH 自身：在 DSH 里按也会截 DSH，方便把界面本身发给模型
- 截图后自动把 DeepSeek Harness（或 DSH Desktop）调到前台

## 安装

```sh
dsh plugin --profile desktop add github:Bing-Bryan/dsh-appshots
```

安装后重启 DeepSeek Harness。

从本地源码安装：

```sh
git clone https://github.com/Bing-Bryan/dsh-appshots.git
cd dsh-appshots
dsh plugin --profile desktop add .
```

Windows 会在第一次截图时用系统自带的 `csc.exe`（.NET Framework 4.x）编译助手，不需要安装 Visual Studio。

发布：把 `package.json` 版本改成 `X.Y.Z` 后推 `vX.Y.Z` tag。GitHub Actions 会打 GitHub Release 并用 Trusted Publisher（OIDC）发到 npm。

## 权限

### macOS

系统设置 → 隐私与安全性：

- **屏幕录制**：捕获最前面窗口所必需
- **辅助功能**：监听热键、读取窗口文字所必需

把这两项授予 **DeepSeek Harness**（用第三方壳时是 **DSH Desktop**）。如果热键不触发，同时允许 `appshot-capture`。

> `空格 + 右 ⌘` 这条路径会消费掉 Space 键，避免触发 Spotlight；但如果辅助功能权限没给到 helper，系统仍可能弹出 Spotlight。日常建议用默认的双击右 ⌘。

### Windows

- 截图走 `CopyFromScreen`，系统可能弹一次屏幕访问授权
- 窗口文字走 UI Automation，部分提权或受保护的应用几乎读不到文字
- 默认热键是同时按两边 Ctrl。如果不触发，可改成 `hotkeyMode: win-hotkey`

## 使用

1. 聚焦你想分享的窗口。
2. macOS **连续按两下右 ⌘**（默认，两下间隔 420ms 内），Windows 同时按两个 Ctrl，或点击输入框里的相机按钮。
3. DeepSeek Harness 来到前台，截图和窗口文字已经作为一条消息发出。

如果当前有打开的会话，Appshot 会发到那里；如果没有，会新建一个会话。连续截图会进入同一个会话。想改回“只附加、不自动发送”，设置 `autoSend: false`。

## 设置

命名空间 `dsh-appshots`，位于 `~/.dsh/settings.yaml`：

| 字段 | 默认值 | 含义 |
|---|---|---|
| `skipSelf` | `false` | 跳过 DeepSeek Harness 自身；默认 `false`，所以能截 DSH 自己的窗口 |
| `autoSend` | `true` | 捕获后直接把截图 + 窗口文字作为一条消息发送；输入框有内容时退回只附加 |
| `attachText` | `true` | 退回“只附加”模式时，是否把辅助功能树作为隐藏上下文注入 |
| `recentWindowMs` | `60000` | 没有打开会话时，复用这个时间窗口内截图过的会话 |
| `hotkeyMode` | `auto` | `auto` / `double-right-command` / `space-right-command` / `right-command-right-option` / `both-command` / `both-control` / `carbon` / `win-hotkey` / `off` |
| `carbonKeyCode` | `0` | `hotkeyMode` 为 `carbon` 时的 Carbon 键码 |
| `carbonModifiers` | `256` | Carbon 修饰键；256 是 Command |
| `winVk` | `44` | `hotkeyMode` 为 `win-hotkey` 时的虚拟键码（44 是 PrintScreen） |
| `winModifiers` | `3` | `win-hotkey` 的 Win32 修饰键；3 是 Ctrl+Alt |

`auto` 在 macOS 上是 **双击右 ⌘**，在 Windows 上是两边 Ctrl。按住右 ⌘ 期间如果按了别的键（比如 ⌘C），这一次不会被算作“单击”，避免误触。想换成空格加右 ⌘ 或右 ⌘ + 右 ⌥：

```yaml
dsh-appshots:
  hotkeyMode: space-right-command   # 或 right-command-right-option
```

## 限制

- 仅支持 macOS 和 Windows
- 窗口文字来自系统辅助功能树，部分应用只暴露可见文本
- 隐藏文本按 VoiceOver / UI Automation 树输出（角色、缩进、Description / Value / URL），不再做成扁平行
- 点击已附加的 Appshot 预览时，右上角可「查看文本」，展示当前窗口读到的辅助功能文字
- 终端像素（如 VS Code xterm）默认不进辅助功能树，编译日志仍以截图为准
- Windows 截的是窗口矩形的屏幕像素，被挡住的窗口会带上挡住它的内容

## License

MIT
