"""Transcribe a wav with no filtering: python dev/rawtx.py file.wav"""
import sys
from faster_whisper import WhisperModel

m = WhisperModel("base", device="cpu", compute_type="int8")
segs, info = m.transcribe(sys.argv[1], beam_size=1)
for s in segs:
    print(f"{s.text!r} no_speech={s.no_speech_prob:.2f} logprob={s.avg_logprob:.2f}")
