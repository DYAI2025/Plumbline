"""Case 10: getpgid(parent) fails with ESRCH.

FAULT-INJECTED, and named as such. The real OS cannot produce it: an orphan is
reparented to pid 1 (launchd on macOS), and getpgid(1) succeeds. The failure is injected
at the syscall boundary -- os.getpgid raises ESRCH for the parent pid ONLY -- so the
branch under test is entered for the real reason it exists.

The control run matters as much as the injected one: the SAME binding is VALID without
the injection, so the refusal cannot be attributed to anything else. The lookup counter
also proves the kernel really performs a live parent lookup at all.
"""
import errno
import os
import sys
import time

HERE = sys.argv[1]
sys.path.insert(0, HERE)
import lib_process_group as K  # noqa: E402

FIX = os.path.join(HERE, "fixtures", "pgkernel")


def say(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


started = K.spawn_process_group([sys.executable, "-I", os.path.join(FIX, "hangs.py")])
proc, binding = started
time.sleep(0.4)
ppid = os.getppid()
say("PROBE pid=%d pgid=%d ppid=%d parent_pgid=%d"
    % (os.getpid(), os.getpgrp(), ppid, os.getpgid(ppid)))
say("TARGET pid=%d pgid=%d leads_group=%s"
    % (binding.target_pid, binding.initial_pgid, binding.target_pid == binding.initial_pgid))

control = K.validate_bound_group(binding)
say("CONTROL state=%s reason=%s" % (control.state, control.reason))

real_getpgid = os.getpgid
counts = {"parent": 0, "target": 0}


def injected(pid):
    if pid == ppid:
        counts["parent"] += 1
        raise OSError(errno.ESRCH, os.strerror(errno.ESRCH))
    counts["target"] += 1
    return real_getpgid(pid)


os.getpgid = injected
try:
    active = False
    try:
        injected(ppid)
    except OSError as exc:
        active = exc.errno == errno.ESRCH
    say("INJECTION_ACTIVE %s target_lookup_still_real=%s"
        % (active, injected(binding.target_pid) == binding.initial_pgid))
    verdict = K.validate_bound_group(binding)
finally:
    os.getpgid = real_getpgid

say("INJECTED state=%s reason=%s" % (verdict.state, verdict.reason))
say("LOOKUPS parent=%d target=%d" % (counts["parent"], counts["target"]))

st = K.terminate_bound_group(proc, binding, grace_seconds=2)
gone = False
try:
    os.kill(binding.target_pid, 0)
except ProcessLookupError:
    gone = True
say("CLEANED state=%s target_gone=%s" % (st.state, gone))
