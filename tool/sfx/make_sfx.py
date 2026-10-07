"""Synthesises the app's small sound effects into assets/sfx/ (all original:
no samples, no Microsoft sounds, just numpy).

    python3 tool/sfx/make_sfx.py          (needs numpy)

  deck_key_down / deck_key_up   projector piano keys: the press (a heavier
                                clunk as the key bottoms and latches) and
                                the release (a lighter, higher spring tick)
  w98_click                     soft mouse click for Windows 98 buttons/menus
  w98_ding                      gentle bell for message boxes
  w98_error                     two-tone "bong" for error boxes
  w98_exit                      short descending chime when leaving Win98
  w98_shutdown                  a few seconds of warm pad for Shut Down
  crt_off                       CRT switching off: pop, whine, crackle
  w98_login                     a gentle rising chime when Win98 opens
  zoom_motor                    a small geared lens motor, looped while
                                the zoom moves (seamless 1 s loop)
"""
import os
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SR = 44100
rng = np.random.default_rng(98)


def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack, decay):
    """Exponential decay with a short linear attack (seconds)."""
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    return a * np.exp(-x / decay)


def noise(seconds):
    return rng.standard_normal(int(SR * seconds))


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def pad(x, seconds):
    return np.concatenate([x, np.zeros(int(SR * seconds))])


def place(dst, src, at):
    i = int(SR * at)
    n = min(len(src), len(dst) - i)
    dst[i:i + n] += src[:n]
    return dst


def reverb(x, mix=0.25, room=0.6):
    """A few feedback combs: enough to put a sound in a room."""
    out = np.copy(x)
    for d, g in ((0.0297, 0.75), (0.0371, 0.72), (0.0411, 0.70), (0.0437, 0.68)):
        k = int(SR * d)
        y = np.copy(x)
        for i in range(k, len(y)):
            y[i] += g * room * y[i - k]
        out += mix * y / 4
    return out


def bell(freq, seconds, decay, partials=((1, 1.0), (2.01, 0.35), (3.02, 0.12))):
    x = t(seconds)
    s = sum(a * np.sin(2 * np.pi * freq * m * x) * np.exp(-x / (decay / m ** 0.7)) for m, a in partials)
    return s * np.clip(x / 0.004, 0, 1)


def pad_note(freq, seconds, attack=0.25, release=0.8):
    x = t(seconds)
    s = (np.sin(2 * np.pi * freq * x) + 0.3 * np.sin(2 * np.pi * freq * 2 * x + 0.5)
         + 0.12 * np.sin(2 * np.pi * freq * 3 * x + 1.1))
    s *= 1 + 0.004 * np.sin(2 * np.pi * 4.5 * x)  # a little life
    e = np.minimum(np.clip(x / attack, 0, 1), np.clip((seconds - x) / release, 0, 1))
    return s * e


