"""Contract test for the Safe Process-Group Signaling Kernel.

UNMAPPED_CHANGE: hermetic test and interpreter runtime contract
(no confirmed Jira key exists for this work; none was guessed)

    python3 config/claude/tests/test_process_group_kernel.py

REGISTERED_IN_CANONICAL_SUITE -- run_all.sh, stage "safe process-group signaling kernel".
CI therefore executes this file on both legs of the matrix, ubuntu-latest and macos-latest.

The three labels this file used to carry -- MANUAL_FOCUSED_TEST_ONLY,
NOT_REGISTERED_IN_CANONICAL_SUITE, CI_NOT_EXECUTED -- are gone because they became false
the moment the stage was added, not because the risk they described disappeared. What
registration changed: Linux is now EXERCISED rather than MISSING, and the exact Linux
evidence is whatever the CI run reports -- read it, do not assume it.

PRODUCT BOUNDARY:
    PROCESS_GROUP_SUPERVISION_ONLY
    PROCESS_TREE_CONTAINMENT_NOT_PROVIDED

Every case proves its precondition through real pid/pgid values and real signal
behaviour. An unmet precondition FAILS -- never a skip, never a silent pass.

TWO cases cannot be produced by this operating system at all, and both say so in their
own header rather than hiding it:

    case 10  getpgid(parent) -> ESRCH. An orphan is reparented to pid 1 and getpgid(1)
             succeeds, so the parent lookup cannot fail for real.
    case 14  a reap failure AFTER a SIGKILL. Nothing survives SIGKILL, so a real
             post-SIGKILL wait cannot be made to fail.

Both are FAULT-INJECTED at the syscall boundary -- os.getpgid and os.waitpid -- and only
there. Case 14's SIGKILL is real and its target really dies. Each injected case carries a
CONTROL that pins the attribution: the same input without the injection reaches the
opposite verdict, so the refusal cannot be coming from somewhere else. Evidence for those
two branches is therefore fault-injected, not real-boundary, and is reported as such.
"""

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
FIX = os.path.join(HERE, "fixtures", "pgkernel")
PY = sys.executable

import lib_process_group as K  # noqa: E402

RUN = 0
FAILED = 0
SKIPPED = 0
CLEANUP = []

# Resolved, not hardcoded: /bin/ps is right on macOS, but on a Linux image ps may live
# only in /usr/bin, or be absent entirely (procps is not always installed). An absent ps
# is reported, never silently treated as "no group members".
PS = shutil.which("ps") or "/bin/ps"


def _ok(m):
    print("  ok   %s" % m)


def _fail(m):
    global FAILED
    FAILED += 1
    print("  FAIL %s" % m)


def check(desc, cond):
    global RUN
    RUN += 1
    (_ok if cond else _fail)(desc)
    return bool(cond)


def eq(desc, expected, actual):
    global RUN
    RUN += 1
    if expected == actual:
        _ok(desc)
        return True
    _fail("%s (expected %r, got %r)" % (desc, expected, actual))
    return False


def skip(desc, why):
    """A tallied, LOUD skip for something this HOST cannot produce.

    Reserved for an environment property that is probed directly -- never for an
    assertion outcome. A reachable-but-wrong answer stays a hard failure everywhere.
    """
    global SKIPPED
    SKIPPED += 1
    print("  PGK_SKIP %s -- %s" % (desc, why))


def pre(desc, cond, detail=""):
    global RUN
    RUN += 1
    if cond:
        _ok("PRE  %s" % desc)
        return True
    _fail("PRE  %s %s" % (desc, detail))
    return False


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def zombie(pid):
    """True when the pid exists only as an unreaped wait status.

    kill(pid, 0) succeeds for a zombie, so "did we leave anything RUNNING" cannot be
    answered with liveness alone. This matters wherever nothing outside reaps for us: as
    PID 1 in a container, an orphan reparents to THIS process, and a SIGKILLed orphan we
    never waited on stays visible forever. A zombie holds no resources but its pid slot;
    a still-running leftover is a real failure and still fails.
    """
    out = subprocess.run([PS, "-o", "stat=", "-p", str(pid)],
                         capture_output=True, text=True, check=False).stdout.strip()
    return out.startswith("Z")


def members(pgid):
    out = subprocess.run([PS, "-o", "pid=,pgid=", "-A"],
                         capture_output=True, text=True, check=False).stdout
    return [int(l.split()[0]) for l in out.splitlines()
            if len(l.split()) == 2 and l.split()[1].isdigit() and int(l.split()[1]) == pgid]


def _binding_is_immutable(b):
    try:
        b.target_pid = 999
        return False
    except AttributeError:
        return True


def fx(n):
    return os.path.join(FIX, n)


