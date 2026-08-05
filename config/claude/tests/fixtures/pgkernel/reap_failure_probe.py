"""Case 14: the reap fails AFTER the SIGKILL went out -- and REAP_FAILED survives.

FAULT-INJECTED at the syscall boundary, and named as such: a target cannot survive
SIGKILL, so a real post-SIGKILL wait cannot be made to fail. What is injected is only
the OBSERVATION -- os.waitpid starts failing the moment the real SIGKILL has been sent.
The SIGKILL itself is real and the target really dies, which the probe proves afterwards
by reaping it for real.

The injection is deliberately keyed on the SIGKILL and not switched on from the start:
switching it on earlier would fail the reap during the grace period, the escalation would
never happen, and the named path -- reap failure AFTER the escalation -- would not be the
one under test.

Scenario B covers the other half of the rule: when the kernel REFUSES to signal and the
reap also fails, the refusal keeps the state (it is the safety-critical fact) but the reap
failure is disclosed in the reason instead of being dropped.
"""
import errno
import os
import signal
import sys
import time

HERE = sys.argv[1]
sys.path.insert(0, HERE)
import lib_process_group as K  # noqa: E402

FIX = os.path.join(HERE, "fixtures", "pgkernel")


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


real_killpg = os.killpg
real_waitpid = os.waitpid

# --- Scenario A: reap failure after a REAL SIGKILL -------------------------------
proc, binding = K.spawn_process_group([sys.executable, "-I",
                                       os.path.join(FIX, "ignores_term.py")])
time.sleep(0.5)
say("A_TARGET pid=%d pgid=%d alive=%s"
    % (binding.target_pid, binding.initial_pgid, alive(binding.target_pid)))

flags = {"killed": False, "failures_after_kill": 0, "waits_before_kill": 0}


def killpg_watch(pgid, sig):
    result = real_killpg(pgid, sig)
    if sig == signal.SIGKILL:
        flags["killed"] = True
    return result


def waitpid_fail_after_kill(pid, options=0):
    if flags["killed"]:
        flags["failures_after_kill"] += 1
        raise OSError(errno.EINVAL, "injected waitpid failure after the real SIGKILL")
    flags["waits_before_kill"] += 1
    return real_waitpid(pid, options)


os.killpg = killpg_watch
os.waitpid = waitpid_fail_after_kill
try:
    outcome = K.terminate_bound_group(proc, binding, grace_seconds=1.0)
finally:
    os.killpg = real_killpg
    os.waitpid = real_waitpid

say("A_SIGKILL_WAS_REAL %s waits_before_kill=%d failures_after_kill=%d"
    % (flags["killed"], flags["waits_before_kill"], flags["failures_after_kill"]))
say("A_RESULT state=%s additional_signal_sent=%r exit_code=%r signal_number=%r "
    "target_reaped=%r"
    % (outcome.state, outcome.additional_signal_sent, outcome.exit_code,
       outcome.signal_number, outcome.target_reaped))
say("A_REASON %s" % outcome.reason)

real_status = K.reap_process(proc, timeout=5)
say("A_REAL_STATUS state=%s signal_number=%r target_gone=%s"
    % (real_status.state, real_status.signal_number, not alive(binding.target_pid)))

# --- Scenario B: a refusal must disclose, not drop, a reap failure ----------------
proc2, binding2 = K.spawn_process_group([sys.executable, "-I", os.path.join(FIX, "hangs.py")])
time.sleep(0.3)
not_leader = K.Binding(target_pid=binding2.target_pid,
                       initial_pgid=binding2.initial_pgid + 7)
say("B_BINDING target_pid=%d initial_pgid=%d leads_group=%s"
    % (not_leader.target_pid, not_leader.initial_pgid,
       not_leader.target_pid == not_leader.initial_pgid))


def waitpid_always_fails(pid, options=0):
    raise OSError(errno.EINVAL, "injected waitpid failure")


os.waitpid = waitpid_always_fails
try:
    outcome2 = K.terminate_bound_group(proc2, not_leader, grace_seconds=1.0)
finally:
    os.waitpid = real_waitpid

say("B_RESULT state=%s additional_signal_sent=%r" % (outcome2.state,
                                                     outcome2.additional_signal_sent))
say("B_REASON %s" % outcome2.reason)
try:
    os.kill(binding2.target_pid, 9)
except OSError:
    pass
K.reap_process(proc2, timeout=5)
say("B_CLEANED target_gone=%s" % (not alive(binding2.target_pid)))
