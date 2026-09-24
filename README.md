<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Pip app icon: a small black creature with glowing eyes hanging from a notch">
</p>

<h1 align="center">Pip</h1>

<p align="center">
  <strong>A tiny companion that lives in your MacBook's notch and tells you when a Claude Code or Codex session needs you.</strong>
</p>

<p align="center">
  <a href="https://github.com/ahrefabhi/pip/releases/latest"><img src="https://img.shields.io/github/v/release/ahrefabhi/pip?label=download&color=black" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="Requires macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6.2-orange" alt="Built with Swift 6.2">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/images/alert.png" width="760" alt="Pip's notch expanded into a notification: Claude needs your permission to run npm install stripe@17.2.0 in payments-api, with Open Session and Later buttons">
</p>

You start a few Claude Code or Codex sessions in iTerm, Terminal and VS Code, switch to something else, and one of them quietly stops to ask for permission. Ten minutes later you notice.

Pip fixes that. It sits invisibly inside the notch while your agents work. When one needs you, Pip drops out, the notch opens into a notification, and **Open Session** takes you straight to the exact terminal tab or editor window. Then Pip tucks itself away again.

## Features

- **Knows why a session is waiting.** Permission requests show the exact command, questions show their choices, errors show the error, and finished runs show the agent's last reply.
- **Takes you to the right place.** Opens the precise iTerm tab, Terminal tab or VS Code window, and outlines it with a brief focus ring.
- **One queue, most urgent first.** Several agents waiting become one list: permission, then questions, then errors, oldest first. Cycle through it with ⌥⌘↓.
- **Every session at a glance.** Click the notch for a live list of what's waiting, working and finished, plus a week of history. Any row jumps to its session.
- **Knows how much you have left.** The Usage tab shows how much of your Claude and Codex rate limits you've used (5-hour and weekly) and when each one resets, and alerts you when one reaches a threshold you set, for Claude, Codex or both.
- **Sounds you can tell apart.** A different chime for permission, questions, errors and finished runs, each one changeable or silenced in Settings.
- **Stays out of the way.** Unanswered alerts fold into a small pill. In full screen Pip shrinks to a thin glow, and it goes quiet while Zoom shares your screen or when you ask it to.
- **Read-only by design.** Pip never types into your terminal and never approves anything. Answers always happen in the real session.
- **Private.** Everything stays on your Mac. The only network request Pip makes is its update check to GitHub.
- **Native.** Swift and SwiftUI, light and dark mode, Reduce Motion, about 6 MB.

## A closer look

### In the notch

Idle, Pip is invisible: the notch is just the notch. While agents work, two eyes glance around beside the camera. When something needs you, Pip drops out.

<p align="center"><img src="docs/images/notch.png" width="760" alt="Three notch states: working with a spinner and a count of 5, Pip dropping out of the notch with amber eyes, and a folded pill with a badge showing 3 waiting"></p>

### When several agents need you

Pip never stacks notifications. One creature, one queue, most urgent first.

<p align="center"><img src="docs/images/multiple.png" width="760" alt="Three agents need you: payments-api needs permission, dashboard-v2 has a question, infra-terraform is blocked, each with an Open button"></p>

### Every session, and what happened today

<p align="center">
  <img src="docs/images/manager.png" width="49%" alt="The session manager: three sessions that need you with their commands and questions, two working, one finished">
  <img src="docs/images/history.png" width="49%" alt="History: today's permission requests with how long they took to answer, a finished run, a cleared error and a new task">
</p>

### How much you have left

