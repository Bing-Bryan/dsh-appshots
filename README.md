# dsh-appshots

[![Release](https://img.shields.io/github/v/release/Bing-Bryan/dsh-appshots)](https://github.com/Bing-Bryan/dsh-appshots/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/Bing-Bryan/dsh-appshots/blob/main/LICENSE)

**简体中文** | [English](README.en.md)

给官方 **DeepSeek Harness** 用的窗口截图插件，也兼容 [DSH Desktop](https://github.com/anywhere-labs/dsh-desktop)。双击右 ⌘，把当前窗口放进输入框；发送时连同压缩后的窗口文字一起带给模型。

## 相对上游的优化

这个 fork 基于上游 [`WongYuYe/dsh-appshots`](https://github.com/WongYuYe/dsh-appshots)，但不是只换 UI：native helper、host 路由和客户端都改了。主要优化在五件事：官方 Harness 适配、稳定性、查看文本质量、捕获反馈、隐藏上下文安全。

| | 上游 | 这个 fork 的优化 |
|---|---|---|
| 目标应用 | DSH Desktop | 官方 DeepSeek Harness + DSH Desktop（识别 `com.deepseek.dsh`，并沿父进程链找宿主） |
| 热键 | 同时按左右 Command / Ctrl | 默认双击右 ⌘；也支持空格 + 右 ⌘、右 ⌘ + 右 ⌥、同时按 |
| 捕获反馈 | 无 | 系统快门声 + 目标窗口 5px 发光描边 |
| 查看文本 | 原始辅助功能树 | 压缩：跳过侧边栏/导航/标签组/工具栏，去重 `Description`，8k 封顶并保留最近内容 |
| 文本上下文 | 附加时绑定，发送时注入 | 压缩文本随图片发送；图片被移除或替换就不注入 |
| 稳定性 | 通过 AX/AppleScript 强制前台 | 去掉 AX frontmost 写入，改用 LaunchServices 安全激活；修复 `sessions.open` 兼容 |
| 截 DSH 自身 | 默认跳过 | 默认不跳过，方便把 DSH 界面发给模型 |

一句话概括：**上游是 DSH Desktop 的通用版；这个 fork 是官方 Harness 的适配版，重点是把截图、文本和稳定性做成一条可靠的链路。**

![dsh-appshots 界面示意](assets/hero.png)

*界面示意：目标窗口被描边，截图进草稿，点开可看「查看文本」。*

## 它能做什么

- **双击右 ⌘ / 相机按钮**：捕获最前面的窗口，不截整个屏幕
- **捕获有反馈**：系统快门声 + 目标窗口 5px 发光描边
- **图片只进草稿**：不自动发送；发送时把压缩后的窗口文字作为隐藏上下文一起带上
- **「查看文本」**：点开图片就能看窗口文字；图片被移除或替换，文字不会注入
- **官方 Harness 优先**：默认不跳过 DSH 自身，也兼容 DSH Desktop

## 安装

在能运行 `dsh` 的终端里执行：

```sh
dsh plugin --profile desktop add "github:Bing-Bryan/dsh-appshots#v0.4.8"
```

> macOS 上如果提示找不到 `dsh`，用 app 自带的 CLI：
> `"/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh" plugin --profile desktop add "github:Bing-Bryan/dsh-appshots#v0.4.8"`

1. 重启 DeepSeek Harness
2. 按下面的「权限」一节，授予 **屏幕录制** 和 **辅助功能**
3. 验证：双击右 ⌘，应该听到快门声、看到目标窗口描边，然后 DSH 到前台，图片已在输入框
4. 点开图片，右上角应该能看到「查看文本」

升级时把 `v0.4.8` 换成新版本 tag，再重启：

```sh
dsh plugin --profile desktop add "github:Bing-Bryan/dsh-appshots#vX.Y.Z"
```

从本地源码安装：

```sh
git clone https://github.com/Bing-Bryan/dsh-appshots.git
cd dsh-appshots
dsh plugin --profile desktop add .
```

Windows 会在第一次截图时用系统自带的 `csc.exe`（.NET Framework 4.x）编译助手，不需要 Visual Studio。Windows 路径继承上游，本 fork 没有单独做 Windows 验证。

## 使用

1. 聚焦你想分享的窗口
2. macOS 连续按两下右 ⌘（默认，两下间隔 420ms 内）；Windows 同时按两个 Ctrl；或点输入框旁的相机
3. DSH 到前台，截图已附加到输入框，**不会自动发送**
4. 点开图片可看「查看文本」；补一句话再发送。发送时文字会作为隐藏上下文随图片一起带给模型；图片在发送前被移除就不会注入

如果当前有打开的会话，Appshot 会附加到那里；如果没有，会新建一个会话。连续截图会进入同一个会话。

## 查看文本和隐藏上下文

窗口文字会被压缩：去容器/Help，跳过侧边栏、导航、标签组和工具栏，按钮写成 `[button]`，最多 8k 字；超出时从前面省略、保留最近内容。

压缩文本和图片用同一个唯一文件名绑定：

- 发送时图片还在 → 文本作为隐藏上下文注入一次
- 图片被移除、替换，或只是没发送 → **不注入**

所以不会出现“图删了，文字还偷偷发出去”。

## 和 Codex 对比

同一个 Gemini 回答：Codex 2,393 字 / 50 行，dsh-appshots 2,006 字 / 13 行。长度接近，但 Codex 保留了 `split group`、`row/cell` 和重复的 `Description`；dsh-appshots 只留可读正文，按钮写成 `[button]`。

![Codex 与 dsh-appshots 的 Gemini 文本对比](assets/case-gemini.png)

*文本结构对比图，不是界面截图。*

## 权限

### macOS

系统设置 → 隐私与安全性：

- **屏幕录制**：捕获最前面窗口所必需
- **辅助功能**：监听热键、读取窗口文字所必需

把这两项授予 **DeepSeek Harness**（用第三方壳时是 **DSH Desktop**）。如果热键不触发，同时允许 `appshot-capture`。

> `空格 + 右 ⌘` 这条路径会消费掉 Space 键，避免触发 Spotlight；如果辅助功能权限没给到 helper，系统仍可能弹出 Spotlight。日常建议用默认的双击右 ⌘。

### Windows

- 截图走 `CopyFromScreen`，系统可能弹一次屏幕访问授权
- 窗口文字走 UI Automation，部分提权或受保护的应用几乎读不到文字
- 默认热键是同时按两边 Ctrl。如果不触发，可改成 `hotkeyMode: win-hotkey`

## 设置

命名空间 `dsh-appshots`，位于 `~/.dsh/settings.yaml`：

| 字段 | 默认值 | 含义 |
|---|---|---|
| `skipSelf` | `false` | 跳过 DeepSeek Harness 自身；默认 `false`，所以能截 DSH 自己的窗口 |
| `attachText` | `true` | 是否把压缩文本作为隐藏上下文注入；设为 `false` 就只保留「查看文本」 |
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

- 仅支持 macOS 和 Windows；Windows 路径继承上游，本 fork 未单独验证
- 窗口文字来自系统辅助功能树，部分应用只暴露可见文本
- 窗口文字会压缩：去容器/Help，跳过侧边栏/导航/标签组，按钮写成 `[button]`，长文本合并，最多 8k 字；超出时从前面省略、保留最近消息
- 压缩文本会随发送的图片作为隐藏上下文一起带给模型；如果图片在发送前被移除，文本不会注入
- 终端像素（如 VS Code xterm）默认不进辅助功能树，编译日志仍以截图为准
- Windows 截的是窗口矩形的屏幕像素，被挡住的窗口会带上挡住它的内容

## 发布

fork 推 `vX.Y.Z` tag 会创建 GitHub Release 并附 tarball；`npm publish` 只在上游仓库执行，fork 的 CI 已跳过。

## License

MIT
