#!/usr/bin/env python3
"""Plumbline runtime-state hygiene guard (PLUM-11).

Agent tooling writes volatile state into the working directory: neural/policy
snapshots, swarm memory, session observations. In a product repository that state
is not source, and it has two failure modes:

  tracked    the state is committed. Product diffs carry session noise, secret and
             history scans inherit prompt/tool output forever, and curated evidence
             becomes indistinguishable from throwaway state. (The pilot: 11 files,
             ~7.1 MB.)
  unignored  the state is untracked but not ignored, so it lands in the enforce
             hook's change surface (`git ls-files --others --exclude-standard`) and
             blocks EVERY scope check without a single line of feature work. The
             2026-07-08 C4 exemption only covers paths that are gitignored AND
             untracked, so "not ignored" is not a harmless state.

This module reports both, plus a third: volatile state sitting inside a curated
export directory, which confuses the one distinction the project depends on.

Every fix is additive. `--fix-ignore` appends a marked block to `.gitignore` and
NEVER deletes a file, rewrites a foreign rule, or silently rewrites history: an
already-tracked file is reported with the `git rm -r --cached` command for the
operator to run, and the check keeps failing until they do.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

EXIT_PASS = 0
EXIT_MISSING = 2
EXIT_VIOLATION = 3
EXIT_MALFORMED = 4

# Known agent-runtime state locations. Deliberately a short, justified list rather
# than a guess at every tool in existence: extend per repo with `--pattern`.
RUNTIME_PATTERNS = (
    ".claude-flow/",      # claude-flow neural/policy/session state
    ".claude/homunculus/",  # homunculus observations/instincts
    ".swarm/",            # swarm memory database
    ".hive-mind/",        # hive-mind session state
    ".plumbline/",        # Plumbline update snapshots
    ".devin/",            # third-party agent state
)

# Directories whose contents are curated, reviewed, versioned artifacts. Volatile
# state inside them is a category error even when it happens to be ignored.
CURATED_PREFIXES = ("docs/", "metrics/")

BLOCK_HEADER = "# plumbline: agent runtime state (volatile, never source) — PLUM-11"
BLOCK_FOOTER = "# plumbline: end agent runtime state"


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def _is_git_repo(repo: Path) -> bool:
    result = _git(repo, "rev-parse", "--git-dir")
    return result.returncode == 0


def _tracked_under(repo: Path, pattern: str) -> list[str]:
    prefix = pattern.rstrip("/")
    result = _git(repo, "ls-files", "--", prefix)
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def _present_on_disk(repo: Path, pattern: str) -> bool:
    return (repo / pattern.rstrip("/")).exists()


def _is_ignored(repo: Path, pattern: str) -> bool:
    # Probe a concrete child path: `check-ignore` answers for paths, and a bare
    # directory that does not exist yet would answer "no" for the wrong reason.
    probe = f"{pattern.rstrip('/')}/.plumbline-hygiene-probe"
    result = _git(repo, "check-ignore", "-q", "--no-index", "--", probe)
    if result.returncode == 0:
        return True
    # A file pattern (no trailing slash in the repo's rules) may match the bare path.
    result = _git(repo, "check-ignore", "-q", "--no-index", "--", pattern.rstrip("/"))
    return result.returncode == 0


def _curated_hits(repo: Path, pattern: str) -> list[str]:
    """Volatile state that lives under a curated export prefix."""
    name = pattern.rstrip("/").lstrip(".")
    hits: list[str] = []
    for prefix in CURATED_PREFIXES:
        base = repo / prefix.rstrip("/")
        if not base.is_dir():
            continue
        for candidate in base.rglob(f"*{name}*"):
            if candidate.is_dir():
                hits.append(str(candidate.relative_to(repo)))
    return sorted(set(hits))


def _existing_block_patterns(gitignore: Path) -> set[str]:
    if not gitignore.exists():
        return set()
    try:
        lines = gitignore.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return set()
    return {line.strip() for line in lines if line.strip() and not line.startswith("#")}


def _append_ignore_rules(gitignore: Path, patterns: list[str]) -> list[str]:
    """Append the missing patterns inside a marked block. Purely additive."""
    already = _existing_block_patterns(gitignore)
    missing = [p for p in patterns if p not in already]
    if not missing:
        return []
    existing_text = ""
    if gitignore.exists():
        existing_text = gitignore.read_text(encoding="utf-8")
        if existing_text and not existing_text.endswith("\n"):
            existing_text += "\n"
    body = "\n".join(missing)
    gitignore.write_text(
        f"{existing_text}\n{BLOCK_HEADER}\n{body}\n{BLOCK_FOOTER}\n",
        encoding="utf-8",
    )
    return missing


def check_hygiene(
    repo: Path,
    extra_patterns: list[str] | None = None,
    fix_ignore: bool = False,
) -> int:
    if not repo.is_dir():
        print(f"ERROR: repository path does not exist: {repo}", file=sys.stderr)
        return EXIT_MISSING
    if not _is_git_repo(repo):
        print(
            f"ERROR: not a git repository: {repo}; runtime-state hygiene is defined "
            "against tracked/ignored status, which needs git",
            file=sys.stderr,
        )
        return EXIT_MISSING

    patterns = list(RUNTIME_PATTERNS)
    for extra in extra_patterns or []:
        candidate = extra.strip()
        if not candidate or candidate.startswith("/") or ".." in Path(candidate).parts:
            print(
                f"ERROR: --pattern {extra!r} must be a non-empty repo-relative path",
                file=sys.stderr,
            )
            return EXIT_MALFORMED
        if candidate not in patterns:
            patterns.append(candidate)

    tracked: list[tuple[str, list[str]]] = []
    unignored: list[str] = []
    curated: list[str] = []
    clean: list[str] = []

    for pattern in patterns:
        hits = _tracked_under(repo, pattern)
        if hits:
            tracked.append((pattern, hits))
        present = _present_on_disk(repo, pattern)
        ignored = _is_ignored(repo, pattern)
        if not ignored and (present or hits):
            unignored.append(pattern)
        elif ignored and present and not hits:
            clean.append(pattern)
        curated.extend(_curated_hits(repo, pattern))

    curated = sorted(set(curated))

    fixed: list[str] = []
    if fix_ignore:
        # Prophylactic on purpose: the rules must be in place BEFORE the first
        # session writes anything, so fixing covers every known pattern rather than
        # only the directories that happen to exist right now. An ignore rule for an
        # unused tool is inert; a missing one blocks a scope gate mid-run.
        fixed = _append_ignore_rules(repo / ".gitignore", patterns)
        if fixed:
            print(
                "fixed: appended to .gitignore (additive, nothing deleted): "
                + ", ".join(fixed)
            )
        # Re-evaluate: an ignored pattern is no longer an `unignored` finding.
        unignored = [p for p in unignored if not _is_ignored(repo, p)]

    exit_code = EXIT_PASS

    for pattern, hits in tracked:
        shown = ", ".join(hits[:5]) + (" …" if len(hits) > 5 else "")
        print(
            f"VIOLATION class=tracked pattern={pattern} files={len(hits)} ({shown})\n"
            f"  fix (non-destructive, keeps the file on disk): "
            f"git -C {repo} rm -r --cached {pattern.rstrip('/')}\n"
            "  then commit the removal. This command is NOT run for you: untracking "
            "is a history decision.",
            file=sys.stderr,
        )
        exit_code = EXIT_VIOLATION

    for pattern in unignored:
        print(
            f"VIOLATION class=unignored pattern={pattern}\n"
            "  volatile state that is neither tracked nor ignored still enters the "
            "enforce hook's change surface and blocks every scope check.\n"
            f"  fix: add '{pattern}' to .gitignore, or re-run with --fix-ignore",
            file=sys.stderr,
        )
        exit_code = EXIT_VIOLATION

    for path in curated:
        print(
            f"VIOLATION class=curated-location path={path}\n"
            "  volatile runtime state inside a curated export directory "
            f"({', '.join(CURATED_PREFIXES)}). Curated directories hold reviewed, "
            "exported artifacts only; move the state out, and export curated "
            "insight explicitly instead of letting session state accumulate here.",
            file=sys.stderr,
        )
        exit_code = EXIT_VIOLATION

    if exit_code == EXIT_PASS:
        if clean:
            print(
                "runtime state present and reliably ignored: " + ", ".join(clean)
            )
        print(
            f"PRIL runtime hygiene passed for {repo} "
            f"({len(patterns)} pattern(s) checked, {len(clean)} present-and-ignored)"
        )
    return exit_code


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Detect agent runtime state that contaminates a product "
        "repository, and offer a non-destructive fix.",
    )
    parser.add_argument("--repo", required=True, help="Repository root to inspect")
    parser.add_argument(
        "--pattern",
        action="append",
        default=[],
        help="Additional repo-relative runtime-state path (repeatable)",
    )
    parser.add_argument(
        "--fix-ignore",
        action="store_true",
        help="Append the missing ignore rules to .gitignore (additive; never "
        "deletes a file and never untracks anything)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return check_hygiene(
        Path(args.repo).resolve() if Path(args.repo).exists() else Path(args.repo),
        extra_patterns=args.pattern,
        fix_ignore=args.fix_ignore,
    )


if __name__ == "__main__":
    raise SystemExit(main())
