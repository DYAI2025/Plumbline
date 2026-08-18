"""Cases 5 and 15: the CALLER's group changes DURING the grace period.

Three processes:

    A = this process. Not a session leader, so it can join another group in the session.
    B = fork of A. It is the supervisor: it spawns the target and owns the wait status.
    T = the target. Leads its own group inside the shared session and ignores SIGTERM.

B validates once (VALID), then calls terminate_bound_group. A joins T's group while the
grace period is running. The re-validation that precedes the SIGKILL must therefore see
getpgid(getppid()) == the target group and refuse -- SIGTERM has already been sent and
ignored, so this is the one moment where the escalation is about to happen.

Two things are proven at once: the parent group is read LIVE (a value stored at binding
time would still be A's old group), and the re-validation before the SIGKILL is REACHED
(delete it and the SIGKILL goes out, the target dies, and the state becomes a success).

B never signals A deliberately: it refuses, and cleans up with os.kill on T's pid.
"""
import os, subprocess, sys, time

HERE = sys.argv[1]
sys.path.insert(0, HERE)
import lib_process_group as K  # noqa: E402

FIX = os.path.join(HERE, "fixtures", "pgkernel")
GRACE = 2.0
SHIFT_AFTER = 0.6


def say(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


say("A pid=%d pgid=%d sid=%d session_leader=%s"
    % (os.getpid(), os.getpgrp(), os.getsid(0), os.getpid() == os.getsid(0)))

announce_r, announce_w = os.pipe()   # B -> A: the target group id
child = os.fork()

if child == 0:
    # ---- B: the supervisor -------------------------------------------------------
    os.close(announce_r)
    target = subprocess.Popen([sys.executable, "-I",
                               os.path.join(FIX, "same_session_leader.py")],
                              stdout=subprocess.PIPE, text=True)
    line = target.stdout.readline().strip()
    tpid = int(line.split()[1].split("=")[1])
    tpgid = int(line.split()[2].split("=")[1])
    say("B pid=%d pgid=%d ppid=%d parent_pgid=%d" % (os.getpid(), os.getpgrp(),
                                                     os.getppid(), os.getpgid(os.getppid())))
    say("B_TARGET %s" % line)
    say("B_TARGET_GROUP_IS_NOT_OURS %s" % (tpgid != os.getpgrp()))
    binding = K.Binding(target_pid=tpid, initial_pgid=tpgid)
    v1 = K.validate_bound_group(binding)
    say("B_BEFORE state=%s reason=%s" % (v1.state, v1.reason))
    os.write(announce_w, b"%d\n" % tpgid)

    started = time.time()
    st = K.terminate_bound_group(target, binding, grace_seconds=GRACE)
    say("B_ELAPSED %.2f grace=%.1f shift_at=%.1f" % (time.time() - started, GRACE, SHIFT_AFTER))
    say("B_RESULT state=%s reason=%s" % (st.state, st.reason))
    say("B_FIELDS target_still_running=%r target_reaped=%r additional_signal_sent=%r "
        "exit_code=%r signal_number=%r"
        % (st.target_still_running, st.target_reaped, st.additional_signal_sent,
           st.exit_code, st.signal_number))
    say("B_TARGET_ALIVE %s" % alive(tpid))
    say("B_LIVE_PARENT_PGID %s target_group=%d"
        % (os.getpgid(os.getppid()) if alive(os.getppid()) else "parent-gone", tpgid))
    try:
        os.kill(tpid, 9)
    except OSError:
        pass
    K.reap_process(target, timeout=5)
    say("B_CLEANED target_gone=%s" % (not alive(tpid)))
    os._exit(0)

# ---- A: shifts its own group into the target's group while the grace runs --------
os.close(announce_w)
with os.fdopen(announce_r) as fh:
    tpgid = int(fh.readline().strip())
time.sleep(SHIFT_AFTER)
try:
    os.setpgid(0, tpgid)
    say("A_SHIFTED live_pgid=%d equals_target_group=%s"
        % (os.getpgrp(), os.getpgrp() == tpgid))
except OSError as exc:
    say("A_SHIFT_FAILED %s" % exc)
os.waitpid(child, 0)
