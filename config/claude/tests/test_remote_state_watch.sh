#!/usr/bin/env bash
# PLUM-14 contract tests: a documented draft / no-merge state must be ENFORCED
# against the real remote, not only asserted in prose.
#
# Measured starting state (2026-07-30): nothing under config/claude/{lib,bin,hooks}
# read any remote or PR state. The run ledger records gates and artifact hashes, so a
# human gate whose artifact changed is caught -- but a PR that was merged, force-pushed
# or re-based UNDER an active run left no trace at all. The pilot: PR #26 was a draft,
# explicitly not cleared for merge, and was merged through GitHub anyway; Plumbline
# only noticed afterwards, by hand.
#
# Contract:
#   * an active run snapshots the expected PR / branch / base state (AC-1);
#   * base-branch, draft-status and merge-state changes are detected BEFORE further
#     writing (AC-2);
#   * an unexpected merge yields REMOTE_STATE_CHANGED and blocks until the run is
#     re-evaluated (AC-3);
#   * the audit names the account and mechanism WITHOUT speculating human vs
#     automation (AC-5);
#   * merge, force-push, base-change and draft-change are all covered (AC-6).
#
# The git-side detections (merge, force-push, base-advanced, base-changed) need no
# injected seam: they read real git ground truth. Draft/merged metadata genuinely comes
# from the forge, so it has a test seam (--pr-state-file) AND a paired real entrypoint
# gated OFF by default (PLUMBLINE_REMOTE_LIVE=1 -> gh). Per the repo's
# injectable-seam invariant this file carries a counter-based falsifier proving the
# real path is wired, plus a proof the gate is off by default.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_remote_state_watch"

WATCH_BIN="$REPO_DIR/config/claude/bin/plumbline-remote-watch"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

assert_file "remote-watch CLI exists" "$WATCH_BIN"

# Build a product repo with a real "remote" (a second local repo), a base branch and
# a feature branch pushed to it. Echoes the working repo path.
new_pair() {
  local name="$1" repo remote
  repo="$WORK/$name"
  remote="$WORK/$name.git"
  git init -q --bare "$remote"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email remote-test@example.com
  git -C "$repo" config user.name "Remote Test"
  git -C "$repo" checkout -q -b main
  printf 'product\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "base"
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -q origin main
  git -C "$repo" checkout -q -b feat/work
  printf 'work\n' >"$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "feature work"
  git -C "$repo" push -q origin feat/work
  git -C "$repo" fetch -q origin
  printf '%s' "$repo"
}

# write_pr_state <repo> <draft> <state> [base] [actor] [mechanism]
write_pr_state() {
  local repo="$1" draft="$2" state="$3" base="${4:-main}"
  local actor="${5:-}" mech="${6:-}"
  cat >"$repo/pr-state.json" <<EOF
{
  "number": 26,
  "isDraft": $draft,
  "state": "$state",
  "baseRefName": "$base",
  "headRefName": "feat/work",
  "mergedBy": "$actor",
  "mergeMechanism": "$mech"
}
EOF
}

# run_watch <repo> <subcommand> [args...]
run_watch() {
  local repo="$1" sub="$2"
  shift 2
  local outf="$WORK/watch.out"
  "$WATCH_BIN" "$sub" --repo "$repo" --feature work "$@" >"$outf" 2>&1
  WATCH_RC=$?
  WATCH_OUT="$(cat "$outf")"
}

# ---------------------------------------------------------------------------
# S. Snapshot: an active run records the expected remote state (AC-1).
# ---------------------------------------------------------------------------

repo="$(new_pair snap)"
write_pr_state "$repo" true OPEN main
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
assert_eq "snapshot succeeds on a clean active run" "0" "$WATCH_RC"
assert_file "snapshot writes the run state" \
  "$repo/docs/context/work.remote-state.json"
assert_contains "snapshot records the PR number" \
  "$(cat "$repo/docs/context/work.remote-state.json")" '"pr": 26'
assert_contains "snapshot records the base branch" \
  "$(cat "$repo/docs/context/work.remote-state.json")" '"base_ref": "main"'
assert_contains "snapshot records the draft state" \
  "$(cat "$repo/docs/context/work.remote-state.json")" '"is_draft": true'

# verify against an unchanged remote is a clean pass.
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "verify on an unchanged remote passes" "0" "$WATCH_RC"
assert_not_contains "unchanged remote is not reported as changed" \
  "$WATCH_OUT" "REMOTE_STATE_CHANGED"

