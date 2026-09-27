#!/usr/bin/env python3
"""Builds lambda.zip from lambda/alarm_to_slack.py, byte-for-byte reproducibly.

The zip is committed so Terraform needs no extra provider to package it.
  python3 build.py          rebuild lambda.zip
  python3 build.py --check  fail if lambda.zip is out of date (used in CI)
"""

import io
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "lambda" / "alarm_to_slack.py"
TARGET = HERE / "lambda.zip"


def build() -> bytes:
    data = SOURCE.read_bytes().replace(b"\r\n", b"\n")  # same result on Windows checkouts
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        info = zipfile.ZipInfo("alarm_to_slack.py", date_time=(1980, 1, 1, 0, 0, 0))
        info.external_attr = 0o644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
    return buffer.getvalue()


def main() -> int:
    content = build()
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_bytes() != content:
            print(f"{TARGET} is out of date: run python3 {Path(__file__).name} and commit it.")
            return 1
        print(f"{TARGET.name} is up to date.")
        return 0
    TARGET.write_bytes(content)
    print(f"Wrote {TARGET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
