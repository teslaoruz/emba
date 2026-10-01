"""CPU of a process over a few seconds, its own and its children's: python dev/cpu.py PID [seconds]"""
import os, sys, time
pid, secs = int(sys.argv[1]), float(sys.argv[2]) if len(sys.argv) > 2 else 10
tick = os.sysconf("SC_CLK_TCK")
def sample():
    with open(f"/proc/{pid}/stat") as f:
        v = [int(x) for x in f.read().rsplit(")", 1)[1].split()[11:15]]
    return (v[0] + v[1]) / tick, (v[2] + v[3]) / tick
a = sample(); time.sleep(secs); b = sample()
with open(f"/proc/{pid}/status") as f:
    rss = next(l for l in f if l.startswith("VmRSS")).split()[1]
print(f"self {100 * (b[0] - a[0]) / secs:.1f}%  children {100 * (b[1] - a[1]) / secs:.1f}%  rss {int(rss) // 1024} MB")