def save(name, x, peak=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    path = os.path.join(ROOT, 'assets', 'sfx', f'{name}.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())
    print(f'{name}.wav  {len(x) / SR:.2f}s')


def deck_key_down():
    out = np.zeros(int(SR * 0.16))
    click = bandpass(noise(0.006), 1500, 6000) * env(int(SR * 0.006), 0.0003, 0.0015)
    thud = np.sin(2 * np.pi * 95 * t(0.07)) * env(int(SR * 0.07), 0.001, 0.018)
    latch = bandpass(noise(0.008), 2500, 8000) * env(int(SR * 0.008), 0.0002, 0.002)
    body = bandpass(noise(0.05), 300, 1800) * env(int(SR * 0.05), 0.001, 0.008)
    place(out, click, 0.0)
    place(out, 0.9 * thud, 0.004)
    place(out, 0.5 * body, 0.004)
    place(out, 0.55 * latch, 0.032)
    return reverb(out, mix=0.12, room=0.4)


def deck_key_up():
    out = np.zeros(int(SR * 0.12))
    tick = bandpass(noise(0.005), 3000, 9000) * env(int(SR * 0.005), 0.0002, 0.0012)
    spring = np.sin(2 * np.pi * 2300 * t(0.05)) * env(int(SR * 0.05), 0.0005, 0.007)
    knock = np.sin(2 * np.pi * 180 * t(0.03)) * env(int(SR * 0.03), 0.0008, 0.006)
    place(out, tick, 0.0)
    place(out, 0.18 * spring, 0.002)
    place(out, 0.4 * knock, 0.003)
    return reverb(out, mix=0.1, room=0.35)


def w98_click():
    out = np.zeros(int(SR * 0.05))
    place(out, bandpass(noise(0.004), 2000, 7000) * env(int(SR * 0.004), 0.0002, 0.0008), 0)
    place(out, 0.5 * bandpass(noise(0.004), 1200, 5000) * env(int(SR * 0.004), 0.0002, 0.0008), 0.018)
    return out


def w98_ding():
    return reverb(pad(bell(1318.5, 0.6, 0.18), 0.1), mix=0.2)


def w98_error():
    out = np.zeros(int(SR * 0.75))
    place(out, bell(523.25, 0.6, 0.16, ((1, 1), (2.0, 0.4), (2.76, 0.2))), 0.0)
    place(out, 0.85 * bell(392.0, 0.6, 0.2, ((1, 1), (2.0, 0.4), (2.76, 0.2))), 0.11)
    return reverb(out, mix=0.22)


def w98_exit():
    out = np.zeros(int(SR * 1.3))
    for i, f in enumerate((783.99, 587.33, 392.0)):
        place(out, (0.9 - 0.15 * i) * bell(f, 0.9, 0.3), i * 0.16)
    return reverb(out, mix=0.3, room=0.7)


def w98_shutdown():
    """An original, slow, falling progression: a pad chord under a soft
    bell line that settles on the tonic."""
    out = np.zeros(int(SR * 4.6))
    chords = [((261.63, 329.63, 392.0), 0.0), ((220.0, 277.18, 329.63), 1.1), ((174.61, 220.0, 261.63), 2.2)]
    for notes, at in chords:
        for f in notes:
            place(out, 0.22 * pad_note(f, 2.1, attack=0.35, release=1.0), at)
    melody = [(1046.5, 0.05), (783.99, 0.55), (880.0, 1.15), (659.25, 1.65), (698.46, 2.25), (523.25, 2.8)]
    for f, at in melody:
        place(out, 0.35 * bell(f, 1.6, 0.45), at)
    fade = np.clip((len(out) / SR - t(len(out) / SR)) / 1.2, 0, 1)
    return reverb(out * fade, mix=0.35, room=0.75)


def crt_off():
    out = np.zeros(int(SR * 0.9))
    pop = lowpass(noise(0.03), 900) * env(int(SR * 0.03), 0.0005, 0.008)
    thump = np.sin(2 * np.pi * 60 * t(0.15)) * env(int(SR * 0.15), 0.002, 0.04)
    x = t(0.7)
    whine = np.sin(2 * np.pi * (9000 - 4000 * x) * x) * 0.05 * np.exp(-x / 0.25)
    crackle = (rng.random(len(x)) > 0.995) * rng.standard_normal(len(x)) * np.exp(-x / 0.3)
    place(out, pop, 0.0)
    place(out, 0.8 * thump, 0.0)
    place(out, whine, 0.02)
    place(out, 0.5 * highpass(crackle, 1500), 0.05)
    return out


def w98_login():
    """A soft swell and four rising bell notes: hello, not fanfare."""
    out = np.zeros(int(SR * 2.4))
    for f in (261.63, 392.0):
        place(out, 0.18 * pad_note(f, 2.2, attack=0.5, release=1.2), 0.0)
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        place(out, (0.5 + 0.1 * i) * bell(f, 1.4, 0.4), 0.12 + i * 0.17)
    return reverb(out, mix=0.32, room=0.7)


def zoom_motor():
    """Whine + gear ripple + a little brush noise. Every partial is a whole
    number of cycles per second and the noise is cross-faded, so the 1 s
    file loops without a click."""
    x = t(1.0)
    whine = (np.sin(2 * np.pi * 620 * x) + 0.5 * np.sin(2 * np.pi * 1240 * x + 0.7)
             + 0.25 * np.sin(2 * np.pi * 1860 * x + 1.9) + 0.15 * np.sin(2 * np.pi * 3100 * x))
    ripple = 1 + 0.35 * np.sin(2 * np.pi * 42 * x)  # gear teeth
    hiss = bandpass(noise(1.2), 900, 5000)
    n = len(x)
    fade = int(SR * 0.2)
    loop = hiss[:n].copy()
    w = np.linspace(0, 1, fade)
    loop[:fade] = loop[:fade] * w + hiss[n:n + fade] * (1 - w)
    return 0.6 * whine * ripple + 0.5 * loop


if __name__ == '__main__':
    save('deck_key_down', deck_key_down())
    save('deck_key_up', deck_key_up())
    save('w98_click', w98_click(), peak=0.6)
    save('w98_ding', w98_ding(), peak=0.7)
    save('w98_error', w98_error(), peak=0.75)
    save('w98_exit', w98_exit(), peak=0.7)
    save('w98_shutdown', w98_shutdown(), peak=0.75)
    save('crt_off', crt_off(), peak=0.8)
    save('zoom_motor', zoom_motor(), peak=0.5)
    save('w98_login', w98_login(), peak=0.7)
