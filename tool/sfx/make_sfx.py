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
  shutter_digital               a compact's shutter key: quiet, deep click
  shutter_film                  a mechanical shutter (two-part clack) and
                                the advance lever ratcheting back
  shutter_run                   Super 8 run button: a soft latch clunk
  cork_swoosh                   the framed corkboard sliding in: a deep,
                                woody whoosh
  cork_thud                     the board landing against its stop
  game_*                        Win98 games: bricks (bop, blip, lose, win),
                                cards (snap, riffle), mines (boom),
                                pinball (flipper, bumper, chime, warp,
                                launch, drain, start-up tune, sling, drop)
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


# Playback level of each sound, baked into the file (the app plays them at
# full scale). Keep them low: these sit under everything else on the phone.
LEVELS = {
    'cork_swoosh': 0.042,
    'cork_thud': 0.1575,
    'deck_key_down': 0.0963,
    'deck_key_up': 0.0788,
    'shutter_digital': 0.042,
    'shutter_film': 0.042,
    'shutter_run': 0.042,
    'w98_click': 0.0525,
    'w98_ding': 0.0525,
    'w98_error': 0.0612,
    'w98_login': 0.0525,
    'w98_exit': 0.0525,
    'w98_shutdown': 0.07,
    'crt_off': 0.0788,
    'game_bop': 0.035,
    'game_blip': 0.035,
    'game_lose': 0.042,
    'game_win': 0.042,
    'card_snap': 0.0525,
    'card_riffle': 0.0525,
    'mine_boom': 0.0525,
    'pin_flipper': 0.049,
    'pin_bumper': 0.035,
    'pin_chime': 0.035,
    'pin_sling': 0.035,
    'pin_drop': 0.042,
    'pin_warp': 0.035,
    'pin_launch': 0.042,
    'pin_drain': 0.042,
    'pin_start': 0.042,
    'zoom_motor': 0.021,
}


