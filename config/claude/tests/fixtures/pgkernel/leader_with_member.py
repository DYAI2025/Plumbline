"""Leader that exits cleanly on SIGTERM while a member stays in the SAME pgid.
The member ignores SIGTERM. Both announce pid/ppid/pgid/sid to argv[1]."""
import os, signal, subprocess, sys, time
logf = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
child = subprocess.Popen([sys.executable, "-I", os.path.join(here, "member.py"), logf])
time.sleep(0.8)
with open(logf, "a", encoding="utf-8") as f:
    f.write("LEADER pid=%d pgid=%d sid=%d child=%d\n"
            % (os.getpid(), os.getpgid(0), os.getsid(0), child.pid))
    f.flush()
signal.signal(signal.SIGTERM, lambda *_a: os._exit(0))
while True:
    time.sleep(3600)
