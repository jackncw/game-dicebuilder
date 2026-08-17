#!/usr/bin/env python
"""Composes and renders the game's music — assets/audio/bgm/*.ogg.

Everything here is procedural (numpy): Karplus-Strong plucks lead, detuned
sine pads underneath, an FFT-colored wind bed, and simple synthesized
percussion where a track needs drive. No external samples — the score is the
project's own work, which is what lets CREDITS.md say "原創" without an
asterisk.

Loops are seamless by construction: each track's note events are rendered
TWICE back to back and the second pass is what ships, so every decay tail and
reverb tail from the end of the loop is already ringing at its beginning.

    python tools/music_build.py            # all tracks
    python tools/music_build.py boss title # just these

Tracks (spec: 章節氛圍 翠綠明亮 → 暮橙緊張 → 暗紫壓迫):
  title  72bpm D-maj pentatonic, sparse warm plucks — the grove at rest
  ch1    92bpm G-maj pentatonic, bright plucks + soft shaker
  ch2   100bpm A-dorian, pulsing bass, lower plucks, dusk pad
  ch3    76bpm D-phrygian drone, sparse dissonant plucks, deep pad
  boss  120bpm D-minor ostinato bass, kick/hat drive, stabs
  win    ~5s rising pluck flourish over a warm pad hit (stinger, no loop)
  lose   ~6s falling minor line into a dark pad (stinger, no loop)
"""
import os
import sys

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio", "bgm")
SR = 44100


# ---------------------------------------------------------------- voices

def pluck(freq: float, dur: float, rng, bright=0.6, level=1.0) -> np.ndarray:
    """Karplus-Strong, block-vectorized: one buffer of `period` samples is
    smoothed and re-emitted per cycle, so a 3s note is ~500 vector ops."""
    period = max(2, int(SR / freq))
    n = int(dur * SR)
    buf = rng.uniform(-1, 1, period).astype("float64")
    # brightness = how much of the initial noise's top end survives
    for _ in range(int((1 - bright) * 6)):
        buf = 0.5 * (buf + np.roll(buf, 1))
    cycles = n // period + 2
    out = np.empty(cycles * period)
    decay = 0.995 + 0.004 * min(freq / 880.0, 1.0)
    for c in range(cycles):
        out[c * period:(c + 1) * period] = buf
        buf = decay * 0.5 * (buf + np.roll(buf, 1))
    body = out[:n]
    att = min(n, 40)
    env = np.ones(n)
    env[:att] = np.linspace(0, 1, att)
    return body * env * level


def pad_chord(freqs, dur: float, rng, level=1.0, dark=0.0) -> np.ndarray:
    """Slow-breathing detuned pad. `dark` shifts harmonic weight downward."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for det, w in [(0.9965, 0.5), (1.0, 1.0), (1.0035, 0.5)]:
            ph = rng.uniform(0, 2 * np.pi)
            out += np.sin(2 * np.pi * f * det * t + ph) * w
            if dark < 0.5:
                out += np.sin(2 * np.pi * f * det * 2 * t + ph) * w * (0.35 - 0.3 * dark)
    lfo = 1 + 0.12 * np.sin(2 * np.pi * 0.13 * t + rng.uniform(0, 6))
    a = min(n, int(1.2 * SR))
    r = min(n, int(1.5 * SR))
    env = np.ones(n)
    env[:a] *= np.linspace(0, 1, a) ** 2
    env[-r:] *= np.linspace(1, 0, r) ** 1.5
    return out * lfo * env * level / (len(freqs) * 3)


def bass_note(freq: float, dur: float, level=1.0, punch=0.0) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2 * t)
    x = np.tanh(x * (1.2 + punch))
    env = np.minimum(t * 60, 1) * np.exp(-t * (2.0 + punch * 4))
    return x * env * level


def kick(level=1.0) -> np.ndarray:
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    f = 120 * np.exp(-t * 22) + 42
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 16) * level


def hat(rng, level=1.0) -> np.ndarray:
    n = int(0.05 * SR)
    x = rng.uniform(-1, 1, n)
    x = np.diff(np.concatenate([[0], x]))  # crude highpass
    return x * np.exp(-np.arange(n) / SR * 90) * level


def shaker(rng, level=1.0) -> np.ndarray:
    n = int(0.09 * SR)
    x = rng.uniform(-1, 1, n)
    x = np.diff(np.concatenate([[0], x]))
    env = np.hanning(n)
    return x * env * level


def wind_bed(dur: float, rng, level=1.0, dark=0.0) -> np.ndarray:
    """FFT-colored noise: pink-ish slope, band-limited; the forest's air."""
    n = int(dur * SR)
    spec = np.fft.rfft(rng.uniform(-1, 1, n))
    f = np.fft.rfftfreq(n, 1 / SR)
    color = 1.0 / np.maximum(f, 30) ** (0.9 + 0.5 * dark)
    color[f < 40] = 0
    color[f > (2200 - 1400 * dark)] *= 0.02
    x = np.fft.irfft(spec * color, n)
    x /= np.max(np.abs(x)) + 1e-9
    sway = 1 + 0.35 * np.sin(2 * np.pi * 0.07 * np.arange(n) / SR + rng.uniform(0, 6))
    return x * sway * level