def start(*argv):
    return K.spawn_process_group([PY, "-I"] + list(argv))


def probe(name, timeout=60):
    """Run a probe fixture in THIS session.

    start_new_session is deliberately NOT used: a session leader cannot join another
    group in its session (setpgid -> EPERM, verified), and the live-group-shift probes
    exist precisely to move themselves between groups.
    """
    r = subprocess.run([PY, "-I", fx(name), HERE], capture_output=True, text=True,
                       timeout=timeout)
    if r.returncode != 0 or not r.stdout.strip():
        print("     probe %s rc=%s stderr=%s" % (name, r.returncode, r.stderr.strip()[:800]))
    return r.stdout


def marker(txt, prefix):
    for line in txt.splitlines():
        if line.startswith(prefix):
            return line
    return ""


def state_of(outcome):
    """The state of an Outcome, or a readable marker when there is no Outcome at all.

    _deliver() returns None for a DELIVERED signal, so a mutant that returns None for a
    failed delivery hands this test a None. That must make the assertion FAIL and let the
    run continue to its cleanup -- an AttributeError here would abort mid-run, leak the
    spawned targets, and report a crash where a red assertion is the actual finding.
    """
    return getattr(outcome, "state", "<not an Outcome: %r>" % (outcome,))


def field_of(outcome, name):
    return getattr(outcome, name, "<not an Outcome: %r>" % (outcome,))


print("\n--- safe process-group signaling kernel ---")
print("--- PROCESS_GROUP_SUPERVISION_ONLY / PROCESS_TREE_CONTAINMENT_NOT_PROVIDED ---")
print("--- REGISTERED_IN_CANONICAL_SUITE (run_all.sh) ---")

KSRC = open(os.path.join(HERE, "lib_process_group.py"), encoding="utf-8").read()
# Non-vacuous: the phrases must be absent AND the scanned file must really be the
# kernel. An absence-only scan passes on an empty or wrong file.
check("the scanned file really is the kernel",
      "def terminate_bound_group" in KSRC
      and "PROCESS_TREE_CONTAINMENT_NOT_PROVIDED" in KSRC and len(KSRC) > 4000)
low = KSRC.lower()
for phrase in ("process tree owned", "whole tree terminated", "no leaked descendants",
               "sandboxed", "host isolated", "grandchildren contained"):
    check("no %r claim" % phrase, phrase not in low)
for field in ("leaked", "process_tree_clean", "descendants_terminated"):
    check("no %r field" % field, ('"%s"' % field) not in KSRC)
eq("the binding stores exactly two fields and nothing else",
   ("_target_pid", "_initial_pgid"), K.Binding.__slots__)
check("the binding is immutable",
      _binding_is_immutable(K.Binding(target_pid=123, initial_pgid=123)))
check("live os.getpgrp() is consulted", "os.getpgrp()" in KSRC)
check("the residual pid/pgid recycling race is documented",
      "reused once released" in KSRC and "NOT eliminated" in KSRC)
# Group membership is observed through ps. If ps is missing, several preconditions would
# silently degrade into "the group looks empty", so prove the instrument works first.
check("ps is available and can observe group membership at all",
      os.path.exists(PS) and os.getpid() in members(os.getpgrp()))

# ---------------------------------------------------------------------------
# 0. an unstartable target is a STATE, never a traceback
# ---------------------------------------------------------------------------
print("\n[0 the target cannot be started at all]")
bad0 = K.spawn_process_group([])
eq("an empty argv is PROCESS_START_FAILED", "PROCESS_START_FAILED", state_of(bad0))
check("the reason says what was wrong",
      "non-empty array" in (field_of(bad0, "reason") or ""))
missing = os.path.join(tempfile.gettempdir(), "plumbline-pgk-no-such-binary-%d" % os.getpid())
pre("the binary really does not exist", not os.path.exists(missing), missing)
bad1 = K.spawn_process_group([missing])
eq("an unstartable binary is PROCESS_START_FAILED", "PROCESS_START_FAILED", state_of(bad1))
check("the reason names the binary that could not be started",
      missing in (field_of(bad1, "reason") or ""))
check("no exit code and no signal number are invented for a target that never ran",
      field_of(bad1, "exit_code") is None and field_of(bad1, "signal_number") is None)

# ---------------------------------------------------------------------------
# 1. leader ends on TERM, member stays in the SAME pgid  (the headline case)
# ---------------------------------------------------------------------------
print("\n[1 leader ends, member of the same PGID survives]")
logf = os.path.join(tempfile.gettempdir(), "plumbline-pgk-%d.log" % os.getpid())
open(logf, "w").close()
proc, b = start(fx("leader_with_member.py"), logf)
CLEANUP.append(b.target_pid)
time.sleep(1.6)
lines = open(logf, encoding="utf-8").read().strip().splitlines()
member_pid = member_pgid = None
for l in lines:
    if l.startswith("MEMBER"):
        member_pid = int(l.split()[1].split("=")[1])
        member_pgid = int(l.split()[3].split("=")[1])
