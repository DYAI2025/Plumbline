"""Leads its own group, then MOVES itself into another group on demand.

This is the only way to make getpgid(target) return a group other than the bound one:
a target started with start_new_session=True is a session leader and cannot change its
process group at all (setsid and setpgid both fail), so its pgid can never drift.

Protocol: announce, read one line holding the destination pgid from stdin, join it,
announce again.
"""
import os, signal, sys, time

os.setpgid(0, 0)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
sys.stdout.write("DRIFTER pid=%d pgid=%d sid=%d\n"
                 % (os.getpid(), os.getpgid(0), os.getsid(0)))
sys.stdout.flush()
dest = int(sys.stdin.readline().strip())
try:
    os.setpgid(0, dest)
    sys.stdout.write("DRIFTED pid=%d pgid=%d requested=%d\n"
                     % (os.getpid(), os.getpgid(0), dest))
except OSError as exc:
    sys.stdout.write("DRIFT_FAILED pid=%d requested=%d error=%s\n"
                     % (os.getpid(), dest, exc))
sys.stdout.flush()
while True:
    time.sleep(3600)
