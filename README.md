<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Nudge app icon: a small black creature with glowing eyes hanging from a notch">
</p>

<h1 align="center">Nudge</h1>

<p align="center">
  <strong>A tiny companion that lives in your MacBook's notch and tells you when a Claude Code or Codex session needs you.</strong>
</p>

<p align="center">
  <a href="https://github.com/ahrefabhi/nudge/releases/latest"><img src="https://img.shields.io/github/v/release/ahrefabhi/nudge?label=download&color=black" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="Requires macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6.2-orange" alt="Built with Swift 6.2">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/images/alert.png" width="760" alt="Nudge's notch expanded into a notification: Claude needs your permission to run npm install stripe@17.2.0 in payments-api, with Open Session and Later buttons">
</p>

When a session stops to ask for permission, a question or help with an error, Nudge drops out of the notch and tells you why. **Open Session** takes you to the exact terminal tab or editor window.

https://github.com/user-attachments/assets/2986e464-c3f6-4134-8ae4-edb229d1eea9

## Features

- **Shows why a session is waiting:** the command, the question and its choices, the error, or the agent's last reply.
- **Opens the right place:** the exact iTerm or Terminal tab, or VS Code window. Other apps (Warp, Ghostty, Zed, Cursor…) come to the front too.
- **One queue, most urgent first:** permissions, then questions, then errors. Cycle with ⌥⌘↓.
- **Every session at a glance:** click the notch for what's waiting, working and finished, plus a week of history.
- **Rate limits:** your Claude and Codex 5-hour and weekly usage, with alerts at thresholds you set.
- **Stays out of the way:** alerts fold into a pill, full screen shrinks Nudge to a glow, and it goes quiet while your screen is shared.
- **Read-only and private:** Nudge never types or approves anything, and everything stays on your Mac.
- **Native:** Swift and SwiftUI, light and dark mode, Reduce Motion, about 6 MB.

## A closer look

### In the notch

Idle, the notch is just the notch. While agents work, two eyes glance around. When something needs you, Nudge drops out.

<p align="center"><img src="docs/images/notch.png" width="760" alt="Three notch states: working with a spinner and a count of 5, Nudge dropping out of the notch with amber eyes, and a folded pill with a badge showing 3 waiting"></p>

### On a Mac without a notch

On an external display or older MacBook, Nudge hides while idle and slides down as a black pill when agents work. Open the manager from the menu bar icon or ⌥⌘.

<p align="center"><img src="docs/images/menu-bar.png" width="760" alt="Four menu bar states on a display without a notch: idle with nothing showing, working as a black pill with a spinner and a count of 5, Nudge dropping out of the menu bar with amber eyes, and a folded pill with a badge showing 3 waiting"></p>

### When several agents need you

<p align="center"><img src="docs/images/multiple.png" width="760" alt="Three agents need you: payments-api needs permission, dashboard-v2 has a question, infra-terraform is blocked, each with an Open button"></p>

### Every session, and what happened today

<p align="center">
  <img src="docs/images/manager.png" width="49%" alt="The session manager: three sessions that need you with their commands and questions, two working, one finished">
  <img src="docs/images/history.png" width="49%" alt="History: today's permission requests with how long they took to answer, a finished run, a cleared error and a new task">
</p>

### Usage

Nudge asks Claude Code and Codex for your limits every few minutes, with no setup. Add alerts (50–95% or a custom value) for Claude, Codex or both; each fires once per threshold until the limit resets.

<p align="center"><img src="docs/images/usage.png" width="49%" alt="The Usage tab: Claude Code at 64% of its 5-hour limit, resetting in 2h 13m, and 38% of its weekly limit; Codex on the Plus plan at 91% of its 5-hour limit in red, resetting in 37m, and 22% of its weekly limit; below them, two alerts: Claude at 75%, and Claude and Codex at 90%"></p>

<p align="center"><img src="docs/images/usage-alert.png" width="760" alt="A usage alert in the notch: Claude reached your usage alert, 5-hour limit, 92% used, alert at 90%, and when it resets, with Show Usage and Later buttons"></p>

### Light mode

<p align="center"><img src="docs/images/light.png" width="760" alt="Light mode: Nudge hangs below the black notch above a frosted light notification panel"></p>

### Nudge's moods

<p align="center"><img src="docs/images/states.png" width="760" alt="Nudge's seven states: idle, working, question, permission, error, success and multiple waiting"></p>

## Install

