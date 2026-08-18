"""Safe Process-Group Signaling Kernel.

UNMAPPED_CHANGE: hermetic test and interpreter runtime contract
(no confirmed Jira key exists for this work; none was guessed)

PRODUCT BOUNDARY -- binding, stated before anything else:

    PROCESS_GROUP_SUPERVISION_ONLY
    PROCESS_TREE_CONTAINMENT_NOT_PROVIDED

This kernel starts a target in its own session and process group and signals ONLY a
group whose identity it has just re-established from live OS facts. It says nothing
about descendants and exposes no field that could be read as such a claim.

WHAT IT DOES NOT DO: capture output, impose output limits, create temporary
directories, delete anything, emit a CLI report, touch the canonical suite, resolve a
toolchain, or filter the environment.

AUTHORITY. The binding carries only `target_pid` and `initial_pgid` -- the two values
that name what was bound. It carries NO supervisor or parent group, because a stored
value is a claim by whoever built the structure: an earlier revision could be handed a
forged binding that made this process's OWN live group look acceptable. Every value
that decides whether a signal is safe is read from the OS immediately before the
signal -- os.getpgrp(), os.getppid(), os.getpgid(parent), os.getpgid(target). Safety
therefore does not depend on nobody being able to construct a Binding.

A failed getpgid() is never replaced by the pid. "I could not identify the group" and
"the group is the pid" are different statements.

THE GROUP LEADER IS THE ONLY ANCHOR. Group identity is re-confirmed through
getpgid(target_pid). Once the bound leader is gone, that anchor is gone with it: the
pgid may still name a live group, but nothing proves it is still the same group. When
the leader has ended and the group is still observable, this kernel does NOT signal
again and says so -- GROUP_STATE_UNVERIFIED. It does not report a termination it
cannot stand behind.

RESIDUAL RACE, named rather than claimed away: POSIX allows a pid and a pgid to be
reused once released. Between a passing validation and the killpg that follows, the
kernel holds no lock. The window is narrow and the checks make a wrong target
unlikely, but it is NOT eliminated, and nothing here should be read as if it were.

Standard library only.
"""

import os
import signal
import subprocess
import time

STATE_TARGET_EXITED = "TARGET_EXITED"
STATE_TARGET_SIGNALED = "TARGET_SIGNALED"
STATE_GROUP_TIMEOUT_TERMINATED = "GROUP_TIMEOUT_TERMINATED"
STATE_GROUP_TIMEOUT_KILLED = "GROUP_TIMEOUT_KILLED"
STATE_GROUP_STATE_UNVERIFIED = "GROUP_STATE_UNVERIFIED"
STATE_SIGNAL_TARGET_UNVERIFIED = "SIGNAL_TARGET_UNVERIFIED"
STATE_SIGNAL_DELIVERY_FAILED = "SIGNAL_DELIVERY_FAILED"
STATE_PROCESS_START_FAILED = "PROCESS_START_FAILED"
STATE_REAP_FAILED = "REAP_FAILED"
STATE_TARGET_STATUS_UNVERIFIED = "TARGET_STATUS_UNVERIFIED"
STATE_VALID = "VALID"


class Binding:
    """What was bound. Two values, immutable, and no security authority of its own."""

    __slots__ = ("_target_pid", "_initial_pgid")

    def __init__(self, target_pid, initial_pgid):
        object.__setattr__(self, "_target_pid", target_pid)
        object.__setattr__(self, "_initial_pgid", initial_pgid)

    @property
    def target_pid(self):
        return self._target_pid

    @property
    def initial_pgid(self):
        return self._initial_pgid

    def __setattr__(self, name, value):
        raise AttributeError("Binding is immutable (%s)" % name)

    def __repr__(self):
        return "Binding(target_pid=%r, initial_pgid=%r)" % (self._target_pid, self._initial_pgid)