if member_pid:
    CLEANUP.append(member_pid)
pre("the leader started and leads its group", b.initial_pgid == b.target_pid)
pre("a member exists in the SAME bound pgid", member_pgid == b.initial_pgid,
    "(bound=%s member=%s)" % (b.initial_pgid, member_pgid))
pre("the member really ignores SIGTERM", any("term=ignored" in l for l in lines))
pre("both are in the group before termination",
    sorted(members(b.initial_pgid)) == sorted([b.target_pid, member_pid or -1]))

st = K.terminate_bound_group(proc, b, grace_seconds=3)
time.sleep(0.3)
eq("state is GROUP_STATE_UNVERIFIED", "GROUP_STATE_UNVERIFIED", st.state)
eq("target_reaped is reported", True, st.target_reaped)
eq("group_still_observable is reported", True, st.group_still_observable)
eq("additional_signal_sent is false", False, st.additional_signal_sent)
check("no success state is claimed",
      st.state not in ("GROUP_TIMEOUT_TERMINATED", "GROUP_TIMEOUT_KILLED",
                       "OK", "TARGET_EXITED"))
check("the surviving member is real, and the state says so rather than hiding it",
      member_pid is not None and alive(member_pid))
try:
    os.unlink(logf)
except OSError:
    pass

# ---------------------------------------------------------------------------
# 1b. target ignores SIGTERM -> the escalation path must actually run
# ---------------------------------------------------------------------------
print("\n[1b target ignores SIGTERM, escalation to SIGKILL]")
proc1b, b1b = start(fx("ignores_term.py"))
CLEANUP.append(b1b.target_pid)
time.sleep(0.6)
pre("the target is alive and leads its group",
    alive(b1b.target_pid) and b1b.initial_pgid == b1b.target_pid)
pre("the target really declared SIGTERM ignored", b1b.target_pid in members(b1b.initial_pgid))
st1b = K.terminate_bound_group(proc1b, b1b, grace_seconds=2)
eq("state is GROUP_TIMEOUT_KILLED", "GROUP_TIMEOUT_KILLED", st1b.state)
eq("the escalation is reported", True, st1b.additional_signal_sent)
eq("the target was reaped", True, st1b.target_reaped)
eq("it died by a signal, not by an exit", int(signal.SIGKILL), st1b.signal_number)
eq("the group is empty afterwards", [], members(b1b.initial_pgid))

# ---------------------------------------------------------------------------
# 1c. the plain success path: SIGTERM suffices and the group is really gone
# ---------------------------------------------------------------------------
# The kernel's primary success state had no positive assertion anywhere: every
# GROUP_TIMEOUT_TERMINATED in this file was a negative check or one branch of a
# disjunction. A success state nothing pins is a success state nothing defends.
print("\n[1c SIGTERM suffices: GROUP_TIMEOUT_TERMINATED]")
proc1c, b1c = start(fx("hangs.py"))
CLEANUP.append(b1c.target_pid)
time.sleep(0.4)
pre("the target is alive, leads its group, and installs no SIGTERM handler",
    alive(b1c.target_pid) and b1c.target_pid == b1c.initial_pgid)
pre("the group holds exactly the target",
    members(b1c.initial_pgid) == [b1c.target_pid],
    "(members=%r target=%d)" % (members(b1c.initial_pgid), b1c.target_pid))
st1c = K.terminate_bound_group(proc1c, b1c, grace_seconds=3)
eq("state is GROUP_TIMEOUT_TERMINATED", "GROUP_TIMEOUT_TERMINATED", st1c.state)
eq("no escalation was needed or claimed", False, st1c.additional_signal_sent)
eq("the group is reported gone", False, st1c.group_still_observable)
eq("the target was reaped", True, st1c.target_reaped)
eq("it died by SIGTERM, not by an exit", int(signal.SIGTERM), st1c.signal_number)
check("no exit code is invented for a signal death", st1c.exit_code is None)
eq("the group is really empty afterwards", [], members(b1c.initial_pgid))

# ---------------------------------------------------------------------------
# 2. a binding naming this process's LIVE group is refused
# ---------------------------------------------------------------------------
print("\n[2 forged binding names the CURRENT supervisor group]")
# Become our own group leader if we are not already one. A SESSION leader already is
# (pgid == pid) and setpgid would fail with EPERM -- an earlier revision called it
# unconditionally and simply died there, which made the whole module unobservable.
eq("no stored supervisor/parent field exists that a forger could set",
   ("_target_pid", "_initial_pgid"), K.Binding.__slots__)
