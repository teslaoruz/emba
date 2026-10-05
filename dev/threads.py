"""CPU per thread of a process over N seconds (which part of Qt is busy).

    python dev/threads.py PID [SECONDS]
"""
import os
import sys
import time

pid, secs = sys.argv[1], float(sys.argv[2] if len(sys.argv) > 2 else 5)
tick = os.sysconf("SC_CLK_TCK")


def sample():
    out = {}
    for t in os.listdir(f"/proc/{pid}/task"):
        try:
            name = open(f"/proc/{pid}/task/{t}/comm").read().strip()
            f = open(f"/proc/{pid}/task/{t}/stat").read().rsplit(")", 1)[1].split()
            out[t] = (name, int(f[11]) + int(f[12]))
        except OSError:
            pass
    return out


a = sample()
time.sleep(secs)
b = sample()
rows = sorted(((b[t][1] - a[t][1]) / tick / secs * 100, b[t][0], t) for t in b if t in a)
for pct, name, t in reversed(rows[-8:]):
    print(f"{pct:5.1f}%  {name:20} {t}")
