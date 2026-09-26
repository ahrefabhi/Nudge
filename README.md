<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Peeku app icon: a small black creature with glowing eyes hanging from a notch">
</p>

<h1 align="center">Peeku</h1>

<p align="center">
  <strong>A tiny companion that lives in your MacBook's notch and tells you when a Claude Code or Codex session needs you.</strong>
</p>

<p align="center">
  <a href="https://github.com/ahrefabhi/peeku/releases/latest"><img src="https://img.shields.io/github/v/release/ahrefabhi/peeku?label=download&color=black" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="Requires macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6.2-orange" alt="Built with Swift 6.2">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/images/alert.png" width="760" alt="Peeku's notch expanded into a notification: Claude needs your permission to run npm install stripe@17.2.0 in payments-api, with Open Session and Later buttons">
</p>

When a session stops to ask for permission, a question or help with an error, Peeku drops out of the notch and tells you why. **Open Session** takes you to the exact terminal tab or editor window.

https://github.com/user-attachments/assets/eefa5891-946c-46a3-9c4b-7ca000052e3b

## Features

- **Shows why a session is waiting:** the command, the question and its choices, the error, or the agent's last reply.
- **Opens the right place:** the exact iTerm or Terminal tab, or VS Code window. Other apps (Warp, Ghostty, Zed, Cursor…) come to the front too.
- **One queue, most urgent first:** permissions, then questions, then errors. Cycle with ⌥⌘↓.
- **Every session at a glance:** click the notch for what's waiting, working and finished, plus a week of history.
- **Rate limits:** your Claude and Codex 5-hour and weekly usage, with alerts at thresholds you set.
- **Spend:** what today, the last 7 or the last 30 days cost at API prices, tokens used, and bars split by model.
- **Quick commands:** save `npm run dev` with its folder, then run, restart and stop it from the notch. Read its output, answer its prompts, and hear about it when it fails.
- **Stays out of the way:** alerts fold into a pill, full screen shrinks Peeku to a glow, and it goes quiet while your screen is shared.
- **Read-only and private:** Peeku never types into or approves anything in your agent sessions, and everything stays on your Mac.
- **Native:** Swift and SwiftUI, light and dark mode, Reduce Motion, about 6 MB.

## A closer look

### In the notch

Idle, the notch is just the notch. While agents work, two eyes glance around. When something needs you, Peeku drops out.

<p align="center"><img src="docs/images/notch.png" width="760" alt="Three notch states: working with a spinner and a count of 5, Peeku dropping out of the notch with amber eyes, and a folded pill with a badge showing 3 waiting"></p>

### On a Mac without a notch

On an external display or older MacBook, there's no fake notch. Peeku lives in its menu bar icon, and the icon's eyes show what it's doing: they glance around while agents work, and change color with a dot or a count when something needs you. When an agent needs you, Peeku climbs down from the icon, hangs from the menu bar and holds the alert. Click the icon (or press ⌥⌘.) for the session manager, right-click it for the menu.

<p align="center"><img src="docs/images/menu-bar.png" width="760" alt="Four states of Peeku's menu bar icon on a display without a notch: idle with sleepy eyes, working with open eyes, Peeku climbing down from the icon with amber eyes while the icon shows an amber dot, and folded with a badge showing 3 waiting"></p>

<p align="center"><img src="docs/images/menu-bar-alert.png" width="760" alt="On a display without a notch, Peeku hangs from its menu bar icon above a frosted panel: Claude needs your permission to run npm install stripe@17.2.0 in payments-api, with Open Session and Later buttons"></p>

### When several agents need you

<p align="center"><img src="docs/images/multiple.png" width="760" alt="Three agents need you: payments-api needs permission, dashboard-v2 has a question, infra-terraform is blocked, each with an Open button"></p>

### Every session, and what happened today

<p align="center">
  <img src="docs/images/manager.png" width="49%" alt="The session manager, with Now, History and Usage tabs, a settings gear and a footer dock with Agents and Commands: three sessions that need you with their commands and questions, two working, one finished; under each, its branch, model, cost so far and how full its context is, auth-service at 93% in red">
  <img src="docs/images/history.png" width="49%" alt="History: today's permission requests with how long they took to answer, a finished run, a cleared error and a new task">
</p>

### Usage

Peeku asks Claude Code and Codex for your limits every few minutes, with no setup. Above each agent's limits, it adds up their session logs for **Today**, **7 days** or **30 days**: the cost at API prices, tokens (cache reads included), replies, the top model, and a bar per hour (today) or day, split by model. Hover a bar for its numbers. On a subscription, the dollars are what the same tokens would cost on the API, not what you pay. Add alerts (50–95% or a custom value) for Claude, Codex or both; each fires once per threshold until the limit resets.

<p align="center"><img src="docs/images/usage.png" width="49%" alt="The Usage tab set to 30 days: Claude Code cost $970.43, 911M tokens, 11,625 replies, top model Opus 5, with a bar per day split into Opus 5, Fable 5.1 and other models; then its 5-hour limit at 64% and weekly limit at 38%; below, Codex on the Plus plan with 75M tokens, 959 replies and GPT-6 Luna as top model"></p>

