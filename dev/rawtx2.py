"""Transcribe a wav loudly and in English: python dev/rawtx2.py file.wav [model]"""
import sys, wave
import numpy as np
from faster_whisper import WhisperModel

w = wave.open(sys.argv[1])
a = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype("float32") / 32768
a = a / max(1e-4, abs(a).max()) * 0.9
m = WhisperModel(sys.argv[2] if len(sys.argv) > 2 else "small", device="cpu", compute_type="int8")
segs, info = m.transcribe(a, beam_size=5, language="en")
print("lang prob", round(info.language_probability, 2))
for s in segs:
    print(f"{s.text!r} no_speech={s.no_speech_prob:.2f}")
