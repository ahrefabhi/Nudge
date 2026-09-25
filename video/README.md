# Launch video

The source of the README's launch video: a 26.7-second, 1920×1080 clip of the notch coming alive, Open Session, the moods, a failed command and a command asking which port to use, the Now, Usage and Commands panels, and the outro. [PLAN.md](PLAN.md) has the storyboard.

```sh
video/render.sh        # writes video/out/peeku.mp4 and video/out/poster.jpg
```

It needs node, python3 and ffmpeg. The first run installs Playwright and numpy inside `video/`. A render takes a few minutes.

## How it works

- **[comp/index.html](comp/index.html)** is the whole video as one page. `window.seek(t)` draws the frame at `t` seconds, so every frame is a pure function of time. It reuses the site: [docs/site.css](../docs/site.css) for the notch, windows and colors, a copy of the character from [docs/site.js](../docs/site.js), and the app renders in [docs/images](../docs/images). Re-rendering the README images (`swift run Peeku --readme-images docs/images`) updates the panels in the video too.
- **[capture.js](capture.js)** opens the page in headless Chromium and screenshots each frame into ffmpeg.
- **[audio.py](audio.py)** synthesizes the music and sound effects together, timed to the same timeline.

## Changing it

1. Edit the scenes and the `T` timeline in `comp/index.html`. If a time moves, change it in `audio.py` too.
2. Check stills from each scene and mid-transition before a full render:
   ```sh
   cd video && node capture.js stills 2.6 6.5 9.8 13.8 16.0 17.45 18.4 21.6 25.5   # out/stills/
   ```
3. Run `video/render.sh`, optionally with the poster time (default 21.6 s, the three panels).

To put a new video in the README, drag `peeku.mp4` into a GitHub comment box to get a `user-attachments` link, and swap it into the README.