# verify without a snapshot must fail closed, not pass by absence.
repo2="$(new_pair nosnap)"
write_pr_state "$repo2" true OPEN main
run_watch "$repo2" verify --pr-state-file "$repo2/pr-state.json"
assert_eq "verify with no snapshot fails closed (exit 2)" "2" "$WATCH_RC"
assert_contains "missing snapshot names the snapshot command" \
  "$WATCH_OUT" "snapshot"

# ---------------------------------------------------------------------------
# M. Unexpected merge (AC-3) -- the pilot's exact event.
# ---------------------------------------------------------------------------

repo="$(new_pair merged)"
write_pr_state "$repo" true OPEN main
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
assert_eq "merged fixture: snapshot ok" "0" "$WATCH_RC"

# Somebody merges the draft PR into the base branch on the remote.
merge_clone="$WORK/merged.merge"
git clone -q "$WORK/merged.git" "$merge_clone"
git -C "$merge_clone" config user.email merger@example.com
git -C "$merge_clone" config user.name "Merger"
git -C "$merge_clone" checkout -q main
git -C "$merge_clone" merge -q --no-ff origin/feat/work -m "Merge pull request #26"
git -C "$merge_clone" push -q origin main
git -C "$repo" fetch -q origin
write_pr_state "$repo" true MERGED main "octo-bot" "merge_commit"

run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "unexpected merge blocks (exit 3)" "3" "$WATCH_RC"
assert_contains "unexpected merge is classified" \
  "$WATCH_OUT" "REMOTE_STATE_CHANGED"
assert_contains "unexpected merge names the change kind" "$WATCH_OUT" "merged"
assert_contains "audit names the account" "$WATCH_OUT" "octo-bot"
assert_contains "audit names the mechanism" "$WATCH_OUT" "merge_commit"
# AC-5: no speculation about who/what acted.
assert_not_contains "audit does not speculate 'human'" "$WATCH_OUT" "human"
assert_not_contains "audit does not speculate 'automation'" "$WATCH_OUT" "automation"
assert_contains "audit says the actor is as reported by the remote" \
  "$WATCH_OUT" "as reported"

# AC-3: it blocks UNTIL re-evaluation -- a repeated verify keeps blocking.
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "merge keeps blocking on re-run" "3" "$WATCH_RC"
# An explicit re-evaluation (a fresh snapshot of the now-known state) clears it.
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
assert_eq "re-snapshot after review succeeds" "0" "$WATCH_RC"
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "after explicit re-evaluation verify passes" "0" "$WATCH_RC"

# The re-evaluation must clear ONLY the reviewed change. Merge detection is a
# TRANSITION check (a post-merge snapshot legitimately records containment), so the
# risk introduced by that design is a blind spot for the NEXT event. Prove there is
# none: a further base advance on the re-snapshotted state still blocks.
post_clone="$WORK/merged.post"
git clone -q "$WORK/merged.git" "$post_clone"
git -C "$post_clone" config user.email other@example.com
git -C "$post_clone" config user.name "Other"
git -C "$post_clone" checkout -q main
printf 'later change\n' >"$post_clone/later.txt"
git -C "$post_clone" add later.txt
git -C "$post_clone" commit -q -m "base moves again after the review"
git -C "$post_clone" push -q origin main
git -C "$repo" fetch -q origin
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "a NEW change after re-evaluation still blocks" "3" "$WATCH_RC"
assert_contains "the new change is classified" "$WATCH_OUT" "base-advanced"

# And a force-push after the review is still caught on the re-snapshotted state.
git -C "$repo" checkout -q feat/work
printf 'rewritten after review\n' >"$repo/feature.txt"
git -C "$repo" commit -q -aq --amend -m "feature work (rewritten after review)"
git -C "$repo" push -q --force origin feat/work
git -C "$repo" fetch -q origin
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
assert_eq "re-snapshot after the new base state succeeds" "0" "$WATCH_RC"
git -C "$repo" commit -q --amend -m "feature work (rewritten twice)"
git -C "$repo" push -q --force origin feat/work
git -C "$repo" fetch -q origin
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "force-push after re-evaluation still blocks" "3" "$WATCH_RC"
assert_contains "post-review force-push is classified" "$WATCH_OUT" "force-push"

