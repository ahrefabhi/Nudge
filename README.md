# Pip

A macOS notch companion for Claude Code sessions. Idle, Pip is invisible inside the notch. When a session needs you, Pip drops out, the notch expands into a notification, and **Open Session** takes you to it.

Built from the "Pip — Notch Session Companion" design handoff (kept outside this repository).

## How Pip sees sessions

- **Claude's session registry** (`~/.claude/sessions/*.json`) lists every running session and whether it's busy, idle or waiting. Pip reads it with no setup at all.
- **Claude Code hooks** say *why* a session waits: the command that needs permission, the question and its choices, the error. Install them from the 👀 menu → **Install Claude Code Hooks…**. That adds entries to `~/.claude/settings.json` that run `~/Library/Application Support/Pip/bin/pip-hook`, backs up the file first, and leaves every other setting and hook alone. **Remove Claude Code Hooks…** takes out only Pip's entries.

The collector only records what happened. It never answers, approves or blocks anything, and it drops everything Pip doesn't show, such as transcript paths. Records land in `~/Library/Application Support/Pip/inbox` and are deleted as soon as Pip reads them.

**Staying out of the way:** when the menu bar is hidden (a full-screen app, or auto-hide), Pip shrinks to a 4px accent glow on the top edge, and only while something is waiting. Click it for the alert; reveal the menu bar and Pip returns. While the menu bar is hidden, Zoom is sharing your screen, or **Quiet** (menu bar → Quiet → 1 hour / until tomorrow) is on, new waiting sessions only update the count; the notch never expands on its own, and an open alert folds away. macOS gives apps no way to read Focus modes without a special entitlement, so use Quiet for those.

The manager's **History** tab logs the week's moments: when a session needed you and how long it took to answer, errors and when they cleared, finished runs and how long they took, and new tasks. It's kept in `~/Library/Application Support/Pip/history.json`. Rows reopen their session while it's still running.

Any session can be opened, not just one that's waiting: in the session manager, click a working, finished or idle row (it shows **Open** on hover). **Open Session** selects the exact iTerm tab (by its session id) or Terminal tab (by tty), opens the session's folder in VS Code (which focuses the window that already has it), or brings the Claude app forward. The first time, macOS asks whether Pip may control iTerm or Terminal.

## Status

Done: the notch UI, the Pip character, the phase machine, real sessions from the registry and hooks, focusing sessions with the focus ring, onboarding, history, staying out of the way, settings, remembering state across restarts, and light mode, updates through Sparkle, an app icon, and uninstalling. Next: Developer ID signing and notarization.

## Run

Requires macOS 14+ and Xcode 26 (Swift 6.2).

```sh
swift run Pip            # run from the terminal
scripts/bundle.sh        # build build/Pip.app
open build/Pip.app
```

On first launch a three-step setup window introduces Pip, shows which apps your sessions run in (turn any off to ignore its sessions), and sets up hooks, Accessibility and Automation. **Set Up Pip…** in the menu reopens it.

**Light mode:** with a light system appearance (or **Appearance → Light** in Settings), alerts and the session manager move into a frosted light panel below the notch, and Pip hangs from the notch between them. The notch itself stays black, and so does everything that lives in it (working, peek, pill).

**Settings…** (👀 menu, ⌘,) covers appearance, opening at login, folding alerts after 8 seconds, popping up when a session finishes, Quiet, which apps to watch, hooks and permissions, and a list of shortcuts. What Pip learned from hooks, such as a question's choices, is saved to `~/Library/Application Support/Pip/sessions.json`, so it survives a restart.

The 👀 menu bar item installs or removes hooks, chooses which apps to watch, opens the session manager, and toggles **Demo Mode**, which swaps in the handoff's sample sessions and a **Simulate** submenu. `swift run Pip --demo` starts in Demo Mode.

| Shortcut | Action |
|---|---|
| ⌥⌘. | Toggle the session manager |
| ⌥⌘↓ | Cycle the queue |
| ↵ / Esc | Open the focused session / fold the alert (once the island has focus) |
| ⌘1–9 | Open row N: any session in the manager, a waiting one in an alert |

## Test

```sh
swift test
swift run Pip --snapshot snapshots   # render the character sheet and every island phase to PNG
swift run Pip --dump-sessions        # print the sessions Pip sees right now, then exit
scripts/make-icon.sh                 # re-render Resources/AppIcon.icns from PipView
PIP_HOME=/tmp/pip swift run Pip      # use a scratch data folder instead of ~/Library/Application Support/Pip
```

## Updates and releases

Pip updates itself with [Sparkle](https://sparkle-project.org). Each GitHub release carries `Pip-<version>.zip` and an `appcast.xml`; Pip reads `https://github.com/ahrefabhi/pip/releases/latest/download/appcast.xml` once a day (**Check for Updates…** in the menu, or Settings), and installs a download only if its EdDSA signature matches the public key in `Resources/Info.plist`.

```sh
scripts/release.sh 0.2.0            # dry run: builds, zips, signs, writes appcast.xml into build/release/v0.2.0
scripts/release.sh 0.2.0 --publish  # also pushes, tags v0.2.0 and uploads both files to a GitHub release
```

The release script needs a clean working tree. The build number is the commit count, so it always grows. The private signing key lives in your login Keychain (created once with Sparkle's `generate_keys`); export a backup with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key` and keep it somewhere safe, since without it you can't ship updates to existing installs.

Releases are ad-hoc signed for now, so the first launch needs right-click → **Open**, and macOS may ask for Accessibility and Automation again after an update. A Developer ID (Apple Developer Program) removes both.

## Uninstalling

**Uninstall Pip…** (menu bar or Settings) removes Pip's hooks from `~/.claude/settings.json`, deletes `~/Library/Application Support/Pip` (collector, inbox, history, saved sessions), turns off opening at login, clears Pip's settings and caches, and moves the app to the Trash. Backups Pip made of your Claude settings stay in `~/.claude`.

If Pip is just dragged to the Trash, its hooks keep running, but the collector stops writing once 10,000 events are waiting unread (about 5 MB), so it can't fill the disk. Remove the leftover entries by reinstalling and choosing Uninstall, or delete the handlers whose command is `…/Application Support/Pip/bin/pip-hook` from `~/.claude/settings.json`.

## Layout

- `Sources/PipHookSchema`: the inbox record format, shared by the collector and the app.
- `Sources/PipHook`: `pip-hook`, the collector Claude Code runs for each hook event.
- `Sources/PipKit`: session model, attention queue, phase machine, and observation (inbox, registry, reducer, projection, hook installer). No UI; unit-tested.
- `Sources/Pip`: the AppKit/SwiftUI app.
  - `Notch/`: the non-activating panel, notch geometry, pointer pass-through and keys.
  - `Island/`: the island shape, per-phase sizes and the root view.
  - `Character/`: Pip, drawn from shapes, with the handoff's keyframes.
  - `Views/`: wings, peek, pill, alert cards and the manager.
  - `Design/`: tokens (OKLCH accents converted exactly) and motion.
  - `System/`: hotkeys, the menu bar item, hook setup, session opening and Demo Mode.