1. Download **Nudge-x.y.z.zip** from the [latest release](https://github.com/ahrefabhi/nudge/releases/latest), unzip it, and move **Nudge.app** to Applications.
2. Open it (see below for the first launch).
3. Follow the setup, which connects Claude Code and, if you use it, Codex.

**Requires** macOS 14+ and [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (any terminal, editor or the Claude app). [Codex CLI](https://developers.openai.com/codex/cli) is optional. Try it first with **Demo Mode** in the menu bar.

### The first time you open Nudge

Nudge isn't notarized yet, so macOS blocks the first launch:

<p align="center"><img src="docs/images/gatekeeper.png" width="262" alt="macOS dialog: “Nudge” Not Opened. Apple could not verify “Nudge” is free of malware that may harm your Mac or compromise your privacy. Buttons: Done and Move to Bin"></p>

Click **Done**, then either go to **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Nudge.app
```

You only do this once; updates open normally.

<p align="center"><img src="docs/images/onboarding.png" width="760" alt="Setup in three steps: Hi, I'm Nudge; where do your agents run, with iTerm, Terminal and VS Code found; and permissions for Claude Code and Codex hooks, Accessibility and Automation"></p>

## How it works

Everything runs on your Mac. The only network request Nudge makes itself is the update check.

- **Session list:** Claude Code's `~/.claude/sessions` says which sessions run and whether they're busy, idle or waiting.
- **Hooks:** setup adds hooks to `~/.claude/settings.json` (and `~/.codex/hooks.json`) that run `nudge-hook`. It records only what Nudge shows (command, question, error, summary, branch, app and tab), never transcripts, into `~/Library/Application Support/Nudge/inbox`, which Nudge deletes after reading. It never answers or blocks anything and exits immediately. For Codex, type `/hooks` and trust Nudge's entries.
- **Usage:** Nudge asks `claude -p` and `codex app-server` for rate limits using their own sign-ins; it never reads credentials. If that fails, **Set Up…** reads Claude's numbers from its status line instead, keeping any status line you have.
- **Permissions:** *Automation* selects the right iTerm or Terminal tab. *Accessibility* finds the exact window and detects screen sharing.

Your settings files are backed up before any change.

## Using Nudge

| Shortcut | Action |
|---|---|
| ⌥⌘. | Show or hide the session manager |
| ⌥⌘↓ | Next waiting agent |
| ↵ | Open the highlighted session |
| Esc | Fold the alert into the pill |
| ⌘1–9 | Open a row by number |

↵, Esc and ⌘1–9 work once the notch has focus. Nudge never takes the keyboard on its own.

**Goes quiet** (count only, no pop-up or sound) while your screen is shared or recorded, when **Quiet** is on, or for the session you're already looking at. In full screen it shrinks to a glow along the top edge.

**Settings** covers appearance, login, updates, sounds per state, usage alerts, which apps to watch, hooks and permissions.

<p align="center"><img src="docs/images/settings.png" width="360" alt="Nudge's settings: appearance, open at login, update checks, notification options, staying quiet for the session in front, usage alerts, a sound for each state, Quiet, which apps to watch, Claude Code hooks and permissions"></p>

## Updates and uninstall

Nudge updates itself through [Sparkle](https://sparkle-project.org), verifying each update's signature. Coming from Pip, the old name? Your data moves over automatically; allow the permissions once more.

To remove it, choose **Uninstall Nudge…** from the menu bar. It removes its hooks, restores your status line, deletes its data and moves itself to the Trash.

## Troubleshooting

- **"Nudge" Not Opened:** expected on first launch. See [The first time you open Nudge](#the-first-time-you-open-nudge).
- **A session shows but not why it's waiting:** install hooks from the menu bar, then restart that session.
- **No Codex sessions:** install Codex hooks, trust them with `/hooks`, and restart Codex.
- **No Claude usage:** the Usage tab says why. Update Claude Code, or choose **Set Up…** and run Claude Code in a terminal.
- **Opens the app but not the tab:** allow Nudge under Privacy & Security → Automation (iTerm, Terminal) or Accessibility (other apps).
- **Accessibility is on but Nudge asks again:** the permission belongs to an older build. Choose **Reset…** in Settings.
- **⌥⌘. does nothing:** another app uses it. Click the notch instead.

## Building from source

Requires Xcode 26 (Swift 6.2).

```sh
git clone https://github.com/ahrefabhi/nudge.git && cd nudge
swift run Nudge                               # run (add --demo for Demo Mode)
scripts/bundle.sh && open build/Nudge.app     # build the app bundle
swift test                                    # unit tests
swift run Nudge --snapshot snapshots          # render every state to PNG
swift run Nudge --dump-sessions               # print the sessions Nudge sees
swift run Nudge --readme-images docs/images   # re-render README images
NUDGE_HOME=/tmp/nudge swift run Nudge         # use a scratch data folder
```

| Path | What's there |
|---|---|
| `Sources/NudgeKit` | Model, queue, phase machine, session observation, hook installer, history, usage. Unit-tested. |
| `Sources/NudgeHook` | `nudge-hook`, the collector hooks run. |
| `Sources/NudgeHookSchema` | The inbox record format. |
| `Sources/Nudge` | The app: notch, views, onboarding, settings, macOS integration. |
| `scripts` | Bundling, releasing, icon rendering. |

**Releasing:** `scripts/release.sh 0.2.0` does a dry run; add `--publish` to tag and upload. Sign with a stable certificate (`NUDGE_SIGN_IDENTITY` or one named **Nudge Code Signing**) so macOS permissions survive updates, and back up the Sparkle key (`generate_keys -x <file>`).

## Acknowledgements

Nudge started from a great idea: [Orbit](https://github.com/syedmazharaliraza/orbit), by [Syed Mazhar Ali Raza](https://github.com/syedmazharaliraza). Nudge wouldn't exist without it. Huge thanks to Syed for the inspiration and for building something so thoughtful. Go give Orbit a star.

Nudge works with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex](https://developers.openai.com/codex) but isn't affiliated with Anthropic or OpenAI.

## License

[MIT](LICENSE)