<p align="center"><img src="docs/images/usage-alert.png" width="760" alt="A usage alert in the notch: Claude reached your usage alert, 5-hour limit, 92% used, alert at 90%, and when it resets, with Show Usage and Later buttons"></p>

### Commands

Commands keeps the commands you run all day, like a dev server, a worker or a docs preview. Add one with **+ New Command**: pick its folder and type the command. It runs in your login shell, like a new terminal tab, so nvm, pyenv and your aliases work. Each row shows whether it's running and its latest line of output. Hover a row to edit or delete it. Commands lives in the dock at the bottom of the session manager, not in the tabs at the top, and shows how many are running. Turn it off in Settings → Utilities if you don't need it.

<p align="center"><img src="docs/images/commands.png" width="49%" alt="Commands, opened from the footer dock, with a back arrow and a New button: Dashboard running npm run dev for 12 minutes with its latest Vite line, payments-api exited with code 1, and Docs waiting for input on a port question, each with output, restart and stop buttons"></p>

When a command exits with an error, Peeku tells you with its last line of output. **Restart** runs it again, and **Show Output** opens everything it printed.

<p align="center"><img src="docs/images/command-alert.png" width="760" alt="A notch alert: Dashboard exited with code 1, with the last line Error: listen EADDRINUSE: address already in use :::5173, and Show Output, Restart and Later buttons"></p>

Commands run in a real terminal, so tools can ask questions, like which port to use when theirs is taken. When a command asks and waits, Peeku drops out of the notch. Answer a yes/no question right there, or type any answer in the output window. Its buttons send Yes, No, Return and Ctrl-C.

<p align="center"><img src="docs/images/command-input.png" width="760" alt="A notch alert: Storefront is waiting for input, asking whether to run the app on another port because something is already running on port 3000, with Show Output, Yes and No buttons"></p>

<p align="center"><img src="docs/images/command-output.png" width="720" alt="A command's output window: pnpm build and pnpm preview in ~/code/docs, waiting for input on the question Port 4173 is in use. Use 4174 instead? (Y/n), with a reply field and Yes, No, Return and Ctrl-C buttons"></p>

Stopping a command stops everything it started, so a dev server doesn't keep its port. Quitting Peeku stops them all.

### Light mode

<p align="center"><img src="docs/images/light.png" width="760" alt="Light mode: Peeku hangs below the black notch above a frosted light notification panel"></p>

### Peeku's moods

<p align="center"><img src="docs/images/states.png" width="760" alt="Peeku's seven states: idle, working, question, permission, error, success and multiple waiting"></p>

## Install

