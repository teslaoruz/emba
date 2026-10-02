"""Print the microphone's loudness (RMS) every 0.1 s for a few seconds.
    .venv/bin/python dev/miclevel.py [SECONDS]"""
import sys

import numpy as np
import sounddevice as sd

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 3
with sd.InputStream(samplerate=16000, channels=1, dtype="float32") as s:
    for _ in range(int(secs * 10)):
        block, _ = s.read(1600)
        print(f"{float(np.sqrt(np.mean(block ** 2))):.5f}")