# PID 1 would make this case test the WRONG guard, silently. Measured on Linux, not
# theorised: `bash -c 'python3 thisfile'` in a container makes bash exec the lone command,
# so the test IS pid 1. Pid 1 is its own group leader, so a "we lead our own group" check
# passes -- but validate_bound_group then refuses at "pid <= 1 is not signalable" and never
# reaches the self-group guard, leaving the state assertion green while proving nothing.
# Probed directly, tallied, and loud. Unreachable through run_all.sh, where this file is
# always a child of bash.
if os.getpid() <= 1:
    skip("case 2 (the LIVE self-group guard)",
         "this process is PID %d, so the 'pid <= 1 is not signalable' guard answers before "
         "the self-group guard can be reached; the case cannot be constructed here -- run "
         "this file as a child process, not as a container entrypoint" % os.getpid())
else:
    if os.getpgrp() != os.getpid():
        try:
            os.setpgid(0, 0)
        except PermissionError:
            pass
    me, mypg = os.getpid(), os.getpgrp()
    pre("this process now leads its own group", me == mypg, "(pid=%s pgrp=%s)" % (me, mypg))
    pre("our own pid is signalable, so the self-group guard is the guard reached",
        me > 1, "(pid=%s)" % me)
    v = K.validate_bound_group(K.Binding(target_pid=me, initial_pgid=mypg))
    eq("a binding naming our live group is refused", "SIGNAL_TARGET_UNVERIFIED", v.state)
    check("the refusal names the LIVE self group", "live group" in (v.reason or ""))

# ---------------------------------------------------------------------------
# 2b. a binding that does not name a group LEADER is refused
# ---------------------------------------------------------------------------
# This case was missing entirely: no test ever built a binding with
# target_pid != initial_pgid, so the static leadership check could be deleted with the
# suite fully green. A guard nothing constructs an input for is not covered.
print("\n[2b binding whose pid does not lead its pgid]")
proc2b, b2b = start(fx("hangs.py"))
CLEANUP.append(b2b.target_pid)
not_leader = K.Binding(target_pid=b2b.target_pid, initial_pgid=b2b.initial_pgid + 7)
pre("the binding really names a pid that does not lead that pgid",
    not_leader.target_pid != not_leader.initial_pgid)
# The live lookups are COUNTED, not inferred from the wording of the reason. Delete the
# static leadership guard and the drift guard refuses instead -- same state, and a reason
# that still mentions no lookup -- so only a count can tell which stage actually answered.
_real_getpgid = os.getpgid
_lookups = {"n": 0}


def _counting_getpgid(pid):
    _lookups["n"] += 1
    return _real_getpgid(pid)


os.getpgid = _counting_getpgid
try:
    v2b = K.validate_bound_group(not_leader)
finally:
    os.getpgid = _real_getpgid
eq("a non-leader binding is refused", "SIGNAL_TARGET_UNVERIFIED", v2b.state)
check("the refusal names the leadership requirement",
      "does not name a group leader" in (v2b.reason or ""))
eq("the refusal really precedes EVERY live lookup (counted)", 0, _lookups["n"])
K.terminate_bound_group(proc2b, b2b, grace_seconds=2)

# ---------------------------------------------------------------------------
# 3. a binding naming the CALLER's live group is refused (real parent/child)
# ---------------------------------------------------------------------------
print("\n[3 forged binding names the CURRENT parent group]")
out = subprocess.run([PY, "-I", fx("parent_group_probe.py"), HERE],
                     capture_output=True, text=True)
txt = out.stdout
pre("the probe established a real parent/child pair", "CHILD ppid=" in txt, txt[:160])
ok_match = False
for l in txt.splitlines():
    if l.startswith("CHILD "):
        live = l.split()[2].split("=")[1]
        claimed = l.split()[3].split("=")[1]
        ok_match = live == claimed
pre("the child's LIVE parent-group lookup matched the claimed group", ok_match, txt[:200])
check("the child refused a binding naming its caller's group",
      "state=SIGNAL_TARGET_UNVERIFIED" in txt)
check("the refusal names the caller's LIVE group", "caller's live group" in txt)

# ---------------------------------------------------------------------------
# 4. the supervisor's OWN group changes AFTER the binding -> refused
# ---------------------------------------------------------------------------
# The binding is byte-identical across the two verdicts; only the supervisor's live
# group moved. A verdict that does not change here means os.getpgrp() was not read live.
print("\n[4 the live supervisor group changes under an unchanged binding]")
p4 = probe("supervisor_group_shift_probe.py")
pre("the probe is not a session leader (a session leader cannot shift groups)",
    "session_leader=False" in marker(p4, "PROBE "), marker(p4, "PROBE "))
