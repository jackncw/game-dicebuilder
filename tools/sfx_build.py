#!/usr/bin/env python
"""Builds assets/audio/sfx/*.ogg — the game's entire sound-effect set.

Self-contained and reproducible: downloads the Kenney CC0 packs it draws from
(cached under tools/_sfx_cache/), trims/normalizes each pick, and writes one
mono 44.1kHz OGG per game event. Events with no fitting sample in the packs are
synthesized here (numpy) — those are ours, also CC0-equivalent.

    python tools/sfx_build.py

Licensing: every source pack is Kenney (kenney.nl), CC0 1.0. See CREDITS.md,
which mirrors the PICKS table below.
"""
import io
import os
import sys
import zipfile
import urllib.request

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", "_sfx_cache")
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
SR = 44100

# Kenney pack pages carry a hashed zip URL; scraped once and pinned here so the
# build does not depend on the page markup staying still. All CC0 1.0.
PACKS = {
    "casino-audio": "https://kenney.nl/media/pages/assets/casino-audio/2472606a04-1721639069/kenney_casino-audio.zip",
    "impact-sounds": "https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
    "interface-sounds": "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
    "rpg-audio": "https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
}

# event name -> (pack, path inside zip, gain, pitch)   pitch: resample factor,
# >1 = higher/shorter. Layered events list several sources mixed together.
PICKS = {
    "roll":   [("casino-audio", "Audio/dice-throw-1.ogg", 1.0, 1.0)],
    "die":    [("impact-sounds", "Audio/impactWood_light_000.ogg", 0.9, 1.0)],
    "hit":    [("impact-sounds", "Audio/impactSoft_medium_001.ogg", 1.0, 1.0)],
    "hit_heavy": [("impact-sounds", "Audio/impactPunch_heavy_000.ogg", 1.0, 0.92),
                  ("impact-sounds", "Audio/impactWood_heavy_001.ogg", 0.5, 0.8)],
    "block":  [("impact-sounds", "Audio/impactPlate_light_001.ogg", 0.9, 1.0)],
    "pierce": [("rpg-audio", "Audio/knifeSlice.ogg", 0.9, 1.05)],
    "stun":   [("impact-sounds", "Audio/impactBell_heavy_002.ogg", 0.55, 1.2)],
    "buy":    [("rpg-audio", "Audio/handleCoins.ogg", 0.9, 1.0)],
    "card":   [("rpg-audio", "Audio/bookFlip2.ogg", 0.9, 1.0)],
    "swoosh": [("rpg-audio", "Audio/cloth2.ogg", 0.65, 1.1)],
    "button": [("interface-sounds", "Audio/click_001.ogg", 0.8, 1.0)],
    "potion": [("interface-sounds", "Audio/glass_004.ogg", 0.8, 0.95)],
    "chest":  [("rpg-audio", "Audio/metalLatch.ogg", 0.9, 1.0),
               ("rpg-audio", "Audio/creak1.ogg", 0.5, 1.15)],
    "death":  [("impact-sounds", "Audio/impactSoft_heavy_001.ogg", 0.9, 0.85)],
    "boss":   [("impact-sounds", "Audio/impactBell_heavy_000.ogg", 0.8, 0.55)],
}


def fetch(pack: str) -> zipfile.ZipFile:
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, pack + ".zip")
    if not os.path.exists(path):
        print("downloading", pack)
        urllib.request.urlretrieve(PACKS[pack], path)
    return zipfile.ZipFile(path)


def load_sample(z: zipfile.ZipFile, inner: str) -> np.ndarray:
    data, sr = sf.read(io.BytesIO(z.read(inner)), dtype="float32", always_2d=True)
    mono = data.mean(axis=1)
    if sr != SR:
        n = int(len(mono) * SR / sr)
        mono = np.interp(np.linspace(0, len(mono) - 1, n), np.arange(len(mono)), mono)
    return mono


def repitch(x: np.ndarray, factor: float) -> np.ndarray:
    if abs(factor - 1.0) < 1e-3:
        return x
    n = int(len(x) / factor)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype("float32")


def trim(x: np.ndarray, thresh_db: float = -50.0) -> np.ndarray:
    amp = 10 ** (thresh_db / 20)
    keep = np.where(np.abs(x) > amp)[0]
    if len(keep) == 0:
        return x
    a = max(0, keep[0] - int(0.005 * SR))
    b = min(len(x), keep[-1] + int(0.05 * SR))
    return x[a:b]