class Outcome:
    """One state plus only the facts that state actually carries."""

    __slots__ = ("state", "exit_code", "signal_number", "reason",
                 "target_reaped", "target_still_running",
                 "group_still_observable", "additional_signal_sent")

    def __init__(self, state, exit_code=None, signal_number=None, reason=None,
                 target_reaped=None, target_still_running=None,
                 group_still_observable=None, additional_signal_sent=None):
        self.state = state
        self.exit_code = exit_code
        self.signal_number = signal_number
        self.reason = reason
        self.target_reaped = target_reaped
        self.target_still_running = target_still_running
        self.group_still_observable = group_still_observable
        self.additional_signal_sent = additional_signal_sent

    def __repr__(self):
        return ("Outcome(state=%r, exit_code=%r, signal_number=%r, target_reaped=%r, "
                "target_still_running=%r, group_still_observable=%r, "
                "additional_signal_sent=%r, reason=%r)"
                % (self.state, self.exit_code, self.signal_number, self.target_reaped,
                   self.target_still_running, self.group_still_observable,
                   self.additional_signal_sent, self.reason))


def _unverified(reason):
    return Outcome(STATE_SIGNAL_TARGET_UNVERIFIED, reason=reason)


def spawn_process_group(argv):
    """Start argv in its own session and process group.

    Returns (Popen, Binding), or Outcome(PROCESS_START_FAILED). An unstartable target
    is a state, never a traceback.
    """
    if not argv or not isinstance(argv, (list, tuple)):
        return Outcome(STATE_PROCESS_START_FAILED, reason="argv must be a non-empty array")
    try:
        proc = subprocess.Popen(list(argv), start_new_session=True)
    except OSError as exc:
        return Outcome(STATE_PROCESS_START_FAILED,
                       reason="could not start %r: %s" % (argv[0], exc))
    try:
        initial_pgid = os.getpgid(proc.pid)
    except OSError as exc:
        try:
            proc.kill()
        except OSError:
            pass
        reap_process(proc, timeout=5)
        return Outcome(STATE_PROCESS_START_FAILED,
                       reason="getpgid() failed right after the spawn: %s" % exc)
    return proc, Binding(target_pid=proc.pid, initial_pgid=initial_pgid)


def validate_bound_group(binding):
    """Re-establish, from LIVE OS facts, that this group is safe to signal NOW.

    Returns Outcome(VALID) or Outcome(SIGNAL_TARGET_UNVERIFIED, reason). Anything other
    than VALID means: do not signal.
    """
    # Shape of what was bound -- cheap, and independent of anything running.
    if binding.target_pid is None or binding.target_pid <= 1:
        return _unverified("target pid %r is not a signalable process" % binding.target_pid)
    if binding.initial_pgid is None or binding.initial_pgid <= 1:
        return _unverified("refusing to signal group %r" % binding.initial_pgid)
    if binding.target_pid != binding.initial_pgid:
        return _unverified("binding does not name a group leader: pid %r, pgid %r"
                           % (binding.target_pid, binding.initial_pgid))

    # Live facts. Every one is read now; none is remembered from binding time.
    try:
        current_supervisor_pgid = os.getpgrp()
    except OSError as exc:
        return _unverified("getpgrp() failed: %s" % exc)
    try:
        current_parent_pid = os.getppid()
        current_parent_pgid = os.getpgid(current_parent_pid)
    except OSError as exc:
        return _unverified("getpgid(parent) failed: %s -- the caller's group cannot be "
                           "ruled out as the signal target" % exc)
    try:
        current_target_pgid = os.getpgid(binding.target_pid)
    except OSError as exc:
        return _unverified("getpgid(%d) failed: %s -- the group cannot be identified, "
                           "and the pid is not a substitute for it"
                           % (binding.target_pid, exc))

    if current_target_pgid != binding.initial_pgid:
        return _unverified("pgid drift: bound %r, now %r"
                           % (binding.initial_pgid, current_target_pgid))
    # NOTE: a live "does the target still lead the group" check would be DEAD here.
    # The static stage already required target_pid == initial_pgid, and the drift check
    # above required current_target_pgid == initial_pgid; leadership therefore follows.
    # A check no test can reach and no mutation can kill is not defence, it is decoration.
    if current_target_pgid == current_supervisor_pgid:
        return _unverified("group %d is this process's live group" % current_target_pgid)
    if current_target_pgid == current_parent_pgid:
        return _unverified("group %d is the caller's live group" % current_target_pgid)
    return Outcome(STATE_VALID)


