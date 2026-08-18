"""Leads its OWN process group inside the INHERITED session, and ignores SIGTERM.

Staying in the caller's session is the point: only a process in the same session may
join this group with setpgid(), which is what the live-group-shift probes need. A target
started with start_new_session=True is in a session of its own and no other process can
ever join its group, so the live checks could not be exercised with one.
"""
import os, signal, sys, time

os.setpgid(0, 0)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
sys.stdout.write("LEADER pid=%d pgid=%d sid=%d term=ignored\n"
                 % (os.getpid(), os.getpgid(0), os.getsid(0)))
sys.stdout.flush()
while True:
    time.sleep(3600)
