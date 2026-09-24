<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Pip app icon: a small black creature with glowing eyes hanging from a notch">
</p>

<h1 align="center">Pip</h1>

<p align="center">
  <strong>A tiny companion that lives in your MacBook's notch and tells you when a Claude Code session needs you.</strong>
</p>

<p align="center">
  <a href="https://github.com/ahrefabhi/pip/releases/latest"><img src="https://img.shields.io/github/v/release/ahrefabhi/pip?label=download&color=black" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="Requires macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6.2-orange" alt="Built with Swift 6.2">
</p>

<p align="center">
  <img src="docs/images/alert.png" width="760" alt="Pip's notch expanded into a notification: Claude needs your permission to run npm install stripe@17.2.0 in payments-api, with Open Session and Later buttons">
</p>

You start a few Claude Code sessions in iTerm, Terminal and VS Code, switch to something else, and one of them quietly stops to ask for permission. Ten minutes later you notice.

Pip fixes that. It sits invisibly inside the notch while your agents work. When one needs you, Pip drops out, the notch opens into a notification, and **Open Session** takes you straight to the exact terminal tab or editor window. Then Pip tucks itself away again.

## Features

- **Knows why a session is waiting.** Permission requests show the exact command, questions show their choices, errors show the error, and finished runs show Claude's summary.
- **Takes you to the right place.** Opens the precise iTerm tab, Terminal tab or VS Code window, and outlines it with a brief focus ring.
- **One queue, most urgent first.** Several agents waiting become one list: permission, then questions, then errors, oldest first. Cycle through it with ⌥⌘↓.
- **Every session at a glance.** Click the notch for a live list of what's waiting, working and finished, plus a week of history. Any row jumps to its session.
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

### Light mode

The notch stays black, so Pip hangs from it and holds a light panel instead.

<p align="center"><img src="docs/images/light.png" width="760" alt="Light mode: Pip hangs below the black notch above a frosted light notification panel"></p>

### Pip's moods

State lives in the eyes: sleepy, busy, curious, eager, worried and happy.

<p align="center"><img src="docs/images/states.png" width="760" alt="Pip's seven states: idle, working, question, permission, error, success and multiple waiting"></p>

## Install

