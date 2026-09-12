#!/usr/bin/env python3
"""Fail when text appears to contain secrets or tokens."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("openai-key", re.compile(r"\bsk-[A-Za-z0-9]{20,}\b")),
    ("github-token", re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b")),
    ("github-fine-grained-token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("azure-storage-connection", re.compile(r"AccountKey=[A-Za-z0-9+/=]{20,}")),
    ("generic-bearer-token", re.compile(r"\bBearer\s+[A-Za-z0-9._-]{20,}\b", re.IGNORECASE)),
]


def detect_secret(text: str) -> tuple[str, str] | None:
    for name, pattern in PATTERNS:
        match = pattern.search(text)
        if match:
            sample = match.group(0)
            return name, sample[:8] + "...REDACTED..."
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", dest="file_path")
    args = parser.parse_args()

    if args.file_path:
        text = pathlib.Path(args.file_path).read_text(encoding="utf-8")
    else:
        text = sys.stdin.read()

    finding = detect_secret(text)
    if finding:
        name, sample = finding
        print(f"secret-like content detected ({name}, sample={sample})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

