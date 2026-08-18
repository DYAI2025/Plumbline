"""The bound group id still resolves, but it no longer names the target's group.

The target moves itself into a THIRD group -- not the supervisor's, not the caller's --
so the drift check is the only guard that can answer. If it were removed, the later
self-group and caller-group guards would not catch this, and the kernel would signal a
group the target has left.

Must be started WITHOUT start_new_session (see same_session_leader.py).
"""
import os, subprocess, sys, time

HERE = sys.argv[1]
sys.path.insert(0, HERE)
import lib_process_group as K  # noqa: E402

FIX = os.path.join(HERE, "fixtures", "pgkernel")


def say(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


say("PROBE pid=%d pgid=%d sid=%d" % (os.getpid(), os.getpgrp(), os.getsid(0)))

# A third group, owned by nobody in this story, for the target to move into.
dest = subprocess.Popen([sys.executable, "-I", os.path.join(FIX, "same_session_leader.py")],
                        stdout=subprocess.PIPE, text=True)
dline = dest.stdout.readline().strip()
dest_pgid = int(dline.split()[2].split("=")[1])
say("DEST %s" % dline)

drifter = subprocess.Popen([sys.executable, "-I", os.path.join(FIX, "drifter.py")],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
line = drifter.stdout.readline().strip()
say("TARGET %s" % line)
tpid = int(line.split()[1].split("=")[1])
tpgid = int(line.split()[2].split("=")[1])

binding = K.Binding(target_pid=tpid, initial_pgid=tpgid)
v1 = K.validate_bound_group(binding)
say("BEFORE_DRIFT state=%s reason=%s" % (v1.state, v1.reason))
say("DEST_IS_A_THIRD_GROUP %s"
    % (dest_pgid not in (os.getpgrp(), os.getpgid(os.getppid()), tpgid)))

drifter.stdin.write("%d\n" % dest_pgid)
drifter.stdin.flush()
say("TARGET_AFTER %s" % drifter.stdout.readline().strip())
say("LIVE_TARGET_PGID %d bound=%d drifted=%s"
    % (os.getpgid(tpid), tpgid, os.getpgid(tpid) != tpgid))

v2 = K.validate_bound_group(binding)
say("AFTER_DRIFT state=%s reason=%s" % (v2.state, v2.reason))

for p in (tpid, dest.pid):
    try:
        os.kill(p, 9)
    except OSError:
        pass
    try:
        os.waitpid(p, 0)
    except OSError:
        pass
time.sleep(0.2)
left = []
for p in (tpid, dest.pid):
    try:
        os.kill(p, 0)
        left.append(p)
    except OSError:
        pass
say("CLEANED survivors=%r" % left)