def reverb(x: np.ndarray, rng, wet=0.25, dur=1.6) -> np.ndarray:
    """FFT convolution with a synthetic decaying-noise IR."""
    ir_n = int(dur * SR)
    ir = rng.uniform(-1, 1, ir_n) * np.exp(-np.arange(ir_n) / SR * (6.9 / dur))
    ir[: int(0.005 * SR)] = 0  # tiny predelay
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    n = len(x) + ir_n
    X = np.fft.rfft(x, n)
    H = np.fft.rfft(ir, n)
    tail = np.fft.irfft(X * H, n)[: len(x)]
    return x + tail * wet


# ---------------------------------------------------------------- scheduler

class Timeline:
    """Mixes events onto a 2×loop buffer; take() returns the second pass."""

    def __init__(self, loop_sec: float, stereo_spread=0.0):
        self.L = int(loop_sec * SR)
        self.buf = np.zeros((2 * self.L + 8 * SR, 2))
        self.spread = stereo_spread

    def add(self, when: float, mono: np.ndarray, pan=0.0, both_passes=True):
        gl = np.sqrt(0.5 * (1 - pan))
        gr = np.sqrt(0.5 * (1 + pan))
        starts = [int(when * SR)]
        if both_passes:
            starts.append(int(when * SR) + self.L)
        for s in starts:
            e = min(s + len(mono), len(self.buf))
            seg = mono[: e - s]
            self.buf[s:e, 0] += seg * gl
            self.buf[s:e, 1] += seg * gr

    def take(self) -> np.ndarray:
        return self.buf[self.L: 2 * self.L].copy()

    def take_oneshot(self, sec: float) -> np.ndarray:
        return self.buf[: int(sec * SR)].copy()


def note(base: float, semis: float) -> float:
    return base * 2 ** (semis / 12)


def master(x: np.ndarray, rms_db=-19.0) -> np.ndarray:
    x = np.tanh(x * 1.2) * 0.9
    rms = np.sqrt(np.mean(x ** 2)) + 1e-9
    x *= 10 ** (rms_db / 20) / rms
    peak = np.max(np.abs(x))
    if peak > 0.98:
        x *= 0.98 / peak
    return x.astype("float32")


# ---------------------------------------------------------------- tracks

D3, G2, A2, D2 = 146.83, 98.0, 110.0, 73.42

# scale degrees in semitones from the root
MAJ_PENT = [0, 2, 4, 7, 9]
DORIAN = [0, 2, 3, 5, 7, 9, 10]
PHRYGIAN = [0, 1, 3, 5, 7, 8, 10]
MIN_PENT = [0, 3, 5, 7, 10]


