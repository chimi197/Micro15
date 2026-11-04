"""Synthesises the game's sound effects and ambience loops into
game/audio/*.wav (mono, 22.05 kHz, 16 bit), so the game has sound without
any third-party recordings. Run from the repository root:

    python tools/make_sounds.py

Needs only numpy. Every sound is built from noise, filters and a few
oscillators; the random seeds are fixed, so running it again gives the same
files. Real recordings can replace any file later (same name).

Footsteps: step_<surface>_<n>.wav for asphalt, paving, concrete, grass,
dirt, gravel, sand, wood, metal and rubber (four variants each), plus
land_<surface>.wav. Effects: kick, bounce, cap, buy, creak_<n>, thump, score,
shutter, jump. Unseen neighbours: life_carpet_<n>, life_ball, life_door,
life_window. Ambience: amb_day.wav and amb_night.wav (seamless 40 s loops).
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "audio")


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def band(x, lo, hi, soft=0.15):
    """Band-pass by FFT with soft edges (lo/hi in Hz, 0 / None for open)."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(x)
    gain = np.ones_like(f)
    if lo:
        gain *= 1 / (1 + (lo / np.maximum(f, 1e-3)) ** (2 / soft * 0.3))
    if hi:
        gain *= 1 / (1 + (f / hi) ** (2 / soft * 0.3))
    return np.fft.irfft(spec * gain, n)