pre("the target leads its own group", "TARGET_LEADS_GROUP True" in p4)
pre("the target shares our session (a prerequisite for the shift)",
    "TARGET_SAME_SESSION True" in p4)
pre("the caller's group is NOT the target group, so only the self guard can answer",
    "PARENT_GROUP_DIFFERS True" in p4)
pre("the same binding was VALID before the shift", "BEFORE_SHIFT state=VALID" in p4,
    marker(p4, "BEFORE_SHIFT"))
pre("the supervisor really joined the target's group",
    "equals_target_group=True" in marker(p4, "SHIFTED "), marker(p4, "SHIFTED "))
check("after the shift the same binding is refused",
      "AFTER_SHIFT state=SIGNAL_TARGET_UNVERIFIED" in p4)
check("the refusal names THIS process's live group",
      "this process's live group" in marker(p4, "AFTER_SHIFT"))
check("the probe cleaned up its target", "CLEANED target_gone=True" in p4)

# ---------------------------------------------------------------------------
# 5 + 15. the CALLER's group changes DURING the grace period, and the
#         re-validation that precedes the SIGKILL catches it
# ---------------------------------------------------------------------------
# This is the only place where the pre-SIGKILL re-validation can be OBSERVED: SIGTERM
# has been sent and ignored, the escalation is one step away, and the parent moves into
# the target's group in between. Delete the re-validation and the SIGKILL goes out.
print("\n[5+15 the live caller group changes during the grace period]")
p5 = probe("parent_group_shift_probe.py")
pre("A is not a session leader", "session_leader=False" in marker(p5, "A pid="),
    marker(p5, "A pid="))
pre("B is a real forked supervisor with A as its parent", marker(p5, "B pid=") != "",
    p5[:200])
pre("the target group is not B's own group", "B_TARGET_GROUP_IS_NOT_OURS True" in p5)
pre("B's first validation, before the shift, was VALID", "B_BEFORE state=VALID" in p5,
    marker(p5, "B_BEFORE"))
pre("A really joined the target group",
    "equals_target_group=True" in marker(p5, "A_SHIFTED"), marker(p5, "A_SHIFTED"))
pre("the shift landed INSIDE the grace period", "shift_at=0.6" in marker(p5, "B_ELAPSED")
    and float(marker(p5, "B_ELAPSED").split()[1]) >= 1.9, marker(p5, "B_ELAPSED"))
pre("B's LIVE parent-group lookup now returns the target group",
    marker(p5, "B_LIVE_PARENT_PGID").split()[1]
    == marker(p5, "B_LIVE_PARENT_PGID").split()[2].split("=")[1],
    marker(p5, "B_LIVE_PARENT_PGID"))
check("the escalation is refused, not sent",
      "B_RESULT state=SIGNAL_TARGET_UNVERIFIED" in p5)
check("the refusal names the caller's LIVE group",
      "caller's live group" in marker(p5, "B_RESULT"))
check("no additional signal is claimed",
      "additional_signal_sent=False" in marker(p5, "B_FIELDS"))
check("the target is reported as still running", "target_still_running=True" in marker(p5, "B_FIELDS"))
check("no exit code or signal number is invented",
      "exit_code=None signal_number=None" in marker(p5, "B_FIELDS"))
check("the target really survived, because no SIGKILL was sent",
      "B_TARGET_ALIVE True" in p5)
check("B cleaned up its target", "B_CLEANED target_gone=True" in p5)

# ---------------------------------------------------------------------------
# 6. SIGCHLD=SIG_IGN -- a signal death must never become a clean exit
# ---------------------------------------------------------------------------
print("\n[6 SIGCHLD=SIG_IGN, target SIGKILLed]")
old = signal.signal(signal.SIGCHLD, signal.SIG_IGN)
try:
    proc6, b6 = start(fx("hangs.py"))
    time.sleep(0.4)
    pre("the target is alive before the kill", alive(b6.target_pid))
    os.kill(b6.target_pid, signal.SIGKILL)
    time.sleep(0.4)
    st6 = K.reap_process(proc6, timeout=3)
    eq("ECHILD is never TARGET_EXITED", "TARGET_STATUS_UNVERIFIED", st6.state)
    check("no exit code is invented", st6.exit_code is None)
    check("the reason names ECHILD", "ECHILD" in (st6.reason or ""))
    eq("target_reaped is false", False, st6.target_reaped)
finally:
    signal.signal(signal.SIGCHLD, old)