# Merge detection must not depend on the forge metadata alone: git containment is
# ground truth. Same merged remote, but the PR state still claims OPEN.
repo="$(new_pair gitmerge)"
write_pr_state "$repo" true OPEN main
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
merge_clone="$WORK/gitmerge.merge"
git clone -q "$WORK/gitmerge.git" "$merge_clone"
git -C "$merge_clone" config user.email merger@example.com
git -C "$merge_clone" config user.name "Merger"
git -C "$merge_clone" checkout -q main
git -C "$merge_clone" merge -q --no-ff origin/feat/work -m "Merge pull request #26"
git -C "$merge_clone" push -q origin main
git -C "$repo" fetch -q origin
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "git-observed merge blocks even when the PR still says OPEN" "3" "$WATCH_RC"
assert_contains "git-observed merge names git as the source" \
  "$WATCH_OUT" "source=git"

# ---------------------------------------------------------------------------
# F. Force-push (AC-6).
# ---------------------------------------------------------------------------

repo="$(new_pair forcepush)"
write_pr_state "$repo" true OPEN main
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
# Rewrite the feature branch history and force-push it.
git -C "$repo" commit -q --amend -m "feature work (rewritten)"
git -C "$repo" push -q --force origin feat/work
git -C "$repo" fetch -q origin
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "force-push blocks (exit 3)" "3" "$WATCH_RC"
assert_contains "force-push is classified" "$WATCH_OUT" "REMOTE_STATE_CHANGED"
assert_contains "force-push names the change kind" "$WATCH_OUT" "force-push"
assert_contains "force-push names the recorded head" \
  "$WATCH_OUT" "recorded_head"

# ---------------------------------------------------------------------------
# B. Base branch changes (AC-2, AC-6).
# ---------------------------------------------------------------------------

# B1: the base branch itself advanced under the run (the stack-base hazard).
repo="$(new_pair baseadvanced)"
write_pr_state "$repo" true OPEN main
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
push_clone="$WORK/baseadvanced.push"
git clone -q "$WORK/baseadvanced.git" "$push_clone"
git -C "$push_clone" config user.email other@example.com
git -C "$push_clone" config user.name "Other"
git -C "$push_clone" checkout -q main
printf 'someone else\n' >"$push_clone/other.txt"
git -C "$push_clone" add other.txt
git -C "$push_clone" commit -q -m "unrelated base change"
git -C "$push_clone" push -q origin main
git -C "$repo" fetch -q origin
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "base branch advancing blocks (exit 3)" "3" "$WATCH_RC"
assert_contains "base advance names the change kind" "$WATCH_OUT" "base-advanced"

# B2: the PR was re-pointed at a DIFFERENT base branch.
repo="$(new_pair basechanged)"
write_pr_state "$repo" true OPEN main
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
write_pr_state "$repo" true OPEN release/1.x
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "base ref change blocks (exit 3)" "3" "$WATCH_RC"
assert_contains "base ref change names the change kind" \
  "$WATCH_OUT" "base-changed"
assert_contains "base ref change names the new base" "$WATCH_OUT" "release/1.x"

# ---------------------------------------------------------------------------
# D. Draft status changes (AC-2, AC-6).
# ---------------------------------------------------------------------------

repo="$(new_pair draftchanged)"
write_pr_state "$repo" true OPEN main
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
# Somebody marks the draft ready for review without the run's sign-off.
write_pr_state "$repo" false OPEN main
run_watch "$repo" verify --pr-state-file "$repo/pr-state.json"
assert_eq "draft -> ready blocks (exit 3)" "3" "$WATCH_RC"
assert_contains "draft change is classified" "$WATCH_OUT" "REMOTE_STATE_CHANGED"
assert_contains "draft change names the change kind" "$WATCH_OUT" "draft-changed"

# ---------------------------------------------------------------------------
# L. The live boundary: wired, gated OFF by default, falsifiable.
# ---------------------------------------------------------------------------

# Without the live gate and without an injected state file, the check must refuse
# rather than silently skipping the forge half.
repo="$(new_pair livegate)"
write_pr_state "$repo" true OPEN main
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
outf="$WORK/livegate.out"
"$WATCH_BIN" verify --repo "$repo" --feature work >"$outf" 2>&1
live_rc=$?
live_out="$(cat "$outf")"
assert_eq "no seam and no live gate: refuses (exit 2)" "2" "$live_rc"
assert_contains "refusal names the live gate" "$live_out" "PLUMBLINE_REMOTE_LIVE"
assert_not_contains "refusal is not a silent pass" "$live_out" "remote state verified"

