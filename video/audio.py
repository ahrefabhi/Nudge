"""Music and sound effects for the Peeku video, synthesized as one piece. Writes out/audio.wav.

F major, 100 BPM (bar = 2.4 s), chords F - Dm - Bb - C. Effects use chord tones and share
the music's reverb, so they sit inside the track rather than on top of it.
"""
import os
import wave
import numpy as np

SR = 48000
DUR = 21.7
N = int(SR * DUR)
BEAT = 0.6
BAR = 4 * BEAT
rng = np.random.default_rng(7)

# Timeline: keep in step with `const T` in comp/index.html
T = dict(pushIn=3.2, drop1=4.5, alert1=5.15, click=8.45, close1=8.55, q=10.75, qAlert=11.35,
         err=12.35, fin=13.3, dip1=14.75, panels=15.05, dip2=18.15, outro=18.45, peekOutro=18.95)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def t_axis(n):
    return np.arange(n) / SR


def env(n, a, d, s=0.0, r=None):
    """Attack a s, then exponential decay with time constant d toward s."""
    t = t_axis(n)
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / d))
    if r:
        e *= np.clip((n / SR - t) / r, 0, 1)
    return e


def lowpass(x, cutoff):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (f / cutoff) ** 4)
    return np.fft.irfft(X, len(x))


def highpass(x, cutoff):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (cutoff / np.maximum(f, 1)) ** 4)
    return np.fft.irfft(X, len(x))


def put(bus, start, sig, gain=1.0):
    i = int(start * SR)
    if i >= len(bus):
        return
    j = min(len(bus), i + len(sig))
    bus[i:j] += sig[: j - i] * gain


def reverb(x, seconds=2.2, mix=1.0):
    n = int(SR * seconds)
    t = t_axis(n)
    ir = rng.standard_normal(n) * np.exp(-t / (seconds / 6.5))
    ir = lowpass(ir, 5200)
    ir[: int(SR * 0.012)] = 0  # a little predelay
    ir /= np.sqrt(np.sum(ir ** 2))
    m = len(x) + n
    y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[: len(x)]
    return y * mix


# ---------------------------------------------------------------------------
# Instruments
def pad_voice(freq, n):
    t = t_axis(n)
    out = np.zeros(n)
    for det in (-0.07, 0.0, 0.06):  # detuned saws, gently filtered
        f = freq * 2 ** (det / 12)
        ph = (t * f) % 1.0
        out += 2 * ph - 1
    return lowpass(out / 3, 2800)


def pluck(freq, dur=0.5, bright=5200):
    n = int(SR * dur)
    t = t_axis(n)
    s = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * 2 * freq * t) + 0.12 * np.sin(2 * np.pi * 3 * freq * t)
    return lowpass(s * env(n, 0.004, 0.16), bright)


def bell(freq, dur=1.6, bright=1.0):
    n = int(SR * dur)
    t = t_axis(n)
    s = (np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.55)
         + 0.35 * bright * np.sin(2 * np.pi * freq * 2.0 * t) * np.exp(-t / 0.3)
         + 0.12 * bright * np.sin(2 * np.pi * freq * 3.0 * t) * np.exp(-t / 0.16))
    return s * np.clip(t / 0.003, 0, 1)


def kick(dur=0.32):
    n = int(SR * dur)
    t = t_axis(n)
    f = 55 + 85 * np.exp(-t / 0.025)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / 0.11)


def hat(dur=0.06):
    n = int(SR * dur)
    return highpass(rng.standard_normal(n), 7000) * np.exp(-t_axis(n) / 0.014)


def tick(dur=0.05):
    """Muted woodblock tick for the 'waiting' intro."""
    n = int(SR * dur)
    t = t_axis(n)
    return (np.sin(2 * np.pi * 1760 * t) * 0.6 + np.sin(2 * np.pi * 2637 * t) * 0.25) * np.exp(-t / 0.009)


def glide(f0, f1, dur, glide_t):
    n = int(SR * dur)
    t = t_axis(n)
    f = f1 + (f0 - f1) * np.exp(-t / (glide_t / 3))
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) + 0.18 * np.sin(2 * ph)
    return s * env(n, 0.006, 0.12)