def env(n, attack, decay, curve=4.0):
    """Fast attack, exponential decay envelope over n samples (seconds)."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) * curve / max(decay, 1e-4))
    return a * d


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def fade(x, ms=4):
    """Short fades so no file starts or ends with a click (0.5 ms in keeps
    the attack of a hit)."""
    a, k = int(SR * 0.0005), int(SR * ms / 1000)
    if a + k < len(x):
        x[:a] *= np.linspace(0, 1, a)
        x[-k:] *= np.linspace(1, 0, k)
    return x


def save(name, x, peak=0.9):
    os.makedirs(OUT, exist_ok=True)
    x = norm(fade(np.asarray(x, dtype=np.float64)), peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def noise(rng, seconds):
    return rng.standard_normal(int(SR * seconds))


def brown(rng, seconds):
    x = np.cumsum(rng.standard_normal(int(SR * seconds)))
    x -= np.convolve(x, np.ones(2001) / 2001, mode="same")     # keep it centred
    return x


def resonator(freq, decay, seconds, rng=None, jitter=0.0):
    t = t_axis(seconds)
    f = freq * (1 + (rng.uniform(-jitter, jitter) if rng is not None else 0))
    return np.sin(2 * np.pi * f * t) * np.exp(-t / decay)


# ----------------------------------------------------------------------------
# Footsteps
# ----------------------------------------------------------------------------
def step(surface, rng, heavy=False):
    k = 1.6 if heavy else 1.0
    if surface in ("asphalt", "paving", "concrete"):
        dur = 0.16 * k
        n = int(SR * dur)
        heel = band(noise(rng, dur), 300, 4200) * env(n, 0.002, 0.03 * k, 5)
        toe = np.zeros(n)
        off = int(SR * rng.uniform(0.045, 0.06))
        toe[off:] = band(noise(rng, dur), 900, 6000)[: n - off] * env(n - off, 0.002, 0.02, 5) * 0.45
        grit = band(noise(rng, dur), 2500, 9000) * env(n, 0.005, 0.07, 3) * (0.25 if surface == "paving" else 0.12)
        thud = resonator(rng.uniform(85, 110), 0.025 * k, dur) * 0.5
        bright = {"asphalt": 0.8, "paving": 1.1, "concrete": 1.0}[surface]
        return heel * bright + toe + grit + thud * (1.4 if heavy else 1.0)
    if surface == "grass":
        dur = 0.24 * k
        n = int(SR * dur)
        swish = band(noise(rng, dur), 1200, 7000) * env(n, 0.02, 0.12 * k, 3)
        crush = band(noise(rng, dur), 150, 900) * env(n, 0.006, 0.05, 4) * 0.6
        return swish + crush
    if surface in ("dirt", "gravel", "sand"):
        dur = 0.24 * k
        n = int(SR * dur)
        base = band(noise(rng, dur), 120, 1500) * env(n, 0.004, 0.06 * k, 4) * 0.7
        grains = np.zeros(n)
        count = {"dirt": 18, "gravel": 70, "sand": 6}[surface]
        for _ in range(count):
            p = int(abs(rng.normal(0.03, 0.035)) * SR)
            if p >= n - 200:
                continue
            g = band(noise(rng, 0.008), 1500, 8000) * env(int(SR * 0.008), 0.0005, 0.004, 4)
            grains[p:p + len(g)] += g * rng.uniform(0.3, 1.0)
        hiss = band(noise(rng, dur), 3000, 9000) * env(n, 0.01, 0.12, 3) * (0.5 if surface == "sand" else 0.1)
        return base + grains * (0.9 if surface == "gravel" else 0.5) + hiss
    if surface == "wood":
        dur = 0.22 * k
        n = int(SR * dur)
        knock = sum(resonator(f, 0.04 * k, dur, rng, 0.05) * a for f, a in ((190, 1.0), (420, 0.5), (760, 0.25)))
        tap = band(noise(rng, dur), 800, 5000) * env(n, 0.001, 0.012, 5) * 0.6
        return knock * env(n, 0.002, 0.2, 1) + tap
    if surface == "metal":
        dur = 0.45 * k
        n = int(SR * dur)
        ring = sum(resonator(f, 0.18, dur, rng, 0.03) * a for f, a in ((523, 0.6), (1187, 0.5), (1970, 0.35), (2830, 0.2)))
        clank = band(noise(rng, dur), 1000, 8000) * env(n, 0.001, 0.015, 5)
        return ring * 0.5 + clank
    # rubber (playground mats, the swing seat)
    dur = 0.16 * k
    n = int(SR * dur)
    return resonator(rng.uniform(70, 90), 0.03, dur) + band(noise(rng, dur), 200, 1200) * env(n, 0.003, 0.03, 4) * 0.4


SURFACES = ("asphalt", "paving", "concrete", "grass", "dirt", "gravel", "sand", "wood", "metal", "rubber")


# ----------------------------------------------------------------------------
# Effects
# ----------------------------------------------------------------------------
def effects(rng):
    # a kicked rubber football: a hollow thump with a slap on top
    dur = 0.35
    n = int(SR * dur)
    t = t_axis(dur)
    thump = np.sin(2 * np.pi * (140 * t - 60 * t * t)) * np.exp(-t / 0.05)
    slap = band(noise(rng, dur), 600, 5000) * env(n, 0.001, 0.02, 5)
    save("kick", thump + slap * 0.8)
    # a ball bouncing on the ground
    dur = 0.3
    t = t_axis(dur)
    pitch = 220 * np.exp(-t * 6) + 120
    boing = np.sin(2 * np.pi * np.cumsum(pitch) / SR) * np.exp(-t / 0.06)
    save("bounce", boing + band(noise(rng, dur), 400, 3000) * env(len(t), 0.001, 0.015, 5) * 0.5)
    # a bottle cap: a bright tinny tink, bent edge rattle
    dur = 0.5
    n = int(SR * dur)
    tink = sum(resonator(f, 0.08, dur, rng, 0.02) * a for f, a in ((3150, 1.0), (4720, 0.6), (6100, 0.35), (2210, 0.3)))
    save("cap", tink * env(n, 0.001, 0.4, 2) + band(noise(rng, dur), 4000, 9000) * env(n, 0.001, 0.01, 5) * 0.4)
    # buying: coins on the kiosk's counter
    dur = 0.7
    n = int(SR * dur)
    coins = np.zeros(n)
    for i, at in enumerate((0.0, 0.09, 0.15, 0.24)):
        p = int(at * SR)
        c = sum(resonator(f, 0.06, dur - at, rng, 0.04) * a for f, a in ((2400, 1.0), (3700, 0.6), (5300, 0.3)))
        coins[p:] += c[: n - p] * (1.0 - i * 0.15)
    save("buy", coins)
    # swing chain creak: stick-slip friction, a buzzy tone that wavers
    for v in range(3):
        dur = rng.uniform(0.45, 0.7)
        t = t_axis(dur)
        f0 = rng.uniform(380, 520)
        wobble = f0 * (1 + 0.08 * np.sin(2 * np.pi * rng.uniform(5, 9) * t) + 0.04 * rng.standard_normal(len(t)).cumsum() / np.sqrt(len(t)))
        phase = np.cumsum(wobble) / SR
        saw = 2 * (phase % 1.0) - 1
        bursts = (np.sin(2 * np.pi * rng.uniform(20, 35) * t) > 0.2).astype(float)
        shape = np.sin(np.pi * t / dur) ** 0.7
        save("creak_%d" % v, band(saw * bursts, 300, 2600) * shape, 0.7)
    # seesaw bump: wood on rubber tyre
    dur = 0.4
    n = int(SR * dur)
    save("thump", resonator(75, 0.07, dur) + resonator(180, 0.05, dur) * 0.6
         + band(noise(rng, dur), 200, 2000) * env(n, 0.002, 0.03, 4) * 0.5)
    # a goal: a referee's whistle, two short blasts
    dur = 0.9
    t = t_axis(dur)
    trill = 1 + 0.5 * (np.sin(2 * np.pi * 32 * t) > 0)
    tone = np.sin(2 * np.pi * np.cumsum(2900 * (1 + 0.01 * np.sin(2 * np.pi * 30 * t))) / SR) * trill
    gate = ((t > 0.02) & (t < 0.28)) | ((t > 0.4) & (t < 0.82))
    save("score", (tone + band(noise(rng, dur), 2500, 4000) * 0.3) * gate * 0.8, 0.6)
    # photo: shutter click-clack
    dur = 0.25
    n = int(SR * dur)
    x = np.zeros(n)
    for at, b in ((0.0, 1.0), (0.07, 0.7)):
        p = int(at * SR)
        c = band(noise(rng, dur - at), 1500, 8000) * env(n - p, 0.0005, 0.01, 5) + resonator(900, 0.01, dur - at) * 0.3
        x[p:] += c * b
    save("shutter", x)
    # jump: a short breath and cloth swish
    dur = 0.25
    n = int(SR * dur)
    save("jump", band(noise(rng, dur), 400, 3000) * env(n, 0.03, 0.12, 3) * 0.6, 0.5)


def life(rng):
    """Sounds of people the game never shows (no NPCs): somebody beating a
    carpet in the yard, a ball bounced against a wall, a stairwell door
    banging shut, a window being closed."""
    # carpet beating: a run of dull, dusty thwacks
    for v in range(2):
        hits = rng.integers(5, 9)
        dur = hits * 0.62 + 0.5
        n = int(SR * dur)
        x = np.zeros(n)
        for i in range(hits):
            p = max(0, int((i * 0.62 + rng.uniform(-0.05, 0.05)) * SR))
            k = int(SR * 0.3)
            whack = band(noise(rng, 0.3), 150, 2200) * env(k, 0.002, 0.06, 4)
            whack += resonator(rng.uniform(90, 120), 0.04, 0.3) * 0.8
            dust = band(noise(rng, 0.3), 2000, 6000) * env(k, 0.01, 0.2, 2) * 0.15
            seg = x[p:p + k]
            seg += (whack + dust)[: len(seg)] * rng.uniform(0.7, 1.0)
        save("life_carpet_%d" % v, band(x, 80, 5000), 0.8)
    # a ball bounced off a wall and the ground, a few times
    dur = 3.0
    n = int(SR * dur)
    x = np.zeros(n)
    at = 0.0
    for i in range(6):
        p = int(at * SR)
        k = int(SR * 0.25)
        t = t_axis(0.25)
        b = np.sin(2 * np.pi * np.cumsum(200 * np.exp(-t * 8) + 110) / SR) * np.exp(-t / 0.05)
        seg = x[p:p + k]
        seg += b[: len(seg)]
        at += rng.uniform(0.35, 0.55)
    save("life_ball", band(x, 80, 3000), 0.7)
    # a stairwell door: latch click and a heavy bang with the hall ringing
    dur = 1.4
    n = int(SR * dur)
    t = t_axis(dur)
    bang = band(noise(rng, dur), 60, 1800) * env(n, 0.002, 0.15, 4) + resonator(70, 0.12, dur) * 0.9
    ring = band(noise(rng, dur), 300, 1500) * env(n, 0.02, 0.9, 2) * 0.12
    click = np.zeros(n)
    c = band(noise(rng, 0.02), 2000, 7000) * env(int(SR * 0.02), 0.0005, 0.005, 5)
    click[int(SR * 0.12):int(SR * 0.12) + len(c)] += c * 0.5
    save("life_door", bang + ring + click, 0.8)
    # a window shutting: a rattle of glass in a frame and a thud
    dur = 0.8
    n = int(SR * dur)
    rattle = sum(resonator(f, 0.05, dur, rng, 0.05) for f in (1800, 2600, 3900)) * env(n, 0.003, 0.2, 3)
    save("life_window", rattle * 0.4 + resonator(110, 0.06, dur) + band(noise(rng, dur), 200, 3000) * env(n, 0.002, 0.04, 4) * 0.5, 0.7)


# ----------------------------------------------------------------------------
# Ambience
# ----------------------------------------------------------------------------
def loopable(x, xfade=2.0):
    """Crossfades the end into the start so the file loops without a seam."""
    k = int(SR * xfade)
    head, body, tail = x[:k], x[k:-k], x[-k:]
    w = np.linspace(0, 1, k)
    return np.concatenate([tail * (1 - w) + head * w, body]) if len(body) else x


def chirp(rng, f0, f1, dur):
    t = t_axis(dur)
    f = np.linspace(f0, f1, len(t)) * (1 + 0.04 * np.sin(2 * np.pi * rng.uniform(40, 70) * t))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / dur) ** 2


def sparrow(rng):
    """A house sparrow's chirrup: a few quick tweets."""
    parts = []
    for _ in range(rng.integers(2, 6)):
        f = rng.uniform(3200, 4600)
        parts.append(chirp(rng, f, f * rng.uniform(0.7, 1.2), rng.uniform(0.04, 0.09)))
        parts.append(np.zeros(int(SR * rng.uniform(0.03, 0.09))))
    return np.concatenate(parts)


