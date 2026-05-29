#!/usr/bin/env python3
"""Provided-fake dark-zone mutator for pipe-providedfake-v1.

Neuters the REAL boundary FileStore.append() to a no-op. The scaffold hands the
arm a ready-made InMemoryStore fake plus a starter test that uses it, so mocking
is the path of least resistance. A suite that only extends the fake pattern stays
GREEN (escaped); only a suite that does the extra work of a real-file smoke test
through build_service() goes RED (caught).

Usage:
  mutate_providedfake.py P1 <task_dir>            apply, print JSON
  mutate_providedfake.py P1 <task_dir> --restore  restore from backup
"""
import json, os, re, shutil, sys


def _backup(p):
    b = p + ".mutbak"
    if not os.path.exists(b):
        shutil.copy2(p, b)


def _restore(p):
    b = p + ".mutbak"
    if os.path.exists(b):
        shutil.move(b, p)
        return True
    return False


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    task, d = sys.argv[1], sys.argv[2]
    if task != "P1":
        raise SystemExit(f"unknown task {task!r} (expected P1)")
    f = os.path.join(d, "src/store.py")
    if "--restore" in sys.argv[3:]:
        print(json.dumps({"task": task, "restored": _restore(f)}))
        return
    _backup(f)
    src = open(f).read()
    new, n = re.subn(
        r"(def append\(self, record: str\) -> None:\n)(?:[ \t]+.*\n|[ \t]*\n)+?(?=\n?[ \t]*def |\Z)",
        r"\1        return  # MUTATED: real boundary write neutered\n",
        src, count=1,
    )
    open(f, "w").write(new)
    if n != 1:
        sys.stderr.write(f"WARNING: mutation did not apply to {f}\n")
    print(json.dumps({"task": task, "file": f, "applied": n == 1,
                      "mutation": "neutered FileStore.append -> no-op"}))


if __name__ == "__main__":
    main()