# ---------------------------------------------------------------------------
# 7/8. real signal deaths
# ---------------------------------------------------------------------------
for label, sig in (("7 SIGTERM", signal.SIGTERM), ("8 SIGKILL", signal.SIGKILL)):
    print("\n[%s kills the target]" % label)
    proc7, b7 = start(fx("hangs.py"))
    time.sleep(0.3)
    pre("the target is alive before the signal", alive(b7.target_pid))
    os.kill(b7.target_pid, sig)
    st7 = K.reap_process(proc7, timeout=5)
    eq("state is TARGET_SIGNALED", "TARGET_SIGNALED", st7.state)
    eq("the signal number is reported", int(sig), st7.signal_number)
    check("no exit code is invented", st7.exit_code is None)
    eq("target_reaped is true", True, st7.target_reaped)

# ---------------------------------------------------------------------------
# 8b. a real NORMAL exit keeps its real code
# ---------------------------------------------------------------------------
# Without this, "a normal exit only on an observed normal wait status" has no positive
# evidence: every other TARGET_EXITED assertion in this file is a negative one. The code 7
# is chosen because neither failure mode can produce it -- a signal death carries no exit
# code at all, and the ECHILD launder produced 0.
print("\n[8b a real normal exit reports its real code]")
proc8b, b8b = start(fx("exits.py"), "7")
pre("the target started and leads its own group",
    b8b.target_pid > 1 and b8b.target_pid == b8b.initial_pgid)
st8b = K.reap_process(proc8b, timeout=5)
eq("state is TARGET_EXITED", "TARGET_EXITED", st8b.state)
eq("the real exit code is reported, not 0 and not None", 7, st8b.exit_code)
check("no signal number is invented", st8b.signal_number is None)
eq("target_reaped is true", True, st8b.target_reaped)

# ---------------------------------------------------------------------------
# 9. getpgid(target) ESRCH
# ---------------------------------------------------------------------------
print("\n[9 getpgid(target) returns ESRCH]")
proc9, b9 = start(fx("exits.py"), "0")
K.reap_process(proc9, timeout=5)
pre("the bound pid is really gone", not alive(b9.target_pid))
v9 = K.validate_bound_group(b9)
eq("a failed target lookup refuses to signal", "SIGNAL_TARGET_UNVERIFIED", v9.state)
check("the refusal names the lookup and rejects a pid substitute",
      "getpgid" in (v9.reason or "") and "not a substitute" in (v9.reason or ""))

# ---------------------------------------------------------------------------
# 10. getpgid(parent) ESRCH -- FAULT-INJECTED, and named as such
# ---------------------------------------------------------------------------
# The real OS cannot produce it: an orphan is reparented to pid 1 (launchd on macOS) and
# getpgid(1) succeeds. The ESRCH is injected at the syscall boundary for the parent pid
# only. The control run pins the attribution: the SAME binding is VALID without the
# injection, so nothing else can be causing the refusal.
print("\n[10 getpgid(parent) returns ESRCH -- injected at the syscall boundary]")
p10 = probe("parent_lookup_esrch_probe.py")
pre("the target leads its own group", "leads_group=True" in marker(p10, "TARGET "))
pre("CONTROL: the same binding is VALID without the injection",
    "CONTROL state=VALID" in p10, marker(p10, "CONTROL"))
pre("the injection really raises ESRCH for the parent pid",
    "INJECTION_ACTIVE True" in p10, marker(p10, "INJECTION_ACTIVE"))
pre("the target lookup stays REAL under the injection",
    "target_lookup_still_real=True" in marker(p10, "INJECTION_ACTIVE"))
check("a failed parent lookup refuses to signal",
      "INJECTED state=SIGNAL_TARGET_UNVERIFIED" in p10)
check("the refusal names the parent lookup",
      "getpgid(parent) failed" in marker(p10, "INJECTED"))
check("the refusal says the caller's group cannot be ruled out, rather than falling back",
      "cannot be ruled out as the signal target" in marker(p10, "INJECTED"))
check("the kernel really performed a LIVE parent lookup",
      int(marker(p10, "LOOKUPS").split()[1].split("=")[1]) >= 2)

# ---------------------------------------------------------------------------
# 11. killpg ESRCH -- never a success
# ---------------------------------------------------------------------------
print("\n[11 killpg returns ESRCH]")
p11, b11 = start(fx("exits.py"), "0")
K.reap_process(p11, timeout=5)
pre("the group is really gone", not K.group_observable(b11.initial_pgid))
res11 = K._deliver(b11.initial_pgid, signal.SIGTERM)
check("delivery to a vanished group is not success", res11 is not None)
eq("it is GROUP_STATE_UNVERIFIED", "GROUP_STATE_UNVERIFIED", state_of(res11))
eq("no additional signal is claimed", False, field_of(res11, "additional_signal_sent"))