def finalize(x: np.ndarray, gain: float = 1.0) -> np.ndarray:
    x = trim(x)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * 0.85 * gain
    fade = min(len(x), int(0.01 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    x[:min(len(x), 64)] *= np.linspace(0, 1, min(len(x), 64))
    return x.astype("float32")


def mix(layers) -> np.ndarray:
    n = max(len(l) for l in layers)
    out = np.zeros(n, dtype="float32")
    for l in layers:
        out[: len(l)] += l
    return out


# ---------------------------------------------------------------- synthesized
# Events with no honest match in the packs. Same DNA as tools/music_build.py's
# palette so the game reads as one production, not a sample-pack collage.

def _noise(n, seed):
    return np.random.default_rng(seed).uniform(-1, 1, n).astype("float32")


def _lowpass(x, cutoff):
    out = np.empty_like(x)
    prev = 0.0
    for i, v in enumerate(x):
        prev += cutoff * (v - prev)
        out[i] = prev
    return out


def synth_poison() -> np.ndarray:
    """Wet, unpleasant blub: two short downward-gliding sines with noise."""
    t = np.arange(int(0.22 * SR)) / SR
    f = 300 - 500 * t
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 18)
    fizz = _lowpass(_noise(len(t), 11), 0.12) * np.exp(-t * 25) * 0.5
    return (body * 0.8 + fizz).astype("float32")


def synth_burn() -> np.ndarray:
    """A crackling sizzle: bandpassed noise with random pops."""
    n = int(0.3 * SR)
    x = _lowpass(_noise(n, 23), 0.35)
    x -= _lowpass(x, 0.05)  # crude bandpass
    env = np.exp(-np.arange(n) / SR * 12)
    rng = np.random.default_rng(5)
    for p in rng.integers(0, n - 80, 10):
        x[p:p + 80] += np.hanning(80) * rng.uniform(0.4, 0.9)
    return (x * env).astype("float32")


def synth_boss_swell() -> np.ndarray:
    """Rising dread under the boss bell: sub boom + noise swell."""
    n = int(1.1 * SR)
    t = np.arange(n) / SR
    sub = np.sin(2 * np.pi * (38 + 14 * t) * t) * np.minimum(t * 3, 1) * np.exp(-np.maximum(t - 0.7, 0) * 8)
    wind = _lowpass(_noise(n, 31), 0.08) * np.minimum(t * 2, 1) ** 2 * 0.7
    return (sub * 0.9 + wind).astype("float32")


def _pluck(freq: float, dur: float, seed: int = 3, bright: float = 0.5) -> np.ndarray:
    """Karplus-Strong string pluck — the same voice music_build.py leads with."""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    rng = np.random.default_rng(seed)
    buf = rng.uniform(-1, 1, period).astype("float32")
    out = np.empty(n, dtype="float32")
    for i in range(n):
        out[i] = buf[i % period]
        nxt = buf[(i + 1) % period]
        buf[i % period] = (buf[i % period] + nxt) * 0.5 * (0.996 + 0.003 * bright)
    return out


def synth_heal() -> np.ndarray:
    """Warm two-note rise, soft attack — mending, not magic-missile."""
    out = np.zeros(int(0.8 * SR), dtype="float32")
    for i, f in enumerate([392.0, 493.88]):  # G4 -> B4, a warm major third
        t = np.arange(int(0.7 * SR)) / SR
        tone = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2 * t)) \
            * np.minimum(t * 18, 1) * np.exp(-t * 5)
        s = int(i * 0.1 * SR)
        out[s:s + len(t)] += tone * 0.45
    return out


def synth_essence() -> np.ndarray:
    """One airy high pluck — a mote of breath arriving in the pool."""
    return _pluck(1318.5, 0.35, seed=17, bright=0.8) * 0.6


def synth_cast() -> np.ndarray:
    """The big ritual: a deep inharmonic bell under a rising shimmer."""
    n = int(1.3 * SR)
    t = np.arange(n) / SR
    bell = np.zeros(n, dtype="float32")
    for p, w in [(1.0, 1.0), (2.76, 0.5), (5.4, 0.25), (8.9, 0.12)]:
        bell += np.sin(2 * np.pi * 110 * p * t) * w * np.exp(-t * (3 + p))
    shimmer = np.sin(2 * np.pi * (880 + 660 * t) * t) * np.minimum(t * 4, 1) * np.exp(-t * 4) * 0.2
    return (bell * 0.5 + shimmer).astype("float32")


def synth_levelup() -> np.ndarray:
    """Quick ascending pluck arpeggio — pentatonic, bright."""
    notes = [523.25, 659.25, 783.99, 1046.5]
    seg = int(0.09 * SR)
    tail = int(0.5 * SR)
    out = np.zeros(seg * len(notes) + tail, dtype="float32")
    for i, f in enumerate(notes):
        t = np.arange(seg + tail) / SR
        tone = np.sin(2 * np.pi * f * t) * np.exp(-t * 6) * (1 - 0.4 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 12))
        out[i * seg : i * seg + len(t)] += tone * 0.5
    return out


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    zips = {p: fetch(p) for p in PACKS}
    written = []
    for name, layers in PICKS.items():
        parts = []
        for pack, inner, gain, pitch in layers:
            x = load_sample(zips[pack], inner)
            parts.append(finalize(repitch(x, pitch)) * gain)
        y = finalize(mix(parts)) if len(parts) > 1 else parts[0]
        path = os.path.join(OUT, name + ".ogg")
        sf.write(path, y, SR, format="OGG", subtype="VORBIS")
        written.append((name, len(y) / SR, os.path.getsize(path)))
    for name, fn in [("poison", synth_poison), ("burn", synth_burn),
                     ("boss_swell", synth_boss_swell), ("levelup", synth_levelup),
                     ("heal", synth_heal), ("essence", synth_essence),
                     ("cast", synth_cast)]:
        y = finalize(fn())
        path = os.path.join(OUT, name + ".ogg")
        sf.write(path, y, SR, format="OGG", subtype="VORBIS")
        written.append((name, len(y) / SR, os.path.getsize(path)))
    total = 0
    for name, dur, size in sorted(written):
        print(f"  {name:<12} {dur:5.2f}s {size/1024:7.1f} KB")
        total += size
    print(f"total {total/1024:.0f} KB across {len(written)} events")


if __name__ == "__main__":
    sys.exit(main())
