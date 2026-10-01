"""Loudness over time in a wav: python dev/wavprofile.py file.wav"""
import sys, wave
import numpy as np
w = wave.open(sys.argv[1]); r = w.getframerate()
a = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype("float32") / 32768
for i in range(0, len(a), r // 10):
    print(f"{i / r:4.1f}s {'#' * int(np.sqrt((a[i:i + r // 10] ** 2).mean()) * 400)}")
