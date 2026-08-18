"""Spawns a child that calls setsid() and deliberately survives OUTSIDE the target
group, then the parent hangs. This documents the PRODUCT BOUNDARY -- it is neither a
pass for process-tree control nor a defect of the group-scoped kernel.

The escaping child logs its pid to argv[1] so the test can clean up exactly that pid.
"""
import os, subprocess, sys, time
logf = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
sys.stdout.write("PG pid=%d pgid=%d\n" % (os.getpid(), os.getpgid(0)))
subprocess.Popen([sys.executable, "-I", os.path.join(here, "_escaper.py"), logf])
sys.stdout.flush()
while True:
    time.sleep(3600)