def whoosh(dur, peak):
    """Filtered noise that swells toward `peak` seconds and falls away."""
    n = int(SR * dur)
    t = t_axis(n)
    noise = rng.standard_normal(n)
    lo, hi = lowpass(noise, 900), lowpass(noise, 4200)
    rise = np.clip(t / peak, 0, 1)
    shape = np.where(t < peak, (t / peak) ** 2, np.exp(-(t - peak) / 0.18))
    return (lo * (1 - rise) + hi * rise) * shape


# ---------------------------------------------------------------------------
music = np.zeros(N)
sfx = np.zeros(N)
send = np.zeros(N)  # reverb send

# Chords: F, Dm, Bb, C (MIDI)
CHORDS = [[53, 57, 60, 65], [50, 57, 62, 65], [46, 53, 58, 62], [48, 55, 60, 64]]
ROOTS = [41, 38, 46, 48]
ARP = [[65, 69, 72, 69], [62, 65, 69, 65], [62, 65, 70, 65], [64, 67, 72, 67]]

bars = int(np.ceil(DUR / BAR))
for b in range(bars):
    t0 = b * BAR
    c = b % 4
    # Pad: every bar, swelling in
    n = int(SR * (BAR + 0.6))
    v = sum(pad_voice(hz(m), n) for m in CHORDS[c]) / 4
    v *= env(n, 0.5, 9.0, 1.0, r=0.6)
    level = 0.16 if t0 < T['pushIn'] else 0.2
    if t0 >= T['outro'] - 0.1:
        level = 0.18
    put(music, t0, v, level)
    put(send, t0, v, level * 0.4)

# Bass from the push-in: root on beats 1 and 3, sine + soft octave
for b in range(bars):
    t0 = b * BAR
    if t0 + BAR <= T['pushIn']:
        continue
    for k in (0, 2):
        tt = t0 + k * BEAT
        if tt < T['pushIn'] or tt > DUR - 1.0:
            continue
        n = int(SR * 1.1)
        f = hz(ROOTS[b % 4] - 12 if ROOTS[b % 4] > 44 else ROOTS[b % 4])
        tt_ax = t_axis(n)
        s = (np.sin(2 * np.pi * f * tt_ax) + 0.45 * np.sin(2 * np.pi * 2 * f * tt_ax) + 0.15 * np.sin(2 * np.pi * 3 * f * tt_ax)) * env(n, 0.01, 0.28, 0.05, r=0.2)
        put(music, tt, s, 0.11)

