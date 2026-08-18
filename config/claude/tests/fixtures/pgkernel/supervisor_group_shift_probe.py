"""Case 4: the supervisor's OWN group changes AFTER the binding was made.

Same binding, same target, twice: VALID before the shift, refused after it. Nothing
about the binding changed between the two verdicts, so a verdict that does not change is
proof that os.getpgrp() was not read live.

Must be started WITHOUT start_new_session: a session leader cannot leave its own session
group (setpgid -> EPERM), so a session-leading probe could not perform the shift at all.
"""
import os, subprocess, sys, time

HERE = sys.argv[1]
sys.path.insert(0, HERE)
import lib_process_group as K  # noqa: E402

FIX = os.path.join(HERE, "fixtures", "pgkernel")


def say(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


say("PROBE pid=%d pgid=%d sid=%d session_leader=%s"
    % (os.getpid(), os.getpgrp(), os.getsid(0), os.getpid() == os.getsid(0)))

target = subprocess.Popen([sys.executable, "-I", os.path.join(FIX, "same_session_leader.py")],
                          stdout=subprocess.PIPE, text=True)
line = target.stdout.readline().strip()
say("TARGET %s" % line)
tpid = int(line.split()[1].split("=")[1])
tpgid = int(line.split()[2].split("=")[1])
tsid = int(line.split()[3].split("=")[1])
say("TARGET_LEADS_GROUP %s" % (tpid == tpgid))
say("TARGET_SAME_SESSION %s" % (tsid == os.getsid(0)))
say("PARENT_GROUP_DIFFERS %s" % (os.getpgid(os.getppid()) != tpgid))

binding = K.Binding(target_pid=tpid, initial_pgid=tpgid)
v1 = K.validate_bound_group(binding)
say("BEFORE_SHIFT state=%s reason=%s" % (v1.state, v1.reason))

try:
    os.setpgid(0, tpgid)
    say("SHIFTED live_pgid=%d equals_target_group=%s" % (os.getpgrp(), os.getpgrp() == tpgid))
except OSError as exc:
    say("SHIFT_FAILED %s" % exc)

v2 = K.validate_bound_group(binding)
say("AFTER_SHIFT state=%s reason=%s" % (v2.state, v2.reason))

# os.kill on the pid, never killpg: this probe is now a member of that very group.
try:
    os.kill(tpid, 9)
except OSError:
    pass
try:
    os.waitpid(tpid, 0)
except OSError:
    pass
time.sleep(0.2)
gone = False
try:
    os.kill(tpid, 0)
except ProcessLookupError:
    gone = True
say("CLEANED target_gone=%s" % gone)
