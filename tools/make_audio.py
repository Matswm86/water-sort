"""Synthesises the game's sound effects and calm music loop into assets/audio/."""

import wave
from pathlib import Path

import numpy as np

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(7)


def write(name: str, x: np.ndarray) -> None:
    x = x / max(1e-9, np.abs(x).max()) * 0.85
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def t(sec: float) -> np.ndarray:
    return np.arange(int(sec * SR)) / SR


def env(n: int, attack: float, release: float) -> np.ndarray:
    e = np.ones(n)
    a = int(attack * SR)
    r = int(release * SR)
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r) ** 2
    return e


def bell(freq: float, sec: float) -> np.ndarray:
    tt = t(sec)
    x = sum(np.sin(2 * np.pi * freq * m * tt) * g * np.exp(-tt * d) for m, g, d in [(1, 1, 4), (2.01, 0.4, 7), (3.02, 0.15, 11)])
    return x * env(len(tt), 0.004, 0.05)


def pour() -> np.ndarray:
    # Glugging water: a train of short resonant bubbles with rising pitch over filtered noise.
    tt = t(0.9)
    x = np.zeros_like(tt)
    pos = 0.0
    while pos < 0.8:
        f = 380 + 500 * pos + rng.uniform(-60, 60)
        bt = t(0.06)
        blip = np.sin(2 * np.pi * (f + 900 * bt) * bt) * np.exp(-bt * 55)
        i = int(pos * SR)
        x[i : i + len(blip)] += blip[: len(x) - i] * rng.uniform(0.5, 1.0)
        pos += rng.uniform(0.035, 0.07)
    noise = np.convolve(rng.normal(0, 1, len(tt)), np.ones(12) / 12, mode="same")
    x += noise * 0.12
    return x * env(len(tt), 0.02, 0.2)


def tap() -> np.ndarray:
    tt = t(0.09)
    return np.sin(2 * np.pi * 1300 * tt) * np.exp(-tt * 60) + 0.3 * np.sin(2 * np.pi * 2600 * tt) * np.exp(-tt * 90)


def done() -> np.ndarray:
    out = np.zeros(int(0.9 * SR))
    for k, f in enumerate([784, 1175]):
        b = bell(f, 0.7)
        i = int(k * 0.09 * SR)
        out[i : i + len(b)] += b
    return out


def win() -> np.ndarray:
    out = np.zeros(int(1.8 * SR))
    for k, f in enumerate([523, 659, 784, 1047, 1319]):
        b = bell(f, 1.0)
        i = int(k * 0.11 * SR)
        out[i : i + len(b)] += b * (0.8 if k < 4 else 1.0)
    return out


def music() -> np.ndarray:
    # Slow pad chords (I - vi - IV - V in C) with a soft plucked arpeggio; 19.2 s loop.
    bar = 4.8
    chords = [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
    total = np.zeros(int(bar * len(chords) * SR))
    for ci, ch in enumerate(chords):
        tt = t(bar)
        pad = sum(np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * f * 2 * tt + 0.3) for f in ch)
        pad *= 0.5 + 0.5 * np.sin(np.pi * tt / bar) ** 2
        i = int(ci * bar * SR)
        total[i : i + len(tt)] += pad * 0.35
        notes = ch + [ch[1] * 2, ch[2] * 2, ch[0] * 2, ch[2] * 2, ch[1] * 2]
        for k, f in enumerate(notes):
            pt = t(1.2)
            pl = np.sin(2 * np.pi * f * 2 * pt) * np.exp(-pt * 3.5) * env(len(pt), 0.005, 0.1)
            j = i + int(k * bar / len(notes) * SR)
            seg = total[j : j + len(pl)]
            seg += pl[: len(seg)] * 0.45
    # Crossfade the tail into the head so the loop is seamless.
    fade = int(0.4 * SR)
    total[:fade] = total[:fade] * np.linspace(0, 1, fade) + total[-fade:] * np.linspace(1, 0, fade)
    return total[:-fade]


OUT.mkdir(parents=True, exist_ok=True)
for name, fn in [("pour", pour), ("tap", tap), ("done", done), ("win", win), ("music", music)]:
    write(name, fn())