def walk_melody(rng, scale, bars, per_bar, rest_p=0.3, octaves=2):
    """A contour-aware random walk over scale degrees: mostly steps, the
    occasional leap, pulled back toward the middle of the range."""
    steps = []
    pos = len(scale)  # middle octave, root
    span = len(scale) * octaves
    for _ in range(bars * per_bar):
        if rng.random() < rest_p:
            steps.append(None)
            continue
        move = rng.choice([-2, -1, -1, 0, 1, 1, 2, rng.integers(-4, 5)])
        pos = int(np.clip(pos + move + (span // 2 - pos) * 0.08, 0, span - 1))
        octv, deg = divmod(pos, len(scale))
        steps.append(scale[deg] + 12 * octv)
    return steps


def render_title():
    rng = np.random.default_rng(20260817)
    bpm, bars = 72, 16
    beat = 60 / bpm
    L = bars * 4 * beat
    tl = Timeline(L)
    prog = [[0, 7, 16], [-3, 4, 12], [-7, 0, 9], [-5, 2, 11]]  # D  Bm  G  A (open voicings)
    for rep in range(bars // 4):
        for i, ch in enumerate(prog):
            when = (rep * 4 + i) * 4 * beat
            tl.add(when, pad_chord([note(D3, s) for s in ch], 4 * beat * 1.3, rng, 0.75, dark=0.15))
            tl.add(when, bass_note(note(D2, ch[0]), 4 * beat, 0.5))
    mel = walk_melody(rng, MAJ_PENT, bars, 2, rest_p=0.42)
    for i, s in enumerate(mel):
        if s is None:
            continue
        tl.add(i * 2 * beat + rng.uniform(-0.01, 0.01),
               pluck(note(D3 * 2, s), 2.6, rng, bright=0.55, level=0.5),
               pan=rng.uniform(-0.4, 0.4))
    tl.add(0, wind_bed(L, rng, 0.16), both_passes=True)
    x = tl.take()
    return master(np.column_stack([reverb(x[:, 0], rng, 0.3), reverb(x[:, 1], rng, 0.3)]))


def render_ch1():
    rng = np.random.default_rng(11)
    bpm, bars = 92, 16
    beat = 60 / bpm
    L = bars * 4 * beat
    tl = Timeline(L)
    prog = [[0, 7, 16], [4, 11, 19], [-3, 9, 16], [2, 7, 14]]  # G  C  Em  A-ish colors
    for rep in range(bars // 4):
        for i, ch in enumerate(prog):
            when = (rep * 4 + i) * 4 * beat
            tl.add(when, pad_chord([note(G2 * 2, s) for s in ch], 4 * beat * 1.25, rng, 0.6, dark=0.1))
            for b in range(4):
                tl.add(when + b * beat, bass_note(note(G2, ch[0]), beat * 0.9, 0.42 if b % 2 else 0.55))
    mel = walk_melody(rng, MAJ_PENT, bars, 4, rest_p=0.35)
    for i, s in enumerate(mel):
        if s is None:
            continue
        tl.add(i * beat, pluck(note(G2 * 4, s), 1.8, rng, bright=0.75, level=0.42),
               pan=rng.uniform(-0.5, 0.5))
    for b in range(bars * 4):
        if b % 2 == 1:
            tl.add(b * beat + beat * 0.5, shaker(rng, 0.10), pan=0.3)
    tl.add(0, wind_bed(L, rng, 0.10), both_passes=True)
    x = tl.take()
    return master(np.column_stack([reverb(x[:, 0], rng, 0.22), reverb(x[:, 1], rng, 0.22)]))


def render_ch2():
    rng = np.random.default_rng(22)
    bpm, bars = 100, 16
    beat = 60 / bpm
    L = bars * 4 * beat
    tl = Timeline(L)
    prog = [[0, 7, 15], [-2, 5, 12], [3, 10, 17], [-4, 3, 10]]  # Am colors, dusk
    for rep in range(bars // 4):
        for i, ch in enumerate(prog):
            when = (rep * 4 + i) * 4 * beat
            tl.add(when, pad_chord([note(A2 * 2, s) for s in ch], 4 * beat * 1.25, rng, 0.6, dark=0.45))
            for e in range(8):
                lv = 0.5 if e % 4 == 0 else 0.3
                tl.add(when + e * beat / 2, bass_note(note(A2, ch[0]), beat * 0.45, lv, punch=0.4))
    mel = walk_melody(rng, DORIAN, bars, 2, rest_p=0.4)
    for i, s in enumerate(mel):
        if s is None:
            continue
        tl.add(i * 2 * beat, pluck(note(A2 * 2, s), 2.2, rng, bright=0.5, level=0.45),
               pan=rng.uniform(-0.4, 0.4))
    for b in range(bars * 4):
        if b % 4 == 2:
            tl.add(b * beat, hat(rng, 0.12), pan=-0.2)
    tl.add(0, wind_bed(L, rng, 0.14, dark=0.5), both_passes=True)
    x = tl.take()
    return master(np.column_stack([reverb(x[:, 0], rng, 0.24), reverb(x[:, 1], rng, 0.24)]))


def render_ch3():
    rng = np.random.default_rng(33)
    bpm, bars = 76, 12
    beat = 60 / bpm
    L = bars * 4 * beat
    tl = Timeline(L)
    tl.add(0, wind_bed(L, rng, 0.22, dark=0.9), both_passes=True)
    for bar in range(bars):
        when = bar * 4 * beat
        tl.add(when, bass_note(D2, 4 * beat * 1.1, 0.6))  # unmoving drone root
        if bar % 2 == 0:
            ch = [[0, 7, 13], [0, 6, 13], [0, 5, 11]][(bar // 2) % 3]  # b9/b6 colors
            tl.add(when, pad_chord([note(D3, s) for s in ch], 8 * beat * 1.1, rng, 0.7, dark=0.85))
        if bar % 4 == 3:
            tl.add(when + 2 * beat, kick(0.35))
    mel = walk_melody(rng, PHRYGIAN, bars, 1, rest_p=0.45, octaves=1)
    for i, s in enumerate(mel):
        if s is None:
            continue
        tl.add(i * 4 * beat + rng.uniform(0, beat), pluck(note(D3, s), 3.4, rng, bright=0.3, level=0.5),
               pan=rng.uniform(-0.6, 0.6))
    x = tl.take()
    return master(np.column_stack([reverb(x[:, 0], rng, 0.4, 2.4), reverb(x[:, 1], rng, 0.4, 2.4)]), rms_db=-20.0)


def render_boss():
    rng = np.random.default_rng(55)
    bpm, bars = 120, 16
    beat = 60 / bpm
    L = bars * 4 * beat
    tl = Timeline(L)
    riff = [0, 0, 3, 0, 5, 0, 3, 2]  # D-minor ostinato
    for bar in range(bars):
        when = bar * 4 * beat
        for e in range(8):
            tl.add(when + e * beat / 2, bass_note(note(D2, riff[e]), beat * 0.5, 0.6, punch=0.9))
        tl.add(when, kick(0.55))
        tl.add(when + 2 * beat, kick(0.5))
        if bar % 2 == 1:
            tl.add(when + 3 * beat + beat / 2, kick(0.4))
        for e in range(8):
            tl.add(when + e * beat / 2 + beat / 4, hat(rng, 0.10 if e % 2 else 0.16))
        if bar % 4 == 0:
            ch = [[0, 7, 12], [0, 6, 12]][(bar // 4) % 2]
            tl.add(when, pad_chord([note(D3, s) for s in ch], 16 * beat, rng, 0.55, dark=0.6))
    mel = walk_melody(rng, MIN_PENT, bars, 4, rest_p=0.5)
    for i, s in enumerate(mel):
        if s is None:
            continue
        tl.add(i * beat, pluck(note(D3 * 2, s), 1.2, rng, bright=0.85, level=0.4),
               pan=rng.uniform(-0.5, 0.5))
    x = tl.take()
    return master(np.column_stack([reverb(x[:, 0], rng, 0.18), reverb(x[:, 1], rng, 0.18)]), rms_db=-17.5)


def render_win():
    rng = np.random.default_rng(77)
    tl = Timeline(6.0)
    for i, s in enumerate([0, 4, 7, 12, 16]):  # D maj arp up
        tl.add(i * 0.11, pluck(note(D3 * 2, s), 2.5, rng, bright=0.7, level=0.5),
               pan=(i - 2) * 0.2, both_passes=False)
    tl.add(0.44, pad_chord([note(D3, s) for s in [0, 7, 16]], 3.5, rng, 0.8, dark=0.1), both_passes=False)
    tl.add(0.44, bass_note(D2, 3.0, 0.6), both_passes=False)
    x = tl.take_oneshot(5.0)
    return master(np.column_stack([reverb(x[:, 0], rng, 0.35), reverb(x[:, 1], rng, 0.35)]))


def render_lose():
    rng = np.random.default_rng(88)
    tl = Timeline(7.0)
    for i, s in enumerate([7, 5, 3, 0, -2]):  # falling minor line
        tl.add(i * 0.5, pluck(note(D3, s), 3.0, rng, bright=0.35, level=0.5),
               pan=(2 - i) * 0.15, both_passes=False)
    tl.add(1.0, pad_chord([note(D2 * 2, s) for s in [0, 3, 10]], 4.5, rng, 0.7, dark=0.8), both_passes=False)
    tl.add(2.0, bass_note(D2, 4.0, 0.5), both_passes=False)
    x = tl.take_oneshot(6.0)
    return master(np.column_stack([reverb(x[:, 0], rng, 0.4, 2.2), reverb(x[:, 1], rng, 0.4, 2.2)]), rms_db=-20.0)


TRACKS = {
    "title": render_title, "ch1": render_ch1, "ch2": render_ch2,
    "ch3": render_ch3, "boss": render_boss, "win": render_win, "lose": render_lose,
}


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    names = argv or list(TRACKS)
    total = 0
    for name in names:
        x = TRACKS[name]()
        path = os.path.join(OUT, name + ".ogg")
        # one-shot sf.write() hard-crashes libsndfile's vorbis encoder on
        # multi-minute stereo buffers (Windows, soundfile 0.13) — block writes
        # of one second at a time are stable
        with sf.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS") as f:
            for i in range(0, len(x), SR):
                f.write(x[i:i + SR])
        size = os.path.getsize(path)
        total += size
        print(f"  {name:<6} {len(x)/SR:6.1f}s {size/1048576:5.2f} MB  peak {np.max(np.abs(x)):.2f}")
    print(f"total {total/1048576:.2f} MB")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