# Falsifier for the real entrypoint: with the live gate ON, the module MUST invoke
# the forge CLI. A counting stub proves the call really happens -- an outcome
# assertion alone would still pass if the wiring were reverted to the seam.
stub_dir="$WORK/gh-stub"
mkdir -p "$stub_dir"
counter="$WORK/gh-calls"
: >"$counter"
cat >"$stub_dir/gh" <<EOF
#!/usr/bin/env bash
printf 'call %s\n' "\$*" >>"$counter"
cat <<'JSON'
{"number": 26, "isDraft": true, "state": "OPEN", "baseRefName": "main", "headRefName": "feat/work", "mergedBy": null}
JSON
EOF
chmod +x "$stub_dir/gh"
outf="$WORK/live.out"
env PATH="$stub_dir:$PATH" PLUMBLINE_REMOTE_LIVE=1 \
  "$WATCH_BIN" verify --repo "$repo" --feature work >"$outf" 2>&1
live_rc=$?
live_out="$(cat "$outf")"
calls="$(wc -l <"$counter" | tr -d ' ')"
assert_eq "live gate ON: the forge CLI was actually invoked (counter)" "1" "$calls"
assert_eq "live gate ON with unchanged state passes" "0" "$live_rc"
assert_contains "live run names the live source" "$live_out" "source=live"
assert_contains "live invocation asked for the PR fields" \
  "$(cat "$counter")" "isDraft"

# The live path must classify a forge failure, never fall back to "unchanged".
fail_stub="$WORK/gh-fail"
mkdir -p "$fail_stub"
cat >"$fail_stub/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh: could not reach api.github.com" >&2
exit 1
EOF
chmod +x "$fail_stub/gh"
outf="$WORK/livefail.out"
env PATH="$fail_stub:$PATH" PLUMBLINE_REMOTE_LIVE=1 \
  "$WATCH_BIN" verify --repo "$repo" --feature work >"$outf" 2>&1
live_rc=$?
live_out="$(cat "$outf")"
assert_eq "live forge failure is classified, not ignored (exit 2)" "2" "$live_rc"
assert_contains "live failure names the tool" "$live_out" "gh"
assert_not_contains "live failure does not claim verification" \
  "$live_out" "remote state verified"

# ---------------------------------------------------------------------------
# P. Optional published no-merge status (AC-4).
# ---------------------------------------------------------------------------

repo="$(new_pair publish)"
write_pr_state "$repo" true OPEN main
run_watch "$repo" snapshot --pr 26 --base main --pr-state-file "$repo/pr-state.json"
outf="$WORK/publish.out"
"$WATCH_BIN" publish-status --repo "$repo" --feature work --state pending \
  --dry-run >"$outf" 2>&1
pub_rc=$?
pub_out="$(cat "$outf")"
assert_eq "publish-status --dry-run succeeds offline" "0" "$pub_rc"
assert_contains "dry-run prints the request it would make" "$pub_out" "would"
assert_contains "dry-run names the check context" "$pub_out" "plumbline"
# The publishing path crosses a boundary, so it is gated OFF by default too.
outf="$WORK/publish2.out"
"$WATCH_BIN" publish-status --repo "$repo" --feature work --state pending \
  >"$outf" 2>&1
pub_rc=$?
pub_out="$(cat "$outf")"
assert_eq "publish-status without the live gate refuses (exit 2)" "2" "$pub_rc"
assert_contains "publish refusal names the live gate" \
  "$pub_out" "PLUMBLINE_REMOTE_LIVE"

# ---------------------------------------------------------------------------
# I. Classified input failures.
# ---------------------------------------------------------------------------

notrepo="$WORK/notarepo"
mkdir -p "$notrepo"
outf="$WORK/notrepo.out"
"$WATCH_BIN" snapshot --repo "$notrepo" --feature work --pr 26 --base main \
  >"$outf" 2>&1
rc=$?
assert_eq "not a git repo: exit 2" "2" "$rc"

repo="$(new_pair badstate)"
printf '{"number": 26, \n' >"$repo/pr-state.json"
outf="$WORK/badstate.out"
"$WATCH_BIN" snapshot --repo "$repo" --feature work --pr 26 --base main \
  --pr-state-file "$repo/pr-state.json" >"$outf" 2>&1
rc=$?
assert_eq "malformed injected PR state: exit 4" "4" "$rc"

repo="$(new_pair unknownbase)"
write_pr_state "$repo" true OPEN main
outf="$WORK/unknownbase.out"
"$WATCH_BIN" snapshot --repo "$repo" --feature work --pr 26 \
  --base does-not-exist --pr-state-file "$repo/pr-state.json" >"$outf" 2>&1
rc=$?
out="$(cat "$outf")"
assert_eq "unresolvable base ref at snapshot: exit 2" "2" "$rc"
assert_contains "unresolvable base names the ref" "$out" "does-not-exist"

finish "test_remote_state_watch"