def save(name, x, peak=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak * LEVELS.get(name, 0.05)
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


def shutter_digital():
    out = np.zeros(int(SR * 0.14))
    thud = np.sin(2 * np.pi * 75 * t(0.06)) * env(int(SR * 0.06), 0.001, 0.014)
    click = lowpass(bandpass(noise(0.006), 600, 3500), 2500) * env(int(SR * 0.006), 0.0004, 0.0016)
    place(out, thud, 0.0)
    place(out, 0.6 * click, 0.0)
    place(out, 0.35 * click, 0.045)  # the key coming back up
    return out


def shutter_film():
    out = np.zeros(int(SR * 0.42))
    def clack(level, lo, hi):
        return level * bandpass(noise(0.012), lo, hi) * env(int(SR * 0.012), 0.0003, 0.0025)
    place(out, clack(1.0, 1200, 7000), 0.0)             # first curtain
    place(out, 0.5 * np.sin(2 * np.pi * 140 * t(0.03)) * env(int(SR * 0.03), 0.001, 0.008), 0.0)
    place(out, clack(0.8, 1500, 8000), 0.028)           # second curtain
    for i in range(7):                                  # advance lever ratchet
        place(out, clack(0.32 - 0.02 * i, 2500, 9000), 0.12 + i * 0.026)
    place(out, clack(0.5, 900, 5000), 0.31)             # lever home
    return reverb(out, mix=0.08, room=0.3)


def shutter_run():
    out = np.zeros(int(SR * 0.2))
    place(out, np.sin(2 * np.pi * 110 * t(0.08)) * env(int(SR * 0.08), 0.001, 0.02), 0.0)
    place(out, 0.7 * bandpass(noise(0.01), 700, 4000) * env(int(SR * 0.01), 0.0005, 0.002), 0.0)
    place(out, 0.4 * bandpass(noise(0.008), 1500, 6000) * env(int(SR * 0.008), 0.0005, 0.0015), 0.05)
    return out


def cork_swoosh():
    x = t(0.9)
    n = len(x)
    # A low, breathy sweep (filtered noise rising then falling in pitch),
    # lasting as long as the board takes to slide in.
    raw = noise(0.9)
    sweep = np.zeros(n)
    cut = 220 + 760 * np.sin(np.pi * np.clip(x / 0.85, 0, 1))
    acc = 0.0
    for i in range(n):
        a = np.exp(-2 * np.pi * cut[i] / SR)
        acc = (1 - a) * raw[i] + a * acc
        sweep[i] = acc
    shape = np.sin(np.pi * np.clip(x / 0.85, 0, 1)) ** 1.5
    return reverb(sweep * shape, mix=0.12, room=0.4)


def resonator(x, freq, q):
    """Two-pole resonant bandpass (a struck mode of a solid body)."""
    w = 2 * np.pi * freq / SR
    r = np.exp(-w / (2 * q))
    a1, a2 = -2 * r * np.cos(w), r * r
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    for i, v in enumerate(x):
        y0 = (1 - r) * v - a1 * y1 - a2 * y2
        y[i] = y0
        y2, y1 = y1, y0
    return y


def cork_thud():
    # A heavy framed board stopping against wood: a short, soft knock
    # (a few milliseconds of filtered noise) rings a handful of low,
    # inharmonic, heavily damped body modes, under a dull low thump. No
    # pitched tones: what makes it wood rather than electronic is that every
    # mode is noise-excited and dies within a few tens of milliseconds.
    n = int(SR * 0.35)
    hit = np.zeros(n)
    k = int(SR * 0.006)
    hit[:k] = lowpass(noise(0.006), 1800) * np.hanning(2 * k)[k:] ** 0.5
    out = np.zeros(n)
    # Modes sit where a phone speaker can play them (it can't do much below
    # ~200 Hz, so a 'heavy' thud there is silent on the phone).
    for f, q, g in ((175, 6, 0.55), (262, 8, 1.0), (395, 9, 0.85), (590, 10, 0.55), (870, 12, 0.3),
                    (1310, 14, 0.14)):
        out += g * resonator(hit, f, q)
    out /= np.max(np.abs(out)) + 1e-9
    # Dull low thump: the mass of the board.
    x = t(0.35)
    thump = np.sin(2 * np.pi * 110 * x) * np.exp(-x / 0.04) * np.clip(x / 0.003, 0, 1)
    out = out + 0.35 * thump
    # A touch of contact grit on the attack.
    grit = bandpass(noise(0.01), 600, 3000) * env(int(SR * 0.01), 0.0003, 0.003)
    place(out, 0.25 * grit / (np.max(np.abs(grit)) + 1e-9), 0.0)
    out = lowpass(out, 3200) * np.exp(-x / 0.11)
    return reverb(out, mix=0.08, room=0.25)


def square(freq, seconds, duty=0.5):
    x = t(seconds)
    f = np.broadcast_to(freq, x.shape) if np.ndim(freq) else np.full(x.shape, float(freq))
    phase = np.cumsum(f) / SR
    return np.where((phase % 1) < duty, 1.0, -1.0)


def tone_env(n, attack=0.002, release=0.03):
    x = np.arange(n) / SR
    total = n / SR
    return np.clip(x / attack, 0, 1) * np.clip((total - x) / release, 0, 1)


def game_bop():
    x = square(330, 0.05)
    return lowpass(x, 3000) * tone_env(len(x), release=0.02)


def game_blip():
    f = np.linspace(660, 990, int(SR * 0.06))
    x = square(f, 0.06, duty=0.25)
    return lowpass(x, 4000) * tone_env(len(x), release=0.03)


def game_lose():
    f = np.geomspace(440, 110, int(SR * 0.45))
    x = square(f, 0.45)
    return lowpass(x, 2500) * tone_env(len(x), release=0.12)


def game_win():
    out = np.zeros(int(SR * 0.6))
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        n = square(f, 0.11, duty=0.25)
        place(out, lowpass(n, 4000) * tone_env(len(n), release=0.04), i * 0.1)
    return out


def card_snap():
    out = np.zeros(int(SR * 0.07))
    place(out, bandpass(noise(0.02), 1500, 7000) * env(int(SR * 0.02), 0.0005, 0.004), 0)
    place(out, 0.4 * np.sin(2 * np.pi * 160 * t(0.03)) * env(int(SR * 0.03), 0.001, 0.008), 0)
    return out


def card_riffle():
    out = np.zeros(int(SR * 0.5))
    for i in range(16):
        place(out, (0.4 + 0.3 * rng.random()) * bandpass(noise(0.008), 2000, 8000)
              * env(int(SR * 0.008), 0.0003, 0.0015), 0.02 + i * 0.026 + 0.004 * rng.random())
    return out


def mine_boom():
    x = t(0.9)
    raw = noise(0.9)
    body = lowpass(lowpass(raw, 500), 400) * np.exp(-x / 0.25)
    thump = np.sin(2 * np.pi * 55 * x) * np.exp(-x / 0.18)
    crack = bandpass(noise(0.04), 1000, 6000) * env(int(SR * 0.04), 0.0005, 0.01)
    out = 2.5 * body + 0.8 * thump
    place(out, 0.5 * crack, 0)
    return reverb(out, mix=0.15, room=0.5)


def pin_flipper():
    out = np.zeros(int(SR * 0.09))
    place(out, np.sin(2 * np.pi * 95 * t(0.06)) * env(int(SR * 0.06), 0.001, 0.015), 0)
    place(out, 0.6 * bandpass(noise(0.01), 800, 5000) * env(int(SR * 0.01), 0.0003, 0.002), 0)
    return out


def pin_bumper():
    out = np.zeros(int(SR * 0.35))
    place(out, bell(1180, 0.3, 0.07, ((1, 1), (2.7, 0.5), (4.1, 0.25))), 0)
    place(out, 0.6 * np.sin(2 * np.pi * 120 * t(0.05)) * env(int(SR * 0.05), 0.001, 0.012), 0)
    return out


def pin_chime():
    return pad(bell(1760, 0.35, 0.12), 0.05)


def pin_sling():
    out = np.zeros(int(SR * 0.12))
    place(out, square(220, 0.06, duty=0.3) * tone_env(int(SR * 0.06), release=0.03) * 0.5, 0)
    place(out, bandpass(noise(0.012), 1000, 6000) * env(int(SR * 0.012), 0.0003, 0.003), 0)
    return lowpass(out, 5000)


def pin_drop():
    return bandpass(noise(0.03), 600, 3000) * env(int(SR * 0.03), 0.0005, 0.008) + \
        0.5 * np.sin(2 * np.pi * 300 * t(0.03)) * env(int(SR * 0.03), 0.001, 0.01)


def pin_warp():
    x = t(0.7)
    f = 1400 * np.exp(-x / 0.25) + 120
    phase = np.cumsum(f) / SR
    tone = np.sin(2 * np.pi * phase) * (1 + 0.4 * np.sin(2 * np.pi * 18 * x))
    return reverb(tone * np.exp(-x / 0.35) * np.clip(x / 0.01, 0, 1), mix=0.3, room=0.6)


def pin_launch():
    x = t(0.5)
    f = 600 * np.exp(-x / 0.18) + 90 + 30 * np.sin(2 * np.pi * 26 * x)
    phase = np.cumsum(f) / SR
    spring = np.sin(2 * np.pi * phase) * np.exp(-x / 0.2)
    out = 0.6 * spring
    place(out, bandpass(noise(0.02), 1500, 6000) * env(int(SR * 0.02), 0.0005, 0.004), 0)
    return out


def pin_drain():
    x = t(0.6)
    f = np.geomspace(300, 70, len(x))
    phase = np.cumsum(f) / SR
    return np.sin(2 * np.pi * phase) * np.clip((0.6 - x) / 0.15, 0, 1) * np.clip(x / 0.01, 0, 1)


def pin_start():
    """Space Rabbit's start-up: a rising synth sweep into a little
    arpeggio (all original)."""
    out = np.zeros(int(SR * 2.4))
    x = t(0.9)
    sweep_f = np.geomspace(110, 880, len(x))
    phase = np.cumsum(sweep_f) / SR
    sweep = (np.sin(2 * np.pi * phase) + 0.3 * np.sin(4 * np.pi * phase)) * np.clip(x / 0.6, 0, 1)
    place(out, 0.4 * lowpass(sweep, 3000) * np.clip((0.9 - x) / 0.2, 0, 1), 0)
    for i, f in enumerate((440.0, 554.37, 659.25, 880.0, 659.25, 880.0, 1108.73)):
        n = square(f, 0.16, duty=0.3)
        place(out, 0.35 * lowpass(n, 3500) * tone_env(len(n), release=0.06), 0.85 + i * 0.13)
    place(out, 0.5 * bell(1760, 0.8, 0.3), 0.85 + 7 * 0.13)
    return reverb(out, mix=0.25, room=0.6)


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
    save('shutter_digital', shutter_digital(), peak=0.8)
    save('shutter_film', shutter_film(), peak=0.8)
    save('shutter_run', shutter_run(), peak=0.8)
    save('cork_swoosh', cork_swoosh(), peak=0.8)
    save('cork_thud', cork_thud(), peak=0.8)
    for name, fn in [('game_bop', game_bop), ('game_blip', game_blip), ('game_lose', game_lose),
                     ('game_win', game_win), ('card_snap', card_snap), ('card_riffle', card_riffle),
                     ('mine_boom', mine_boom), ('pin_flipper', pin_flipper), ('pin_bumper', pin_bumper),
                     ('pin_chime', pin_chime), ('pin_sling', pin_sling), ('pin_drop', pin_drop),
                     ('pin_warp', pin_warp), ('pin_launch', pin_launch), ('pin_drain', pin_drain),
                     ('pin_start', pin_start)]:
        save(name, fn(), peak=0.7)