# Pluck arpeggio in 8ths from the reveal until the outro
step = BEAT / 2
tt = 0.0
i = 0
while tt < DUR:
    b = int(tt // BAR)
    if T['alert1'] - 0.3 <= tt < T['outro'] - 0.05:
        f = hz(ARP[b % 4][i % 4])
        s = pluck(f, 0.5)
        g = 0.11 if i % 2 == 0 else 0.08
        put(music, tt, s, g)
        put(send, tt, s, g * 0.8)
    tt += step
    i += 1

# Soft kick on the beat from the drop, a hat on the off-beats; both drop out on the dips
tt = 0.0
while tt < DUR:
    near_dip = any(abs(tt - T[k]) < 0.35 for k in ('dip1', 'dip2'))
    if T['drop1'] - 0.1 <= tt < T['outro'] - 0.1 and not near_dip:
        put(music, tt, kick(), 0.17)
        put(music, tt + BEAT / 2, hat(), 0.07)
    tt += BEAT

# Waiting: a quiet clock tick in the intro, on the beat, fading as the camera moves
tt = 0.0
while tt < T['pushIn'] + 0.2:
    fade = 1 - np.clip((tt - 2.4) / 1.0, 0, 1)
    put(sfx, tt, tick(), 0.12 * fade)
    put(send, tt, tick(), 0.05 * fade)
    tt += BEAT

# ---------------------------------------------------------------------------
# Effects
def boop(start, up=True, gain=0.22):
    s = glide(hz(72), hz(77), 0.4, 0.09) if up else glide(hz(77), hz(72), 0.35, 0.08)
    put(sfx, start, s, gain)
    put(send, start, s, gain * 0.6)


# Peeku drops out of the notch
boop(T['drop1'] + 0.02)
# The notch opens: an airy swell and a soft chord-tone bell (A5)
put(sfx, T['alert1'] - 0.25, whoosh(0.7, 0.3), 0.05)
put(sfx, T['alert1'] + 0.08, bell(hz(81), 1.4, 0.6), 0.09)
put(send, T['alert1'] + 0.08, bell(hz(81), 1.4, 0.6), 0.06)

# Open Session: a muted click, then the notch tucks away
n = int(SR * 0.03)
click = lowpass(rng.standard_normal(n), 3000) * np.exp(-t_axis(n) / 0.004) * 0.6 + np.sin(2 * np.pi * 1400 * t_axis(n)) * np.exp(-t_axis(n) / 0.006)
put(sfx, T['click'], click, 0.28)
boop(T['close1'] + 0.05, up=False, gain=0.12)
# The exact tab lights up: bright bell on C6
put(sfx, T['close1'] + 0.25, bell(hz(84), 1.3, 0.5), 0.07)
put(send, T['close1'] + 0.25, bell(hz(84), 1.3, 0.5), 0.05)

# Moods: question drops and opens, then error, then finished
boop(T['q'] + 0.02, gain=0.18)
put(sfx, T['qAlert'] - 0.2, whoosh(0.6, 0.25), 0.035)
put(sfx, T['qAlert'] + 0.05, bell(hz(81), 1.2, 0.6), 0.08)            # question: A5
put(sfx, T['err'] + 0.02, bell(hz(74), 1.0, 0.8), 0.075)              # error: D5 over Bb
put(sfx, T['err'] + 0.02, bell(hz(77), 1.0, 0.8), 0.05)               # + F5
put(sfx, T['fin'] + 0.02, bell(hz(84), 1.4, 0.5), 0.075)              # finished: C6 ...
put(sfx, T['fin'] + 0.14, bell(hz(88), 1.4, 0.5), 0.06)               # ... E6, a little lift
for k in ('qAlert', 'err', 'fin'):
    put(send, T[k] + 0.02, bell(hz(81 if k == 'qAlert' else 74 if k == 'err' else 84), 1.2, 0.5), 0.05)

# Dips: airy swells through the background
for k in ('dip1', 'dip2'):
    w = whoosh(1.0, 0.35)
    put(sfx, T[k] - 0.3, w, 0.06)
    put(send, T[k] - 0.3, w, 0.05)
# Panels rise: two soft plucks, one per panel
put(sfx, T['panels'] + 0.05, pluck(hz(77), 0.7, 2600), 0.08)
put(sfx, T['panels'] + 0.23, pluck(hz(81), 0.7, 2600), 0.08)

# Outro: the logo lands on an F major bell chord; Peeku peeks out with a happy boop
for j, m in enumerate((77, 81, 84, 89)):
    b = bell(hz(m), 3.0, 0.4)
    put(sfx, T['outro'] + 0.12 + j * 0.06, b, 0.06)
    put(send, T['outro'] + 0.12 + j * 0.06, b, 0.07)
boop(T['peekOutro'] + 0.02, gain=0.13)
# Final pad: a long F chord that fades out
n = int(SR * (DUR - T['outro']))
v = sum(pad_voice(hz(m), n) for m in (53, 57, 60, 65, 69)) / 5 * env(n, 0.4, 20, 1.0, r=1.6)
put(music, T['outro'], v, 0.1)

# ---------------------------------------------------------------------------
# Mix: effects duck the music a touch, everything shares one room
duck = np.ones(N)
for k in ('drop1', 'alert1', 'click', 'q', 'qAlert', 'err', 'fin'):
    i = int(T[k] * SR)
    m = int(0.5 * SR)
    j = min(N, i + m)
    duck[i:j] = np.minimum(duck[i:j], 1 - 0.18 * np.exp(-t_axis(j - i) / 0.18))
mix = music * duck + sfx + reverb(send, 2.2, 0.55)
mix = highpass(mix, 45)

# Fade in/out, soft limit, normalize to -1 dBFS
t = t_axis(N)
mix *= np.clip(t / 0.08, 0, 1) * np.clip((DUR - t) / 1.2, 0, 1)
mix = np.tanh(mix * 1.6) / 1.6
mix *= 10 ** (-1 / 20) / np.max(np.abs(mix))

# Stereo: a slight width from a short Haas delay on the reverb-heavy side
d = int(0.011 * SR)
left = mix
right = np.concatenate([mix[:d], mix[:-d]]) * 0.25 + mix * 0.75
st = np.stack([left, right], axis=1)
st *= 10 ** (-1 / 20) / np.max(np.abs(st))
pcm = (st * 32767).astype(np.int16)
os.makedirs(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out'), exist_ok=True)
with wave.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out', 'audio.wav'), 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('wrote out/audio.wav', DUR, 's')
