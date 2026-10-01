"""Record the mic to a wav: python dev/micrec.py OUT.wav SECONDS"""
import sys, wave
import numpy as np, sounddevice as sd
secs = float(sys.argv[2])
a = sd.rec(int(secs * 16000), samplerate=16000, channels=1, dtype="float32"); sd.wait()
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes((a.clip(-1, 1) * 32767).astype("<i2").tobytes())
