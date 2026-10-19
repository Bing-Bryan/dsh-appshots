# dsh-appshots

[![Awesome DSH Plugin](https://awesome-dsh-plugin.com/badge.svg)](https://awesome-dsh-plugin.com)

[简体中文](README.md) | English

Codex-style window capture for the official **DeepSeek Harness** desktop app, also compatible with [DSH Desktop](https://github.com/anywhere-labs/dsh-desktop), on macOS and Windows.

The default hotkey is **double-tap Right Command** (to avoid Codex's double-Command), or **Space + Right Command** or **Right Command + Right Option**, or the camera button next to the composer: grab the frontmost window and send its screenshot plus window text as one message into the current chat.

- Captures the frontmost window only, not the whole screen
- Sends automatically by default: the screenshot and window text become one user message
- Falls back to attaching the capture to the composer draft when the composer already has text
- Reads available window text (Accessibility on macOS, UI Automation on Windows) and uses it as the message body
- Does not skip DSH by default, so you can share the DSH window itself
- After capture, brings DeepSeek Harness (or DSH Desktop) to the front

## Install

```sh
dsh plugin --profile desktop add github:Bing-Bryan/dsh-appshots
```

Restart DeepSeek Harness after installing.

From source:

```sh
git clone https://github.com/Bing-Bryan/dsh-appshots.git
cd dsh-appshots
dsh plugin --profile desktop add .
```

On Windows the helper compiles on first capture with the system `csc.exe` (.NET Framework 4.x). Visual Studio is not required.

Release: bump `package.json` to `X.Y.Z` and push a `vX.Y.Z` tag. GitHub Actions opens the GitHub Release and publishes to npm with Trusted Publisher (OIDC).

## Permissions

### macOS

System Settings → Privacy & Security:

- **Screen Recording**: required to capture the frontmost window
- **Accessibility**: required to listen for the hotkey and read window text

Grant these to **DeepSeek Harness** (or **DSH Desktop** for the third-party shell). If the hotkey does not fire, also allow `appshot-capture`.

> `Space + Right Command` consumes the Space key to avoid Spotlight, but without Accessibility granted to the helper macOS may still open Spotlight. The default double-tap is the safer choice.

### Windows

- Screen capture uses `CopyFromScreen`; Windows may prompt once for screen access
- Window text uses UI Automation; some elevated or protected apps expose little or no text
- The default hotkey is both Ctrl keys. If it does not fire, try `hotkeyMode: win-hotkey`

## Use

1. Focus the window you want to share.
2. **Double-tap Right Command** (default on macOS, within 420ms) or both Ctrl keys (Windows), or click the camera button in the composer.
3. DeepSeek Harness comes to the front and the screenshot plus window text are already sent as one message.

If a session is currently open, the appshot goes there. If none is open, a new session is created. Consecutive captures go to the same session. Set `autoSend: false` to go back to attach-only.

## Settings

Namespace `dsh-appshots` in `~/.dsh/settings.yaml`:

| Field | Default | Meaning |
|---|---|---|
| `skipSelf` | `false` | Skip DeepSeek Harness itself; `false` lets you capture the DSH window |
| `autoSend` | `true` | Send the screenshot + window text as one message; fall back to attach-only when the composer has text |
| `attachText` | `true` | In attach-only mode, inject the accessibility tree as hidden model context |
| `recentWindowMs` | `60000` | If no session is open, reuse the session captured within this window |
| `hotkeyMode` | `auto` | `auto` / `double-right-command` / `space-right-command` / `right-command-right-option` / `both-command` / `both-control` / `carbon` / `win-hotkey` / `off` |
| `carbonKeyCode` | `0` | Carbon key code when `hotkeyMode` is `carbon` |
| `carbonModifiers` | `256` | Carbon modifiers; 256 is Command |
| `winVk` | `44` | Virtual-key code when `hotkeyMode` is `win-hotkey` (44 is PrintScreen) |
| `winModifiers` | `3` | Win32 modifiers for `win-hotkey`; 3 is Ctrl+Alt |

`auto` is **double-tap Right Command** on macOS and both Ctrl keys on Windows. Pressing another key while Right Command is held (for example ⌘C) marks that press as not a clean tap, so shortcuts do not trigger a capture. To switch to Space + Right Command or Right Command + Right Option:

```yaml
dsh-appshots:
  hotkeyMode: space-right-command   # or right-command-right-option
```

## Limits

- macOS and Windows only
- Window text comes from the platform accessibility tree, so some apps expose only visible copy
- Hidden text is an indented VoiceOver / UI Automation tree (role, Description / Value / URL), not flattened unique lines
- Opening an attached Appshot preview adds a View text control that shows the accessibility copy for that window
- Terminal pixels (VS Code xterm) are usually absent from accessibility, so compile logs still come from the screenshot
- Windows capture copies the on-screen pixels of the window rectangle; occluded windows include whatever is visible

## License

MIT
