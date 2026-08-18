#!/usr/bin/env python3
"""Plumbline Runtime Integrity Layer redaction guard."""
from __future__ import annotations

import argparse
import json
import re
import sys

EXIT_PASS = 0
EXIT_SECRET = 3
EXIT_MALFORMED = 4
EXIT_TOO_LARGE = 5
MAX_BYTES = 1024 * 1024

SECRET_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("OpenAI/API key", re.compile(r"\bsk-[A-Za-z0-9][A-Za-z0-9_-]{20,}\b")),
    ("AWS access key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{30,}\b")),
    ("private key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
    ("credential assignment", re.compile(r"(?im)^\s*(?:[A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|ACCESS_KEY)[A-Z0-9_]*)\s*=\s*[^\s#]{8,}")),
)


def _read_stdin() -> tuple[int, str]:
    data = sys.stdin.buffer.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        print(f"ERROR: input too large for safe persistence redaction ({len(data)} bytes)", file=sys.stderr)
        return EXIT_TOO_LARGE, ""
    try:
        return EXIT_PASS, data.decode("utf-8")
    except UnicodeDecodeError:
        print("ERROR: input is not UTF-8 text", file=sys.stderr)
        return EXIT_MALFORMED, ""


def find_secret(text: str) -> tuple[str, str] | None:
    for name, pattern in SECRET_PATTERNS:
        match = pattern.search(text)
        if match:
            return name, match.group(0)
    return None


def redact_text(text: str) -> str:
    redacted = text
    for name, pattern in SECRET_PATTERNS:
        redacted = pattern.sub(f"[REDACTED:{name}]", redacted)
    return redacted


def check_jsonl(text: str) -> int:
    if not text.strip():
        print("ERROR: empty JSONL input", file=sys.stderr)
        return EXIT_MALFORMED
    for idx, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"ERROR: invalid JSONL at line {idx}: {exc.msg}", file=sys.stderr)
            return EXIT_MALFORMED
        secret = find_secret(line)
        if secret:
            print(f"ERROR: unsafe persistent artifact contains secret-like data at line {idx}: {secret[0]}", file=sys.stderr)
            return EXIT_SECRET
    print("PRIL redaction check passed")
    return EXIT_PASS


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Check or redact text before persistent Plumbline storage.")
    parser.add_argument("--mode", required=True, choices=("check", "auto"), help="check JSONL or emit redacted text")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    status, text = _read_stdin()
    if status != EXIT_PASS:
        return status
    if args.mode == "check":
        return check_jsonl(text)
    sys.stdout.write(redact_text(text))
    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