Codex usage shows up with no setup. For Claude, choose **Set Up…** in the Usage tab or Settings (see [How it works](#how-it-works)). Numbers update while a session runs, so each agent says how old its reading is, and a window that has since reset says so rather than showing a stale percentage.

**Usage alerts.** Under the limits, **Alerts** lists when Pip should tell you a limit is getting close. Choose **Add Alert**, pick Claude, Codex or both, and a threshold: 50%, 75%, 90% or 95%, or type any percentage from 1 to 100 under **Custom**. There's one to start with: Claude and Codex at 90%. When a limit reaches an alert, Pip tells you the way it tells you about a waiting session: it drops out with the limit, how much is used and when it resets, and **Show Usage** opens this tab. It queues after any sessions that need you, follows Quiet like other alerts, and has its own sound. Each limit alerts once per threshold (so alerts at 75% and 90% each fire once), then stays quiet until it resets. The limits are the ones Claude Code and Codex report, which cover your whole account rather than each model.

<p align="center"><img src="docs/images/usage.png" width="49%" alt="The Usage tab: Claude Code at 64% of its 5-hour limit, resetting in 2h 13m, and 38% of its weekly limit; Codex on the Plus plan at 91% of its 5-hour limit in red, resetting in 37m, and 22% of its weekly limit"></p>

### Light mode

The notch stays black, so Pip hangs from it and holds a light panel instead.

<p align="center"><img src="docs/images/light.png" width="760" alt="Light mode: Pip hangs below the black notch above a frosted light notification panel"></p>

### Pip's moods

State lives in the eyes: sleepy, busy, curious, eager, worried and happy.

<p align="center"><img src="docs/images/states.png" width="760" alt="Pip's seven states: idle, working, question, permission, error, success and multiple waiting"></p>

## Install

1. Download **Pip-x.y.z.zip** from the [latest release](https://github.com/ahrefabhi/pip/releases/latest) and unzip it.
2. Move **Pip.app** to your Applications folder.
3. Open Pip, and let macOS open it once (see below).
4. Follow the short setup. It finds where your agents run, and connects to Claude Code (and Codex, if you use it).

### The first time you open Pip

Pip isn't notarized by Apple yet, so the first launch shows this. It means macOS couldn't check the app with Apple, not that anything is wrong with it:

<p align="center"><img src="docs/images/gatekeeper.png" width="258" alt="macOS dialog: “Pip” Not Opened. Apple could not verify “Pip” is free of malware that may harm your Mac or compromise your privacy. Buttons: Done and Move to Bin"></p>

Click **Done** (not Move to Bin), then either:

- **In System Settings:** open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to *"Pip" was blocked*. Confirm with your password or Touch ID, open Pip again, and choose **Open**.
- **In Terminal:** remove the "downloaded from the internet" flag, then open Pip normally:

  ```sh
  xattr -dr com.apple.quarantine /Applications/Pip.app
  ```

You only do this once. Later versions arrive through Pip's own updater and open without asking. On macOS 14 you can also right-click Pip.app and choose **Open**.

<p align="center"><img src="docs/images/onboarding.png" width="760" alt="Setup in three steps: Hi, I'm Pip; where do your agents run, with iTerm, Terminal and VS Code found; and permissions for Claude Code and Codex hooks, Accessibility and Automation"></p>

**Requirements:** macOS 14 Sonoma or later, and [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in a terminal (iTerm or Terminal), in VS Code, or in the Claude app, and optionally the [Codex CLI](https://developers.openai.com/codex/cli). Pip is designed for Macs with a notch; on other displays it shows as a small black pill at the top of the screen.

Want to look around first? Choose **Demo Mode** from the menu bar and use **Simulate** to trigger each kind of alert.

## How it works

Pip combines these sources, all on your Mac:

1. **Claude Code's session list** (`~/.claude/sessions`) says which sessions are running and whether they're busy, idle or waiting. Pip reads it with no setup.
2. **Claude Code hooks** say *why* a session is waiting. Setup adds entries to `~/.claude/settings.json` that run Pip's small collector, `pip-hook`, for each event. The collector keeps only what Pip shows (the command, the question and its choices, the error, Claude's summary, and which app and tab the session is in) and drops the rest, including transcripts. Records go into `~/Library/Application Support/Pip/inbox` and are deleted as soon as Pip reads them.
3. **Codex hooks**, if Codex is installed, work the same way through `~/.codex/hooks.json`. Codex has no session list, so the collector also notes the Codex process, and Pip drops the session when that process ends. Codex runs new hooks only after you trust them: after installing, type `/hooks` in Codex and trust Pip's entries. Pip never does this for you.

4. **Usage.** Codex writes your rate limits into its session logs (`~/.codex/sessions`) after every turn, and Pip reads the latest one. Claude Code shares your limits only with its status line, so to show them Pip asks to become that status line: it sets `statusLine` in `~/.claude/settings.json` to run the collector, which saves the numbers to `~/Library/Application Support/Pip/usage` and prints nothing. If you already have a status line, the collector runs it with the same input, so what you see doesn't change, and Pip puts it back when you remove this. Two limits come from Claude Code: only Claude Code in a terminal runs a status line (not the VS Code extension or the Claude app), and it includes usage only on Pro and Max plans. With any status line set, Claude Code also hides some footer hints, like "esc to interrupt".

The collector only records. It never answers, approves or blocks anything, prints nothing, and always exits immediately, so it can't slow your agent down or change what it does. Your other settings and hooks are left exactly as they were, and your settings file is backed up before any change.

Pip asks macOS for two permissions. **Automation** lets it select the right iTerm or Terminal tab; without it, Open Session can't switch tabs there and points you to the setting. **Accessibility** lets it find the exact window for the focus ring; without it, Pip outlines the app's front window instead.

## Using Pip

| Shortcut | Action |
|---|---|
| ⌥⌘. | Show or hide the session manager |
| ⌥⌘↓ | Move to the next waiting agent |
| ↵ | Open the highlighted session |
| Esc | Fold the alert into the pill |
| ⌘1–9 | Open a row by number |

↵, Esc and ⌘1–9 work once the notch has focus: click it, or use ⌥⌘. or ⌥⌘↓. Pip never takes the keyboard from your editor on its own.

**Staying out of the way.** When an app is full screen (or the menu bar is set to hide), Pip shrinks to a 4px glow along the top edge, only while something is waiting; click it to see what. While Zoom is sharing your screen, or when you turn on **Quiet** from the menu bar, new alerts only update the count, no sound plays and the notch doesn't open by itself. macOS doesn't let apps read Focus modes, so use Quiet for those.

**Already looking at it.** If the session that starts waiting is the one in front of you (its iTerm or Terminal tab is selected, its VS Code window is focused, or the Claude app is in front) and you've used your Mac in the last minute, Pip stays quiet for it, just as in Quiet: the count updates, but there's no pop-up and no sound. Other sessions still announce themselves. Turn this off in Settings with **Stay quiet for the session in front**.

<p align="center"><img src="docs/images/settings.png" width="360" alt="Pip's settings: appearance, open at login, update checks, notification options, staying quiet for the session in front, a sound for each state, Quiet, which apps to watch, Claude Code hooks and permissions"></p>

**Settings** (menu bar → Settings…) covers appearance, opening at login, update checks, whether alerts fold after 8 seconds, whether finished sessions pop up, staying quiet for the session in front, usage alerts, sounds for each state, Quiet, which apps to watch, hooks, Claude usage and permissions.

## Updates

Pip checks for updates once a day through [Sparkle](https://sparkle-project.org), using the releases on this page, and you can check any time from the menu bar. Every update is verified against a signing key built into Pip before it's installed.

## Uninstall

Choose **Uninstall Pip…** from the menu bar or Settings. After you confirm, Pip removes its hooks from `~/.claude/settings.json` (and `~/.codex/hooks.json`), puts back the status line you had before if Pip was showing Claude usage, deletes its data in `~/Library/Application Support/Pip`, turns off opening at login, and moves itself to the Trash. Backups Pip made of those files (`….pip-backup-…`) are left next to them.

If you delete Pip.app directly instead, its hooks stay in your Claude (and Codex) settings. They're harmless (the collector stops writing once 10,000 unread events pile up, about 5 MB), but to remove them, reinstall Pip and choose Uninstall, or delete the entries whose command ends in `Application Support/Pip/bin/pip-hook`.

## Troubleshooting

**"Pip" Not Opened: Apple could not verify "Pip" is free of malware.** Expected on the first launch of a download, because Pip isn't notarized yet. Click **Done**, then use **Open Anyway** or the `xattr` command in [The first time you open Pip](#the-first-time-you-open-pip). If macOS instead says Pip "is damaged and can't be opened", download the zip again; if it still says so, the `xattr` command above clears it.

**Pip lists a session but doesn't say why it's waiting.** The hooks aren't installed, or the session started before they were. Install them from the menu bar (or Settings → Claude Code); a session that was already running may need a restart before it reports to Pip.

**Pip doesn't see Codex sessions.** Install Codex hooks from the menu bar or Settings, then type `/hooks` in Codex and trust Pip's entries; Codex skips untrusted hooks. Restart any Codex session that was already running.

**The Usage tab doesn't show Claude's numbers.** It says why. *Waiting for Claude Code to run its status line* means no terminal session has run it yet: start or restart Claude Code in iTerm or Terminal (the VS Code extension and the Claude app don't run status lines). *Hasn't included usage* means the status line runs but Claude Code leaves usage out, as it does on plans other than Pro and Max, and in a new session until Claude's first reply.

**Open Session brings the app forward but not the right tab.** Allow Pip under System Settings → Privacy & Security → Automation for iTerm or Terminal.

**Pip asks for Accessibility, but it's already switched on in System Settings.** macOS ties Accessibility and Automation to the app's signature, and that switch belongs to an older build of Pip. In Pip's Settings (or the last setup step), choose **Reset…**: it removes Pip's entries and asks again. You can also select Pip in System Settings → Privacy & Security → Accessibility, click **−**, and allow it again. Builds signed with the same certificate keep their permissions across updates, so this should only happen once.

**⌥⌘. does nothing.** Another app already uses that shortcut. The manager is also one click on the notch, or in the menu bar.

## Building from source

Requires macOS 14 or later and Xcode 26 (Swift 6.2).

```sh
git clone https://github.com/ahrefabhi/pip.git
cd pip
swift run Pip            # run from the terminal (Demo Mode: swift run Pip --demo)
scripts/bundle.sh        # build build/Pip.app with the collector and Sparkle inside
open build/Pip.app
```

```sh
swift test                                    # unit tests: queue, phases, hooks, installer, history, usage
swift run Pip --snapshot snapshots            # render every state to PNG for checking against the design
swift run Pip --dump-sessions                 # print the sessions Pip sees right now
swift run Pip --readme-images docs/images     # re-render the images in this README (then pngquant them)
scripts/make-icon.sh                          # re-render Resources/AppIcon.icns
PIP_HOME=/tmp/pip swift run Pip               # use a scratch data folder
```

### Project layout

| Path | What's there |
|---|---|
| `Sources/PipKit` | The model, attention queue and phase machine, observation of Claude Code and Codex (inbox, registry, reducer), the hook and status line installer, history and usage readers. No UI; unit-tested. |
| `Sources/PipHook` | `pip-hook`, the collector Claude Code and Codex run for each hook event, and Claude Code's status line when Pip shows Claude usage. |
| `Sources/PipHookSchema` | The inbox record format shared by the collector and the app. |
| `Sources/Pip` | The app: the notch panel and island, Pip, the views, onboarding, settings and macOS integration. |
| `Tests/PipKitTests` | Tests for everything in PipKit. |
| `scripts` | Bundling, releasing and icon rendering. |

### Releasing

```sh
scripts/release.sh 0.2.0            # dry run: build, zip, sign, and write appcast.xml into build/release/v0.2.0
scripts/release.sh 0.2.0 --publish  # also push, tag v0.2.0 and upload both files to a GitHub release
```

The script needs a clean working tree and uses the commit count as the build number, so it always grows.

**Code signing.** `bundle.sh` signs with the `PIP_SIGN_IDENTITY` certificate if set, else a certificate named **Pip Code Signing** if your Keychain has one, else ad-hoc. Use a certificate for releases: macOS keys Accessibility and Automation to the signature, and an ad-hoc signature changes with every build, so permissions would go stale after each update. A self-signed code-signing certificate is enough for that (a Developer ID is still needed for notarization). Export it from Keychain Access (**My Certificates → Pip Code Signing → Export**) and keep the backup safe; a new certificate makes everyone allow Pip's permissions once more. Updates are signed with a Sparkle EdDSA key kept in the maintainer's login Keychain (created once with `.build/artifacts/sparkle/Sparkle/bin/generate_keys`). Back it up with `generate_keys -x <file>`: without it, existing installs can't be updated.

## Acknowledgements

Pip is built on [Sparkle](https://sparkle-project.org) for updates. It works with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex](https://developers.openai.com/codex) but isn't affiliated with or endorsed by Anthropic or OpenAI.

## License

Pip is available under the [MIT license](LICENSE).