def group_observable(pgid):
    """True when the group still answers. EPERM counts as observable, never as gone."""
    if not pgid or pgid <= 1:
        return False
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return True


def _target_running(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


def _classify_status(status, proc):
    """Turn one raw wait status into a state. A signal death is never an exit."""
    if os.WIFSIGNALED(status):
        sig = os.WTERMSIG(status)
        proc.returncode = -sig
        return Outcome(STATE_TARGET_SIGNALED, signal_number=sig, target_reaped=True,
                       reason="terminated by signal %d" % sig)
    if os.WIFEXITED(status):
        code = os.WEXITSTATUS(status)
        proc.returncode = code
        return Outcome(STATE_TARGET_EXITED, exit_code=code, target_reaped=True)
    return Outcome(STATE_TARGET_STATUS_UNVERIFIED, target_reaped=True,
                   reason="wait status %r is neither an exit nor a signal death" % status)


def _reap_now(proc):
    """One non-blocking attempt at the direct target's wait status.

    Returns an Outcome when something is known, and None for the one thing that is NOT
    a failure: the target has not exited yet. Reporting "not yet" as REAP_FAILED would
    invent a failure for a target nobody asked to terminate, and would make the
    "REAP_FAILED is never laundered into a success" rule unprovable, because the state
    would no longer mean what it says.

    Popen.wait() is deliberately NOT used: with SIGCHLD set to SIG_IGN the OS reaps
    children itself, Popen then reports returncode 0, and a SIGKILLed target was
    laundered into a clean successful exit. os.waitpid raises ECHILD in that case, which
    is the truth -- the status is gone and how the target ended cannot be established.
    """
    pid = proc.pid
    try:
        wpid, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return Outcome(STATE_TARGET_STATUS_UNVERIFIED, target_reaped=False,
                       target_still_running=_target_running(pid),
                       reason="waitpid(%d) reported ECHILD: the wait status is not "
                              "available (the child was reaped elsewhere, e.g. under "
                              "SIGCHLD=SIG_IGN); how it ended cannot be established"
                              % pid)
    except OSError as exc:
        return Outcome(STATE_REAP_FAILED, target_reaped=False,
                       target_still_running=_target_running(pid),
                       reason="waitpid(%d) failed: %s" % (pid, exc))
    if wpid != pid:
        return None
    return _classify_status(status, proc)


def reap_process(proc, timeout=None):
    """Wait up to `timeout` seconds for the direct target's wait status.

    A target that is still running when the budget runs out is REAP_FAILED here -- the
    caller asked for a status within a deadline and did not get one. That is a different
    statement from _reap_now()'s "not yet", which carries no deadline.
    """
    deadline = None if timeout is None else time.time() + timeout
    while True:
        out = _reap_now(proc)
        if out is not None:
            return out
        if deadline is not None and time.time() >= deadline:
            return Outcome(STATE_REAP_FAILED, target_reaped=False,
                           target_still_running=_target_running(proc.pid),
                           reason="the target did not terminate within %ss" % timeout)
        time.sleep(0.02)


def _deliver(pgid, sig):
    """Send one signal. Returns None on delivery, or a non-success Outcome."""
    try:
        os.killpg(pgid, sig)
        return None
    except ProcessLookupError as exc:
        return Outcome(STATE_GROUP_STATE_UNVERIFIED, additional_signal_sent=False,
                       group_still_observable=False,
                       reason="killpg(%d, %d): %s -- nothing received the signal, so no "
                              "termination can be claimed" % (pgid, sig, exc))
    except PermissionError as exc:
        return Outcome(STATE_SIGNAL_DELIVERY_FAILED, additional_signal_sent=False,
                       reason="killpg(%d, %d) refused: %s" % (pgid, sig, exc))
    except OSError as exc:
        return Outcome(STATE_SIGNAL_DELIVERY_FAILED, additional_signal_sent=False,
                       reason="killpg(%d, %d) failed: %s" % (pgid, sig, exc))


def terminate_bound_group(proc, binding, grace_seconds=3.0):
    """SIGTERM the bound group, wait out the grace period, escalate to SIGKILL.

    Every signal is preceded by a full live validation. Once the bound leader has
    ended, the group's identity can no longer be re-established through it, so no
    further signal is sent and the state says exactly that.
    """
    verdict = validate_bound_group(binding)
    if verdict.state != STATE_VALID:
        verdict.additional_signal_sent = False
        reaped = _reap_now(proc)
        verdict.target_still_running = _target_running(binding.target_pid)
        if reaped is not None:
            verdict.target_reaped = bool(reaped.target_reaped)
            verdict.exit_code = reaped.exit_code
            verdict.signal_number = reaped.signal_number
            if reaped.state == STATE_REAP_FAILED:
                # The refusal is the safety-critical fact and keeps the state, but the
                # reap failure is disclosed rather than dropped: a REAP_FAILED is never
                # laundered into a success, and never silently discarded either.
                verdict.reason = "%s; additionally, %s" % (verdict.reason, reaped.reason)
        else:
            verdict.target_reaped = False
        return verdict

    failure = _deliver(binding.initial_pgid, signal.SIGTERM)
    if failure is not None:
        return failure

    deadline = time.time() + grace_seconds
    reaped = None
    while time.time() < deadline:
        # None means "no status yet" -- the only answer that justifies waiting longer.
        # Anything else, including a real reap failure, ends the wait and is reported.
        reaped = _reap_now(proc)
        if reaped is not None:
            break
        time.sleep(0.05)

    escalated = False
    if reaped is None:
        # The bound leader is still alive: re-validate in full, then escalate.
        verdict = validate_bound_group(binding)
        if verdict.state != STATE_VALID:
            verdict.target_still_running = True
            verdict.target_reaped = False
            verdict.additional_signal_sent = False
            return verdict
        failure = _deliver(binding.initial_pgid, signal.SIGKILL)
        if failure is not None:
            return failure
        escalated = True
        reaped = reap_process(proc, timeout=10)

    if reaped.state == STATE_REAP_FAILED:
        reaped.additional_signal_sent = escalated
        return reaped

    if group_observable(binding.initial_pgid):
        # The leader has ended, so getpgid can no longer confirm the group's identity.
        # Something still answers this pgid; it may or may not be what was bound.
        return Outcome(STATE_GROUP_STATE_UNVERIFIED,
                       exit_code=reaped.exit_code, signal_number=reaped.signal_number,
                       target_reaped=bool(reaped.target_reaped),
                       group_still_observable=True,
                       additional_signal_sent=False,
                       reason="the bound leader has ended, so group %d can no longer be "
                              "identified through it; it is still observable and was NOT "
                              "signalled again" % binding.initial_pgid)
    state = STATE_GROUP_TIMEOUT_KILLED if escalated else STATE_GROUP_TIMEOUT_TERMINATED
    return Outcome(state, exit_code=reaped.exit_code, signal_number=reaped.signal_number,
                   target_reaped=bool(reaped.target_reaped),
                   group_still_observable=False,
                   additional_signal_sent=escalated,
                   reason=reaped.reason)