# ---------------------------------------------------------------------------
# 12. killpg EPERM -> SIGNAL_DELIVERY_FAILED
# ---------------------------------------------------------------------------
print("\n[12 killpg returns EPERM]")
foreign = None
psout = subprocess.run([PS, "-o", "pgid=,user=", "-A"],
                       capture_output=True, text=True).stdout
for line in psout.splitlines():
    parts = line.split()
    if len(parts) == 2 and parts[0].isdigit() and parts[1] == "root" and int(parts[0]) > 1:
        pg = int(parts[0])
        try:
            os.killpg(pg, 0)
        except PermissionError:
            foreign = pg
            break
        except OSError:
            continue
if foreign is None:
    # An environment property, probed directly -- not an assertion outcome. Where we may
    # signal every group that exists (root in a container, which is how this suite runs on
    # some Linux images) EPERM cannot be produced at all, and failing here would report the
    # kernel as broken because the HOST is permissive. Narrow: only these four assertions
    # are skipped, only on this probe. A group that IS found is asserted hard on every OS,
    # and a reachable-but-WRONG answer is a hard failure everywhere.
    skip("case 12 (killpg EPERM)",
         "no process group on this host refuses our signal (uid=%d), so EPERM is "
         "unproducible and its four assertions are NOT evidence on this run" % os.getuid())
else:
    pre("a group we may not signal was found", True, "(pgid %d)" % foreign)
    res12 = K._deliver(foreign, signal.SIGTERM)
    check("EPERM is not success", res12 is not None)
    eq("it is SIGNAL_DELIVERY_FAILED", "SIGNAL_DELIVERY_FAILED", state_of(res12))
    check("the reason names the refusal", "refused" in (field_of(res12, "reason") or ""))

# ---------------------------------------------------------------------------
# 13. the wait status is gone because someone ELSE collected it
# ---------------------------------------------------------------------------
# Distinct from case 6: no SIGCHLD disposition is touched. The status is simply already
# claimed, which is the general shape of ECHILD.
print("\n[13 the wait status was already collected elsewhere -> ECHILD]")
proc13, b13 = start(fx("exits.py"), "7")
time.sleep(0.4)
wpid13, raw13 = os.waitpid(b13.target_pid, 0)
pre("the test itself collected the status first, outside the kernel",
    wpid13 == b13.target_pid and os.WIFEXITED(raw13) and os.WEXITSTATUS(raw13) == 7,
    "(wpid=%s status=%r)" % (wpid13, raw13))
pre("SIGCHLD is untouched (this is not the case-6 mechanism)",
    signal.getsignal(signal.SIGCHLD) is not signal.SIG_IGN)
st13 = K.reap_process(proc13, timeout=3)
eq("a status that is gone is TARGET_STATUS_UNVERIFIED", "TARGET_STATUS_UNVERIFIED", st13.state)
check("the real exit code 7 is NOT invented from elsewhere", st13.exit_code is None)
check("the reason names ECHILD", "ECHILD" in (st13.reason or ""))
eq("target_reaped is false", False, st13.target_reaped)

# ---------------------------------------------------------------------------
# 14. the reap fails AFTER a real SIGKILL -- REAP_FAILED must survive
# ---------------------------------------------------------------------------
# FAULT-INJECTED observation, real signal: os.waitpid starts failing the moment the real
# SIGKILL has been sent, so the named path -- a reap failure after the escalation -- is
# the one entered. Scenario B covers the refusal half of the same rule.
print("\n[14 reap failure after the real SIGKILL, and after a refusal]")
p14 = probe("reap_failure_probe.py")
pre("the target was alive before the escalation", "alive=True" in marker(p14, "A_TARGET"))
pre("a REAL SIGKILL was sent to the bound group",
    "A_SIGKILL_WAS_REAL True" in p14, marker(p14, "A_SIGKILL_WAS_REAL"))
pre("the reap succeeded during the grace period and failed only afterwards",
    int(marker(p14, "A_SIGKILL_WAS_REAL").split()[2].split("=")[1]) > 0
    and int(marker(p14, "A_SIGKILL_WAS_REAL").split()[3].split("=")[1]) > 0,
    marker(p14, "A_SIGKILL_WAS_REAL"))
check("the state is REAP_FAILED", "A_RESULT state=REAP_FAILED" in p14)
check("REAP_FAILED is not replaced by ANY group-level state",
      not any(s in marker(p14, "A_RESULT") for s in
              ("GROUP_TIMEOUT_KILLED", "GROUP_TIMEOUT_TERMINATED",
               "GROUP_STATE_UNVERIFIED")))
check("the escalation that did happen is still reported",
      "additional_signal_sent=True" in marker(p14, "A_RESULT"))
check("no exit code and no signal number are invented",
      "exit_code=None signal_number=None" in marker(p14, "A_RESULT"))
