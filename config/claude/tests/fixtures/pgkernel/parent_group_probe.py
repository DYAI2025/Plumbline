"""Becomes its own group leader, then asks a CHILD to validate a binding that names
THIS process's group. The child's caller-group check must refuse it. Prints the child's
verdict so the test can assert on a real parent/child relationship."""
import os, subprocess, sys
os.setpgid(0, 0)
here = os.path.dirname(os.path.abspath(__file__))
sys.stdout.write("PARENT pid=%d pgid=%d\n" % (os.getpid(), os.getpgrp()))
sys.stdout.flush()
# start_new_session: the child must NOT share our group, otherwise the kernel's
# self-group branch refuses first and the caller's-group branch is never exercised.
child = subprocess.Popen([sys.executable, "-I", os.path.join(here, "_caller_group_child.py"),
                          str(os.getpid()), str(os.getpgrp()), sys.argv[1]],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True, start_new_session=True)
out, err = child.communicate()
sys.stdout.write(out)
sys.stderr.write(err)
