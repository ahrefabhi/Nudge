# Peeku — launch video plan (0.7.0)

**Format:** 1920×1080, 30 fps, 31.3 s. That's longer than the usual 25 s, so the video can cover everything in 0.7.0: the notch loop, Commands, the new Skills utility and the new shortcuts. **Tone:** default — playful and clean, tipping to polished (it's a real tool, the creature carries the charm).

## Answers
- **What is it?** A tiny companion for your coding agents. It lives in your MacBook's notch or menu bar and tells you when a Claude Code or Codex session needs you.
- **Who's it for?** People who run several coding agents at once in iTerm, Terminal and VS Code and switch away while they work.
- **What sets it apart?** It lives *in the notch*: invisible while agents work, it drops out when one needs you and says why, and Open Session jumps to the exact tab. Since 0.7 it also manages every plugin and skill both agents load.
- **Best claim:** "One of them quietly stops to ask for permission. Ten minutes later you notice." (the product's own problem line)
- **Visual hook:** the notch — two glowing eyes peeking out of the camera cutout.
- **Real UI shown:** the site's working notch island and character (the project's own HTML/CSS/JS), the ghost terminal windows from the site, and the real SwiftUI renders from `docs/images` (skills-flow, manager, usage, commands, skills).
- **Share caption:** Peeku lives in your notch and drops out when Claude Code or Codex needs you. New in 0.7: Skills, every plugin and skill your agents load, in one place.

## Angle
The creature is still the hero, and the video is still the product loop: entry (agents working) → key action (Peeku drops out, Open Session) → result (you're in the right tab). Then the new part: Skills gets its own scene with a real install into one project, and a closing recap shows every panel with its shortcut.

## Visual identity
Site palette: bg `#0d0e12`, hero gradient `#1d2130`, ink `#060607`, text `#f5f5f7`; state colors amber `oklch(.83 .13 78)`, blue `oklch(.8 .12 250)`, red `oklch(.75 .15 25)`, green `oklch(.82 .14 152)`. SF Pro / SF Mono (system). Dot grid + glow orb that takes on the state color.

## Storyboard

The exact timeline is `const T` in comp/index.html and `T` in audio.py.

| # | Time | Scene | On-screen text |
|---|---|---|---|
| 1 | 0.0–3.2 | **Hook.** Dark desktop, four agent windows float in (payments-api, dashboard-v2, infra-terraform, docs-site). payments-api sits on its Bash permission prompt, caret blinking. | "One agent stopped to ask." → "Ten minutes later, you notice." |
| 2 | 3.2–7.3 | **Reveal.** Push in to the notch. Working: eyes glance, spinner "5". Peeku drops out with amber eyes; the notch springs open into the permission alert (`npm install stripe@17.2.0`). | "Meet Peeku. It lives in your notch." |
| 3 | 7.3–10.35 | **Open Session.** Cursor glides to Open Session, click; notch tucks away; toast "Switched to iTerm · Tab 1 · payments-api"; the iTerm window lights up. | "Open Session jumps to the exact tab." |
| 4 | 10.35–13.6 | **It tells you why.** Quick cuts in the notch: question (blue), error (red), finished (green). Glow follows. | "Questions. Errors. Finished runs." |
| 5 | 13.6–18.0 | **Commands.** A red FAILED alert (`EADDRINUSE`), then a blue INPUT alert (the port question). Cursor clicks Yes; toast "Storefront · running on localhost:3001". | "Your dev servers live there too." → "Answer their prompts in one click." |
| 6 | 18.3–23.3 | **New: Skills.** The Installed and Discover panels rise side by side. The camera eases in on playwright's install card, set to the payments-api project; the cursor clicks Install; the app's own notice appears: "Installed playwright. New Claude Code sessions will load it." | "New: Skills. Every plugin and skill, in one place." → "Install for everything, or just one project." |
| 7 | 23.6–27.8 | **Everything, one shortcut each.** Now, Usage, Commands and Skills panels rise in a row. Under each, its keycap presses in turn: ⌥⌘, · Usage · ⌥⌘. · ⌥⌘/. | "Your sessions, limits, commands and skills." → "One shortcut each. Set your own in Settings." |
| 8 | 28.1–31.3 | **Outro.** App icon, "Peeku", tagline, "New: Skills" badge, meta, URL. Peeku peeks out of the notch, happy. | "A tiny companion for your coding agents." / "For Claude Code and Codex · macOS 14+ · Open source" / "peeku.ahrefabhi.com" |

Transitions: dip through the background between 1→2, 5→6, 6→7 and 7→8 (no muddy crossfades); 2→5 stay in the same notch shot.

## Sound
Warm synth-pop bed, 100 BPM, F major (F–Dm–B♭–C), soft kick from scene 2, pluck arpeggio. SFX tuned to the key: soft "boop" when Peeku drops (C5→F5), a muted click on Open Session, airy filtered-noise swells on the dips, a small chime per mood in scene 4 (chord tones), the same for the command alerts in scene 5 with a click on Yes. In scene 6: a pluck per panel, a click on Install and a bright C6 + F6 when it's done. In scene 7: a pluck per panel and a soft tick per keycap. A gentle resolve on the logo. Effects sit under the music.
