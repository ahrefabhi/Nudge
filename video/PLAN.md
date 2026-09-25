# Peeku — launch video plan

**Format:** 1920×1080, 30 fps, 21.7 s. **Tone:** default — playful and clean, tipping to polished (it's a real tool, the creature carries the charm).

## Answers
- **What is it?** A tiny creature that lives in your MacBook's notch and tells you when a Claude Code or Codex session needs you.
- **Who's it for?** People who run several coding agents at once in iTerm, Terminal and VS Code and switch away while they work.
- **What sets it apart?** It lives *in the notch*: invisible while agents work, drops out when one needs you, says why (the exact command/question/error), and Open Session jumps to the exact tab.
- **Best claim:** "One of them quietly stops to ask for permission. Ten minutes later you notice." (the product's own problem line)
- **Visual hook:** the notch — two glowing eyes peeking out of the camera cutout.
- **Real UI shown:** the site's working notch island + character (the project's own HTML/CSS/JS), the ghost terminal windows from the site, and the real SwiftUI renders from `docs/images` (manager, usage).
- **Share caption:** Peeku lives in your MacBook's notch and drops out when a Claude Code or Codex session needs you.

## Angle
The creature is the hero. Start on the pain (agents waiting unseen), then the notch comes alive: eyes glance, Peeku drops out, the notch opens into the alert. The video *is* the product loop: entry (agents working) → key action (Peeku drops out, Open Session) → result (you're in the right tab).

## Visual identity
Site palette: bg `#0d0e12`, hero gradient `#1d2130`, ink `#060607`, text `#f5f5f7`; state colors amber `oklch(.83 .13 78)`, blue `oklch(.8 .12 250)`, red `oklch(.75 .15 25)`, green `oklch(.82 .14 152)`. SF Pro / SF Mono (system). Dot grid + glow orb that takes on the state color.

## Storyboard

Times are the first plan; the exact timeline is `const T` in comp/index.html (scene 4 later grew by 0.7 s, and everything after it moved).
| # | Time | Scene | On-screen text |
|---|---|---|---|
| 1 | 0.0–3.2 | **Hook.** Dark desktop, four agent windows float in (payments-api, dashboard-v2, infra-terraform, docs-site). payments-api sits on its Bash permission prompt, caret blinking. | "One agent stopped to ask." → "Ten minutes later, you notice." |
| 2 | 3.2–7.4 | **Reveal.** Push in to the notch. Working: eyes glance, spinner "5". Peeku drops out with amber eyes; the notch springs open into the permission alert (`npm install stripe@17.2.0`). | "Meet Peeku. It lives in your notch." |
| 3 | 7.4–10.6 | **Open Session.** Cursor glides to Open Session, click; notch tucks away; toast "Switched to iTerm · Tab 1 · payments-api"; the iTerm window lights up. | "Open Session jumps to the exact tab." |
| 4 | 10.6–14.2 | **It tells you why.** Quick cuts in the notch: question (blue), error (red), finished (green). Glow color follows. | "Questions. Errors. Finished runs." |
| 5 | 14.2–17.6 | **Real app.** Manager (Now) and Usage panels rise side by side. | "Every session, and your Claude and Codex limits." |
| 6 | 17.6–21.0 | **Outro.** App icon, "Peeku", tagline, meta. | "A tiny companion in your notch." / "For Claude Code and Codex · macOS 14+ · Open source" / "peeku.ahrefabhi.com" |

Transitions: dip through background between 1→2 and 4→5 (no muddy crossfades); 2→3→4 stay in the same notch shot.

## Sound
Warm synth-pop bed, 100 BPM, F major (F–Dm–B♭–C), soft kick from scene 2, pluck arpeggio. SFX tuned to the key: soft "boop" when Peeku drops (C5→F5), a muted click on Open Session, airy filtered-noise swells on the dips, a small chime per mood in scene 4 (chord tones), a gentle resolve on the logo. Effects sit under the music.
