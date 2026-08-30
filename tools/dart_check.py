#!/usr/bin/env python3
"""Syntax-check Dart files using tree-sitter (no Dart SDK available)."""
import sys
from pathlib import Path

import tree_sitter_dart
from tree_sitter import Language, Parser

DART = Language(tree_sitter_dart.language())
parser = Parser(DART)

def check(path: Path) -> list[str]:
    src = path.read_bytes()
    tree = parser.parse(src)
    errors = []

    def walk(node):
        if node.type == "ERROR" or node.is_missing:
            line = node.start_point[0] + 1
            col = node.start_point[1] + 1
            snippet = src[node.start_byte:node.start_byte + 60].decode("utf-8", "replace").replace("\n", "\\n")
            errors.append(f"{path}:{line}:{col}: {node.type} -> {snippet!r}")
        for child in node.children:
            walk(child)

    walk(tree.root_node)
    return errors

def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    files = sorted(root.rglob("*.dart")) if root.is_dir() else [root]
    all_errors = []
    for f in files:
        if "ephemeral" in str(f) or ".git" in str(f):
            continue
        all_errors.extend(check(f))
    if all_errors:
        print(f"{len(all_errors)} syntax problem(s):")
        for e in all_errors[:80]:
            print(" ", e)
        sys.exit(1)
    print(f"OK: {len(list(files))} dart files parsed cleanly")

if __name__ == "__main__":
    main()