1. Download **Pip-x.y.z.zip** from the [latest release](https://github.com/ahrefabhi/pip/releases/latest) and unzip it.
2. Move **Pip.app** to your Applications folder.
3. Open Pip. Because it isn't notarized by Apple yet, macOS says it can't verify it the first time: open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to Pip. (On macOS 14 you can instead right-click Pip.app and choose **Open**.) You only do this once.
4. Follow the short setup. It finds where your agents run, and connects to Claude Code.

<p align="center"><img src="docs/images/onboarding.png" width="760" alt="Setup in three steps: Hi, I'm Pip; where do your agents run, with iTerm, Terminal and VS Code found; and permissions for Claude Code hooks, Accessibility and Automation"></p>

**Requirements:** macOS 14 Sonoma or later, and [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in a terminal (iTerm or Terminal), in VS Code, or in the Claude app. Pip is designed for Macs with a notch; on other displays it shows as a small black pill at the top of the screen.

Want to look around first? Choose **Demo Mode** from the menu bar and use **Simulate** to trigger each kind of alert.

## How it works

Pip combines two sources, both on your Mac:

1. **Claude Code's session list** (`~/.claude/sessions`) says which sessions are running and whether they're busy, idle or waiting. Pip reads it with no setup.
2. **Claude Code hooks** say *why* a session is waiting. Setup adds entries to `~/.claude/settings.json` that run Pip's small collector, `pip-hook`, for each event. The collector keeps only what Pip shows (the command, the question and its choices, the error, Claude's summary, and which app and tab the session is in) and drops the rest, including transcripts. Records go into `~/Library/Application Support/Pip/inbox` and are deleted as soon as Pip reads them.

The collector only records. It never answers, approves or blocks anything, prints nothing, and always exits immediately, so it can't slow Claude down or change what it does. Your other settings and hooks are left exactly as they were, and your settings file is backed up before any change.

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

**Staying out of the way.** When an app is full screen (or the menu bar is set to hide), Pip shrinks to a 4px glow along the top edge, only while something is waiting; click it to see what. While Zoom is sharing your screen, or when you turn on **Quiet** from the menu bar, new alerts only update the count and the notch doesn't open by itself. macOS doesn't let apps read Focus modes, so use Quiet for those.

<p align="center"><img src="docs/images/settings.png" width="360" alt="Pip's settings: appearance, open at login, update checks, notification options, Quiet, which apps to watch, Claude Code hooks and permissions"></p>

**Settings** (menu bar → Settings…) covers appearance, opening at login, update checks, whether alerts fold after 8 seconds, whether finished sessions pop up, Quiet, which apps to watch, hooks and permissions.

## Updates

Pip checks for updates once a day through [Sparkle](https://sparkle-project.org), using the releases on this page, and you can check any time from the menu bar. Every update is verified against a signing key built into Pip before it's installed.

## Uninstall

Choose **Uninstall Pip…** from the menu bar or Settings. After you confirm, Pip removes its hooks from `~/.claude/settings.json`, deletes its data in `~/Library/Application Support/Pip`, turns off opening at login, and moves itself to the Trash. Backups of your Claude settings (`settings.json.pip-backup-…`) are left in `~/.claude`.

If you delete Pip.app directly instead, its hooks stay in your Claude settings. They're harmless (the collector stops writing once 10,000 unread events pile up, about 5 MB), but to remove them, reinstall Pip and choose Uninstall, or delete the entries whose command ends in `Application Support/Pip/bin/pip-hook`.

## Troubleshooting

**Pip lists a session but doesn't say why it's waiting.** The hooks aren't installed, or the session started before they were. Install them from the menu bar (or Settings → Claude Code); a session that was already running may need a restart before it reports to Pip.

**Open Session brings the app forward but not the right tab.** Allow Pip under System Settings → Privacy & Security → Automation for iTerm or Terminal.

**macOS asks for permissions again after an update.** Pip isn't signed with an Apple Developer ID yet, and macOS ties these permissions to the app's signature. Allow them again; this goes away once releases are signed.

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
swift test                                    # unit tests: queue, phases, hooks, installer, history
swift run Pip --snapshot snapshots            # render every state to PNG for checking against the design
swift run Pip --dump-sessions                 # print the sessions Pip sees right now
swift run Pip --readme-images docs/images     # re-render the images in this README (then pngquant them)
scripts/make-icon.sh                          # re-render Resources/AppIcon.icns
PIP_HOME=/tmp/pip swift run Pip               # use a scratch data folder
```

### Project layout

| Path | What's there |
|---|---|
| `Sources/PipKit` | The model, attention queue and phase machine, observation of Claude Code (inbox, registry, reducer), the hook installer and history. No UI; unit-tested. |
| `Sources/PipHook` | `pip-hook`, the collector Claude Code runs for each hook event. |
| `Sources/PipHookSchema` | The inbox record format shared by the collector and the app. |
| `Sources/Pip` | The app: the notch panel and island, Pip, the views, onboarding, settings and macOS integration. |
| `Tests/PipKitTests` | Tests for everything in PipKit. |
| `scripts` | Bundling, releasing and icon rendering. |

### Releasing

```sh
scripts/release.sh 0.2.0            # dry run: build, zip, sign, and write appcast.xml into build/release/v0.2.0
scripts/release.sh 0.2.0 --publish  # also push, tag v0.2.0 and upload both files to a GitHub release
```

The script needs a clean working tree and uses the commit count as the build number, so it always grows. Updates are signed with a Sparkle EdDSA key kept in the maintainer's login Keychain (created once with `.build/artifacts/sparkle/Sparkle/bin/generate_keys`). Back it up with `generate_keys -x <file>`: without it, existing installs can't be updated.

## Acknowledgements

Pip is built on [Sparkle](https://sparkle-project.org) for updates. It works with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) but isn't affiliated with or endorsed by Anthropic.
