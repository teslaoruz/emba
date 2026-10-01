"""Run a wav through Emba's own transcribe() (with its filters): python dev/embatx.py file.wav"""
import sys, wave
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "voice"))
import voice
w = wave.open(sys.argv[1])
a = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype("float32") / 32768
print(repr(voice.transcribe(a, "base")))