def pigeon(rng):
    """A feral pigeon's coo: a soft low 'hoo-hroo-hoo'."""
    parts = []
    for i, (d, f) in enumerate(((0.25, 420), (0.45, 470), (0.3, 400))):
        t = t_axis(d)
        tone = np.sin(2 * np.pi * np.cumsum(f * (1 + 0.06 * np.sin(2 * np.pi * 14 * t))) / SR)
        rough = 1 + 0.5 * np.sin(2 * np.pi * 70 * t)
        parts.append(tone * rough * np.sin(np.pi * t / d) ** 1.5)
        parts.append(np.zeros(int(SR * 0.05)))
    return band(np.concatenate(parts), 250, 1400)


def scatter_into(bed, rng, maker, per_minute, gain, fade_far=True):
    n = len(bed)
    count = int(per_minute * n / SR / 60)
    for _ in range(count):
        s = maker(rng)
        p = rng.integers(0, max(1, n - len(s)))
        g = gain * (rng.uniform(0.25, 1.0) if fade_far else 1.0)
        bed[p:p + len(s)] += s[: n - p] * g
    return bed


def ambience(rng):
    dur = 42.0
    n = int(SR * dur)
    t = t_axis(dur)
    # day: wind in the trees, the city's low rumble, a passing trolley or car
    # far off, sparrows in the hedges, pigeons on the blocks
    wind = band(brown(rng, dur), 80, 900) * (0.6 + 0.4 * np.sin(2 * np.pi * t / 14.0 + 1.0) ** 2)
    leaves = band(noise(rng, dur), 2000, 7000) * (0.15 + 0.25 * np.sin(2 * np.pi * t / 14.0 + 0.6) ** 4)
    city = band(brown(rng, dur), 40, 260) * 1.4
    passes = np.zeros(n)
    for at in (6.0, 22.0, 33.0):
        w = np.exp(-((t - at) / 3.0) ** 2)
        passes += band(noise(rng, dur), 120, 1100) * w * 0.5
    day = norm(wind) * 0.35 + norm(leaves) * 0.12 + norm(city) * 0.35 + norm(passes) * 0.25
    day = scatter_into(day, rng, sparrow, 22, 0.22)
    day = scatter_into(day, rng, pigeon, 3, 0.18)
    save("amb_day", loopable(day), 0.6)
    # night: crickets in the lawns, a softer wind, the city quieter
    crickets = np.zeros(n)
    for _ in range(5):
        f = rng.uniform(4300, 5200)
        rate = rng.uniform(2.5, 4.0)
        pulse = (np.sin(2 * np.pi * rate * t + rng.uniform(0, 6)) > 0.55).astype(float)
        chirps = (np.sin(2 * np.pi * 30 * t) > 0).astype(float)
        crickets += np.sin(2 * np.pi * f * t) * pulse * chirps * rng.uniform(0.2, 1.0)
    crickets = band(crickets, 3500, 6500)
    night = norm(wind) * 0.18 + norm(city) * 0.22 + norm(crickets) * 0.18
    save("amb_night", loopable(night), 0.5)


def main():
    rng = np.random.default_rng(15)
    for s in SURFACES:
        for v in range(4):
            save("step_%s_%d" % (s, v), step(s, rng), 0.8)
        save("land_%s" % s, step(s, rng, heavy=True), 0.9)
    effects(rng)
    life(rng)
    ambience(rng)
    print("wrote", len(os.listdir(OUT)), "files to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