1. Download **Peeku-x.y.z.zip** (not the `-update` one, which is for in-app updates) from the [latest release](https://github.com/ahrefabhi/peeku/releases/latest), unzip it, and move **Peeku.app** to Applications.
2. Open it (see below for the first launch).
3. Follow the setup, which connects Claude Code and, if you use it, Codex.

**Requires** macOS 14+ and [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (any terminal, editor or the Claude app). [Codex CLI](https://developers.openai.com/codex/cli) is optional. Try it first with **Demo Mode** in the menu bar.

### The first time you open Peeku

Peeku isn't notarized yet, so macOS blocks the first launch:

<p align="center"><img src="docs/images/gatekeeper.png" width="262" alt="macOS dialog: “Peeku” Not Opened. Apple could not verify “Peeku” is free of malware that may harm your Mac or compromise your privacy. Buttons: Done and Move to Bin"></p>

Click **Done**, then either go to **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Peeku.app
```

You only do this once; updates open normally.

<p align="center"><img src="docs/images/onboarding.png" width="760" alt="Setup in three steps: Hi, I'm Peeku; where do your agents run, with iTerm, Terminal and VS Code found; and permissions for Claude Code and Codex hooks, Accessibility and Automation"></p>

## How it works

Everything runs on your Mac. The only network request Peeku makes itself is the update check.

- **Session list:** Claude Code's `~/.claude/sessions` says which sessions run and whether they're busy, idle or waiting.
- **Hooks:** setup adds hooks to `~/.claude/settings.json` (and `~/.codex/hooks.json`) that run `peeku-hook`. It records only what Peeku shows (command, question, error, summary, branch, app and tab), never transcripts, into `~/Library/Application Support/Peeku/inbox`, which Peeku deletes after reading. It never answers or blocks anything and exits immediately. For Codex, type `/hooks` and trust Peeku's entries.
- **Usage:** Peeku asks `claude -p` and `codex app-server` for rate limits using their own sign-ins; it never reads credentials. If that fails, **Set Up…** reads Claude's numbers from its status line instead, keeping any status line you have.
- **Spend:** Peeku reads the session logs in `~/.claude/projects` and `~/.codex/sessions` and keeps only each reply's time, model and token counts, priced from a table built into the app. Nothing else is kept, saved or sent.
- **Commands:** saved in `~/Library/Application Support/Peeku/commands.json`, with each command's latest output next to it. They run only when you press Run, in your login shell, with the same access as your terminal.
- **Permissions:** *Automation* selects the right iTerm or Terminal tab. *Accessibility* finds the exact window and detects screen sharing.

Your settings files are backed up before any change.

## Using Peeku

| Shortcut | Action |
|---|---|
| ⌥⌘. | Show or hide the session manager on your agents |
| ⌥⌘. then 1–3 | Open the manager on Now, History or Usage (keep ⌥⌘ held) |
| ⌥⌘, | Show or hide Commands |
| ⌥⌘↓ | Next waiting agent |
| ↵ | Open the highlighted session |
| Esc | Fold the alert into the pill, or go back to Agents from Commands or Settings |
| ⌘1–9 | Open a row by number |

↵, Esc and ⌘1–9 work once the notch has focus. Peeku never takes the keyboard on its own.

**Goes quiet** (count only, no pop-up or sound) while your screen is shared or recorded, when **Quiet** is on, or for the session you're already looking at. In full screen it shrinks to a glow along the top edge.

**Settings** opens from the gear at the top right of the session manager (or **Settings…** in the menu bar). It covers appearance, login, updates, sounds per state, usage alerts, showing costs, utilities, which apps to watch, hooks and permissions.

<p align="center"><img src="docs/images/settings.png" width="420" alt="Peeku's settings inside the session manager, opened from the gear: appearance, notch or menu bar, open at login, update checks, notification options, staying quiet for the session in front, usage alerts, showing costs, a sound for each state, Quiet, which apps to watch, Claude Code hooks and permissions"></p>

## Updates and uninstall

Peeku updates itself through [Sparkle](https://sparkle-project.org), verifying each update's signature. Coming from Pip, the old name? Your data moves over automatically; allow the permissions once more.

To remove it, choose **Uninstall Peeku…** from the menu bar. It removes its hooks, restores your status line, deletes its data and moves itself to the Trash.

## Troubleshooting

- **"Peeku" Not Opened:** expected on first launch. See [The first time you open Peeku](#the-first-time-you-open-peeku).
- **A session shows but not why it's waiting:** install hooks from the menu bar, then restart that session.
- **No Codex sessions:** install Codex hooks, trust them with `/hooks`, and restart Codex.
- **No Claude usage:** the Usage tab says why. Update Claude Code, or choose **Set Up…** and run Claude Code in a terminal.
- **Opens the app but not the tab:** allow Peeku under Privacy & Security → Automation (iTerm, Terminal) or Accessibility (other apps).
- **Accessibility is on but Peeku asks again:** the permission belongs to an older build. Choose **Reset…** in Settings.
- **⌥⌘. does nothing:** another app uses it. Click the notch instead.
- **A command can't find `node`, `npm` or another tool:** Peeku runs commands in your login shell with your `.zshrc`, like a new terminal tab. Check that the command works in a new tab, or give the tool's full path.
- **A command's output has no colors:** expected. Commands see a plain terminal, so tools skip colors and spinners and the output stays readable.

## Building from source

Requires Xcode 26 (Swift 6.2).

```sh
git clone https://github.com/ahrefabhi/peeku.git && cd peeku
swift run Peeku                               # run (add --demo for Demo Mode)
scripts/bundle.sh && open build/Peeku.app     # build the app bundle
swift test                                    # unit tests
swift run Peeku --snapshot snapshots          # render every state to PNG
swift run Peeku --dump-sessions               # print the sessions Peeku sees
swift run Peeku --readme-images docs/images   # re-render README images
pngquant --quality=70-95 --strip --skip-if-larger --force --ext .png docs/images/*.png   # then shrink them (brew install pngquant)
PEEKU_HOME=/tmp/peeku swift run Peeku         # use a scratch data folder
```

| Path | What's there |
|---|---|
| `Sources/PeekuKit` | Model, queue, phase machine, session observation, hook installer, history, usage, quick commands. Unit-tested. |
| `Sources/PeekuHook` | `peeku-hook`, the collector hooks run. |
| `Sources/PeekuHookSchema` | The inbox record format. |
| `Sources/Peeku` | The app: notch, views, onboarding, settings, macOS integration. |
| `scripts` | Bundling, releasing, icon rendering. |

**Releasing:** `scripts/release.sh 0.2.0` does a dry run; add `--publish` to tag and upload. Sign with a stable certificate (`PEEKU_SIGN_IDENTITY` or one named **Peeku Code Signing**) so macOS permissions survive updates, and back up the Sparkle key (`generate_keys -x <file>`).

## Acknowledgements

Peeku started from a great idea: [Orbit](https://github.com/syedmazharaliraza/orbit), by [Syed Mazhar Ali Raza](https://github.com/syedmazharaliraza). Peeku wouldn't exist without it. Huge thanks to Syed for the inspiration and for building something so thoughtful. Go give Orbit a star.

Peeku works with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex](https://developers.openai.com/codex) but isn't affiliated with Anthropic or OpenAI.

## License

[MIT](LICENSE)
