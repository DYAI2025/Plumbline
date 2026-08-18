#!/usr/bin/env python3
"""Non-local dark-zone mutator for pipe-nonlocal-v1.

Unlike pipe-core-v1/mutate.py (which breaks LOCAL logic that any unit test
catches), this breaks NON-LOCAL reality:

  N1  composition-root WIRING gap  -- remove the handler registration in
      build_app(). A unit-only suite stays GREEN (escaped); an integration
      suite that dispatches through build_app() goes RED (caught).

  N2  real-boundary FAKE gap       -- neuter FileStore.append() to a no-op.
      A fake-only suite stays GREEN (escaped); a real-boundary smoke test
      that round-trips through a temp file goes RED (caught).

Usage:
  mutate_nonlocal.py <N1|N2> <task_dir>            apply, print JSON
  mutate_nonlocal.py <N1|N2> <task_dir> --restore  restore from backup

The point of THIS oracle is that the defect is invisible to a test suite that
only exercises units/fakes, and visible only to one wired through the real
composition root / real boundary. So escaped-defect-rate here measures whether
the arm's TESTS reach reality -- exactly the dark zone the DNA targets.
"""
import json
import os
import re
import shutil
import sys


def _backup(path: str) -> None:
    bak = path + ".mutbak"
    if not os.path.exists(bak):
        shutil.copy2(path, bak)


def _restore(path: str) -> bool:
    bak = path + ".mutbak"
    if os.path.exists(bak):
        shutil.move(bak, path)
        return True
    return False


def _find(task_dir: str, rel: str) -> str:
    p = os.path.join(task_dir, rel)
    if not os.path.exists(p):
        raise FileNotFoundError(f"expected {rel} under {task_dir}; not found")
    return p


def apply_mutation(task: str, task_dir: str):
    if task == "N1":
        f = _find(task_dir, "src/app.py")
        _backup(f)
        src = open(f).read()
        # Remove any bus.register(...) call inside build_app (the wiring line).
        new, n = re.subn(r"^[ \t]*\w+\.register\([^\n]*\)[^\n]*\n", "", src, flags=re.M)
        open(f, "w").write(new)
        return f, n >= 1, f"removed {n} register() wiring line(s) from composition root"
    if task == "N2":
        f = _find(task_dir, "src/store.py")
        _backup(f)
        src = open(f).read()
        # Neuter FileStore.append body -> no-op (real persistence broken).
        new, n = re.subn(
            r"(def append\(self, record: str\) -> None:\n)(?:[ \t]+.*\n|[ \t]*\n)+?(?=\n?[ \t]*def |\Z)",
            r"\1        return  # MUTATED: real boundary write neutered\n",
            src,
            count=1,
        )
        open(f, "w").write(new)
        return f, n == 1, "neutered FileStore.append -> no-op (real persistence broken)"
    raise SystemExit(f"unknown task {task!r} (expected N1 or N2)")


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    task, task_dir = sys.argv[1], sys.argv[2]
    restore = "--restore" in sys.argv[3:]
    if restore:
        targets = {
            "N1": ["src/app.py"],
            "N2": ["src/store.py"],
        }[task]
        ok = any(_restore(os.path.join(task_dir, t)) for t in targets)
        print(json.dumps({"task": task, "restored": ok}))
        return
    path, applied, desc = apply_mutation(task, task_dir)
    if not applied:
        sys.stderr.write(f"WARNING: mutation did not apply to {path} -- {desc}\n")
    print(json.dumps({"task": task, "file": path, "applied": applied, "mutation": desc}))


if __name__ == "__main__":
    main()
