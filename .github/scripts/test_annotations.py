#!/usr/bin/env python3
"""Surface `flutter test` failures as GitHub Actions annotations.

Job logs live in blob storage that is not always reachable (see
analyze_annotations.py), so a failing test suite would otherwise show only
"161 tests passed, 4 failed." with no names. This prints every failing test
line — and the few assertion lines under it — as `::error` workflow commands,
so the PR shows *which* test failed and why.

Usage: python3 test_annotations.py /path/to/flutter-test.log
"""
import pathlib
import sys

MAX_BLOCKS = 10
MAX_LINES = 12


def escape(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def main(path: str) -> int:
    # `flutter test` (compact reporter) progress lines are separated by \r, not
    # \n — dono par split karna zaroori hai, warna failing test line ek hi
    # bade string me chhup jati hai.
    text = pathlib.Path(path).read_text(errors="replace").replace("\r", "\n")
    blocks, current = [], None
    for raw in text.splitlines():
        line = raw.rstrip()
        if "[E]" in line:
            if current:
                blocks.append(current)
            current = [line]
            continue
        if current is None:
            continue
        # Test output lines are indented under the failing test; a new
        # "00:12 +N" progress line means the failure block ended.
        if line.strip() == "" or line[:2].isdigit() and " +" in line[:12]:
            blocks.append(current)
            current = None
            continue
        current.append(line)
    if current:
        blocks.append(current)

    if not blocks:
        # Format badal jaye to bhi PR par kuch to dikhe: log ka aakhiri hissa.
        tail = text.strip().splitlines()[-60:]
        print("::error::flutter test failed (no [E] block) — log tail:%0A"
              + escape("\n".join(tail))[-6000:])
        return 0

    print(f"::error::{len(blocks)} failing test(s)")
    for block in blocks[:MAX_BLOCKS]:
        message = escape("\n".join(block[:MAX_LINES]))
        print(f"::error::{message}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
