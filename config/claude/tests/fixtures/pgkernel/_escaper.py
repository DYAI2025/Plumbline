"""Leaves the inherited process group via setsid() and logs its pid before detaching."""
import os, sys, time
os.setsid()
with open(sys.argv[1], "a", encoding="utf-8") as fh:
    fh.write("ESCAPED pid=%d pgid=%d sid=%d\n" % (os.getpid(), os.getpgid(0), os.getsid(0)))
    fh.flush()
while True:
    time.sleep(3600)
