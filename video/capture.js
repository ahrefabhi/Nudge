// Renders comp/index.html frame by frame; each frame is a pure function of time (window.seek).
// node capture.js stills 0.5 4.8 ...   -> out/stills/t-<time>.png, for checking scenes
// node capture.js video out/video.mp4  -> every frame at 30 fps, piped to ffmpeg (no audio)
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const FPS = 30;
(async () => {
  const [mode, ...rest] = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(__dirname, 'comp/index.html'));
  await page.evaluate(() => window.ready);
  const duration = await page.evaluate(() => window.DURATION);

  const shot = async (t) => {
    await page.evaluate((t) => window.seek(t), t);
    return page.screenshot({ type: 'png' });
  };

  if (mode === 'stills') {
    const dir = path.join(__dirname, 'out', 'stills');
    fs.mkdirSync(dir, { recursive: true });
    for (const t of rest.map(Number)) {
      fs.writeFileSync(path.join(dir, `t-${t.toFixed(2)}.png`), await shot(t));
    }
  } else if (mode === 'video') {
    const out = rest[0];
    const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
      '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
    const frames = Math.round(duration * FPS);
    for (let f = 0; f < frames; f++) {
      const buf = await shot(f / FPS);
      if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
      if (f % 60 === 0) process.stdout.write(`frame ${f}/${frames}\n`);
    }
    ff.stdin.end();
    await new Promise((r) => ff.on('close', r));
  }
  await browser.close();
})();
