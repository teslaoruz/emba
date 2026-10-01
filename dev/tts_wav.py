"""Write speech to a wav with Piper: python dev/tts_wav.py OUT.wav TEXT"""
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "voice"))
import voice  # noqa: E402

v = voice.piper_voice("en_US-amy-medium")
with wave.open(sys.argv[1], "wb") as w:
    v.synthesize_wav(" ".join(sys.argv[2:]), w)
