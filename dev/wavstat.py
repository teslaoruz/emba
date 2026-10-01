"""Duration and loudness of a wav: python dev/wavstat.py file.wav"""
import sys, wave
import numpy as np
w = wave.open(sys.argv[1])
a = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype("float32") / 32768
print(f"{len(a) / w.getframerate():.2f}s  peak {abs(a).max():.3f}  rms {np.sqrt((a ** 2).mean()):.4f}")
