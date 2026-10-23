#!/usr/bin/env python3
"""Convert `flutter analyze` output into GitHub Actions check-run annotations.

Actions job logs live in blob storage that is not always reachable (and
`gh run view --log-failed` can return EOF for this repository), but check-run
annotations are readable through the REST API. This script prints one
`::error file=…,line=…` workflow command per analyzer issue, so a failing
`flutter analyze` shows its exact file:line inside the PR even when the log
cannot be downloaded.

Usage: python3 analyze_annotations.py /path/to/analyze.log
"""
import pathlib
import re
import sys

#  error • The name 'X' isn't a type. • lib/main.dart:5:7 • undefined_class
LINE = re.compile(
    r"^\s*(?P<level>error|warning|info)\s+•\s+(?P<message>.*?)\s+•\s+"
    r"(?P<path>\S+?):(?P<line>\d+):(?P<col>\d+)\s+•\s*(?P<code>.*)$"
)


def escape(value: str) -> str:
    return (
        value.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )


def main(path: str) -> int:
    text = pathlib.Path(path).read_text(errors="replace")
    count = 0
    for raw in text.splitlines():
        match = LINE.match(raw)
        if not match:
            continue
        parts = match.groupdict()
        print(
            "::{level} file={path},line={line},col={col},title={code}::{message}".format(
                level=parts["level"],
                path=parts["path"],
                line=parts["line"],
                col=parts["col"],
                code=escape(parts["code"] or "analyzer"),
                message=escape(parts["message"]),
            )
        )
        count += 1
    print(f"({count} analyzer issue(s) annotated)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
