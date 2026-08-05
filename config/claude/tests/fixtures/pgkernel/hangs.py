"""Announces pid/pgid, then never terminates."""
import os, sys, time
sys.stdout.write("PG pid=%d pgid=%d\n" % (os.getpid(), os.getpgid(0)))
sys.stdout.flush()
while True:
    time.sleep(3600)
