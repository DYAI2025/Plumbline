"""Stays in the inherited process group and ignores SIGTERM."""
import os, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
with open(sys.argv[1], "a", encoding="utf-8") as f:
    f.write("MEMBER pid=%d ppid=%d pgid=%d sid=%d term=ignored\n"
            % (os.getpid(), os.getppid(), os.getpgid(0), os.getsid(0)))
    f.flush()
while True:
    time.sleep(3600)
