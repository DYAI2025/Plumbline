"""Ignores SIGTERM: only KILL escalation can stop it."""
import os, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
sys.stdout.write("PG pid=%d pgid=%d term=ignored\n" % (os.getpid(), os.getpgid(0)))
sys.stdout.flush()
while True:
    time.sleep(3600)