check("the reason names the failed wait", "waitpid" in marker(p14, "A_REASON"))
check("the SIGKILL really killed the target (only the observation was injected)",
      "A_REAL_STATUS state=TARGET_SIGNALED signal_number=9 target_gone=True" in p14)
pre("scenario B really used a non-leader binding",
    "leads_group=False" in marker(p14, "B_BINDING"))
check("a refusal keeps its own state", "B_RESULT state=SIGNAL_TARGET_UNVERIFIED" in p14)
check("a refusal claims no additional signal",
      "additional_signal_sent=False" in marker(p14, "B_RESULT"))
check("the refusal DISCLOSES the reap failure instead of dropping it",
      "additionally" in marker(p14, "B_REASON") and "waitpid" in marker(p14, "B_REASON"))

# ---------------------------------------------------------------------------
# the bound pgid still resolves, but the target has LEFT that group
# ---------------------------------------------------------------------------
# The destination is a third group -- neither ours nor the caller's -- so the drift check
# is the only guard that can answer. Without it the kernel would signal a group the
# target no longer belongs to.
print("\n[drift: the target moved out of the bound group]")
pd = probe("pgid_drift_probe.py")
pre("the binding was VALID before the move", "BEFORE_DRIFT state=VALID" in pd,
    marker(pd, "BEFORE_DRIFT"))
pre("the destination is a THIRD group, not ours and not the caller's",
    "DEST_IS_A_THIRD_GROUP True" in pd)
pre("the target really left the bound group",
    "drifted=True" in marker(pd, "LIVE_TARGET_PGID"), marker(pd, "LIVE_TARGET_PGID"))
check("the moved target is refused", "AFTER_DRIFT state=SIGNAL_TARGET_UNVERIFIED" in pd)
check("the refusal names the drift, not some later guard",
      "pgid drift" in marker(pd, "AFTER_DRIFT"))
check("the probe left nothing behind", "CLEANED survivors=[]" in pd)

# ---------------------------------------------------------------------------
# boundary: an escaped child survives, and nothing claims otherwise
# ---------------------------------------------------------------------------
print("\n[boundary: a child leaves the group and survives]")
elog = os.path.join(tempfile.gettempdir(), "plumbline-pgk-esc-%d.log" % os.getpid())
open(elog, "w").close()
pe, be = start(fx("escapes_setsid.py"), elog)
CLEANUP.append(be.target_pid)
time.sleep(1.2)
escaped = []
for line in open(elog, encoding="utf-8"):
    for tok in line.split():
        if tok.startswith("pid="):
            escaped.append(int(tok.split("=")[1]))
pre("the escaping child really detached and logged itself", bool(escaped))
ste = K.terminate_bound_group(pe, be, grace_seconds=2)
check("the bound group was handled without any descendant claim",
      ste.state in ("GROUP_TIMEOUT_TERMINATED", "GROUP_TIMEOUT_KILLED",
                    "GROUP_STATE_UNVERIFIED"))
check("no descendant field exists on the outcome",
      not any(hasattr(ste, f) for f in ("leaked", "process_tree_clean",
                                        "descendants_terminated")))
check("BOUNDARY (not a defect): the escaped child survives", any(alive(p) for p in escaped))
CLEANUP.extend(escaped)
try:
    os.unlink(elog)
except OSError:
    pass

# ---------------------------------------------------------------------------
print("\n[cleanup: explicit logged pids only]")
for pid in CLEANUP:
    if pid and alive(pid):
        try:
            os.kill(pid, signal.SIGKILL)
            print("  cleaned pid %d" % pid)
        except OSError as exc:
            print("  could not clean %d: %s" % (pid, exc))
# Reap whatever this process happens to be the parent of. Where nothing outside reaps for
# us -- PID 1 in a container -- an orphan reparents here, and skipping this would leave a
# zombie that kill(pid, 0) still answers for.
for pid in CLEANUP:
    if pid:
        try:
            os.waitpid(pid, os.WNOHANG)
        except OSError:
            pass
time.sleep(0.4)
survivors = [p for p in CLEANUP if p and alive(p) and not zombie(p)]
zombies = [p for p in CLEANUP if p and alive(p) and zombie(p)]
if zombies:
    print("  reaped-or-zombie (holding only a pid slot, not running): %r" % zombies)
eq("no recorded pid is still RUNNING", [], survivors)

print("\nprocess group kernel tests: %d run, %d failed, %d skipped" % (RUN, FAILED, SKIPPED))
if SKIPPED:
    print("  NOTE: %d host-limitation skip(s) above are NOT evidence -- see PGK_SKIP" % SKIPPED)
sys.exit(1 if FAILED else 0)
