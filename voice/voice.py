#!/usr/bin/env python3
"""Emba's voice: local, free, offline after the first model download.

    voice.py listen [--model base]    record until you stop talking, print the text
    voice.py say TEXT [--voice NAME]  speak TEXT
    voice.py wake [--words emba,...]  listen for "Emba" and print a line when heard
    voice.py setup                    download the models now

Every command prints JSON lines on stdout for Emba to follow:
    {"state": "listening"} {"level": 0.42} {"state": "thinking"} {"text": "..."}
    {"state": "speaking"} {"level": 0.3} {"state": "done"} {"wake": true} {"error": "..."}

Needs: pip install faster-whisper sounddevice piper-tts
"""

import json
import os
import platform
import queue
import re
import subprocess
import sys
import time
from pathlib import Path

RATE = 16000
BLOCK = 1600  # 100 ms


def out(**kw):
    print(json.dumps(kw), flush=True)


def data_dir():
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home()))
    elif platform.system() == "Darwin":
        base = Path.home() / "Library" / "Application Support"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    d = base / "emba" / "voice"
    d.mkdir(parents=True, exist_ok=True)
    return d


def arg(name, default):
    a = sys.argv
    return a[a.index(name) + 1] if name in a[:-1] else default


# ---------------------------------------------------------------- hearing

_models = {}


def whisper(name):
    if name not in _models:
        from faster_whisper import WhisperModel
        _models[name] = WhisperModel(name, device="cpu", compute_type="int8", download_root=str(data_dir() / "whisper"))
    return _models[name]


def record(max_wait=6.0, max_len=15.0, silence=1.0, threshold=None, report=True):
    """Record one utterance: wait for speech, stop after a pause. Returns float32 audio or None."""
    import numpy as np
    import sounddevice as sd

    q = queue.Queue()
    with sd.InputStream(samplerate=RATE, channels=1, dtype="float32", blocksize=BLOCK,
                        callback=lambda d, *_: q.put(d.copy())):
        # the first half second sets the noise floor, so a noisy room still works
        floor = [np.sqrt(np.mean(q.get() ** 2)) for _ in range(5)]
        thr = threshold or max(0.012, float(np.median(floor)) * 3)
        chunks, started, quiet, t0 = [], False, 0.0, time.time()
        while True:
            block = q.get()
            level = float(np.sqrt(np.mean(block ** 2)))
            if report:
                out(level=round(min(1.0, level / (thr * 4)), 3))
            if level > thr:
                started, quiet = True, 0.0
            elif started:
                quiet += BLOCK / RATE
            if started:
                chunks.append(block)
            elif time.time() - t0 > max_wait:
                return None
            if started and (quiet >= silence or len(chunks) * BLOCK / RATE >= max_len):
                return np.concatenate(chunks)[:, 0]


# What Whisper tends to "hear" in silence and room noise
HALLUCINATIONS = {"", "you", "thank you", "thanks", "thank you for watching", "thanks for watching", "bye",
                  "so", "okay", "uh", "um", "hmm", "mm", "oh"}


def transcribe(audio, model):
    segs, _ = whisper(model).transcribe(audio, beam_size=1, vad_filter=True)
    text = " ".join(s.text.strip() for s in segs if s.no_speech_prob < 0.6 and s.avg_logprob > -1.0).strip()
    return "" if re.sub(r"[^a-z ]", "", text.lower()).strip() in HALLUCINATIONS else text


def listen():
    model = arg("--model", "base")
    out(state="listening")
    audio = record()
    if audio is None:
        out(error="I didn't hear anything")
        return
    out(state="thinking")
    text = transcribe(audio, model)
    if text:
        out(text=text)
    else:
        out(error="I didn't catch any words")


def wake():
    words = [w.strip().lower() for w in arg("--words", "emba,ember,amba,embah").split(",") if w.strip()]
    model = arg("--model", "tiny")
    pattern = re.compile(r"\b(hey |hi |ok |okay )?(" + "|".join(map(re.escape, words)) + r")\b")
    whisper(model)  # load once, up front
    out(state="ready")
    while True:
        # short phrases only: a wake word is one or two words
        audio = record(max_wait=3600, max_len=3.0, silence=0.5, report=False)
        if audio is None or len(audio) > 3.0 * RATE:
            continue
        heard = transcribe(audio, model).lower()
        if pattern.search(heard):
            out(wake=True, heard=heard)


# ---------------------------------------------------------------- speaking

def piper_voice(name):
    from piper import PiperVoice
    from piper.download_voices import download_voice
    d = data_dir() / "piper"
    d.mkdir(exist_ok=True)
    model = d / f"{name}.onnx"
    if not model.exists():
        download_voice(name, d)
    return PiperVoice.load(str(model))


def say():
    text = " ".join(a for a in sys.argv[2:] if not a.startswith("--") and a != arg("--voice", None))
    text = re.sub(r"[`*_#>]+", "", text).strip()  # markdown reads badly aloud
    if not text:
        return
    out(state="speaking")
    try:
        import numpy as np
        import sounddevice as sd
        voice = piper_voice(arg("--voice", "en_US-amy-medium"))
        with sd.OutputStream(samplerate=voice.config.sample_rate, channels=1, dtype="float32") as stream:
            for chunk in voice.synthesize(text):
                audio = chunk.audio_float_array.astype("float32")
                step = chunk.sample_rate // 20  # 50 ms windows drive the mouth
                for i in range(0, len(audio), step):
                    piece = audio[i:i + step]
                    out(level=round(min(1.0, float(np.sqrt(np.mean(piece ** 2))) * 6), 3))
                    stream.write(piece.reshape(-1, 1))
    except Exception as e:  # no piper, no audio device, no network for the first download
        if not system_say(text):
            out(error=f"can't speak: {e}")
    out(state="done")


def system_say(text):
    """The OS's own voice, when Piper is not available."""
    s = platform.system()
    if s == "Darwin":
        cmd = ["say", text]
    elif s == "Windows":
        cmd = ["powershell", "-NoProfile", "-Command",
               "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak($args[0])",
               text]
    else:
        cmd = next(([c, text] for c in ("spd-say", "espeak-ng", "espeak") if shutil_which(c)), None)
    if not cmd:
        return False
    out(level=0.5)
    return subprocess.run(cmd, capture_output=True).returncode == 0


def shutil_which(c):
    from shutil import which
    return which(c)


def setup():
    out(state="downloading")
    whisper(arg("--model", "base"))
    whisper("tiny")
    piper_voice(arg("--voice", "en_US-amy-medium"))
    out(state="done")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        {"listen": listen, "say": say, "wake": wake, "setup": setup}[cmd]()
    except KeyError:
        print(__doc__)
        sys.exit(2)
    except ImportError as e:
        out(error=f"voice needs: pip install faster-whisper sounddevice piper-tts ({e.name} missing)")
        sys.exit(1)
    except Exception as e:
        out(error=str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()
