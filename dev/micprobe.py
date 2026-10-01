"""Print the microphone's loudness every 0.25 s for a few seconds: python dev/micprobe.py [seconds]"""
import sys

import numpy as np
import sounddevice as sd

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 6
print("device:", sd.query_devices(kind="input")["name"])
audio = sd.rec(int(secs * 16000), samplerate=16000, channels=1, dtype="float32")
sd.wait()
for i in range(0, len(audio), 4000):
    print(f"{i / 16000:4.2f}s  rms {float(np.sqrt(np.mean(audio[i:i + 4000] ** 2))):.4f}")
