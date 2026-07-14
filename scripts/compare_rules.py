#!/usr/bin/env python3
"""Compare source rules with Mihomo's normalized MRS text export."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys


def load_rules(path: pathlib.Path) -> list[str]:
    data = path.read_bytes()
    if b"\x00" in data:
        raise ValueError(f"{path} contains NUL bytes")
    rules = [line.strip().lower() for line in data.decode("utf-8").splitlines()]
    if not rules or any(not rule for rule in rules):
        raise ValueError(f"{path} contains an empty rule or is empty")
    if len(set(rules)) != len(rules):
        raise ValueError(f"{path} contains duplicate rules")
    return rules


def normalize_source_rules(rules: list[str]) -> tuple[set[str], int]:
    """Mirror the lossless normalization visible in DomainSet.DumpMrs.

    Inserting ``+.example.com`` creates both the suffix-wildcard node and its
    exact ``example.com`` node. If the YAML also explicitly contains the exact
    rule, the MRS text exporter emits only ``+.example.com``. Dropping that
    redundant exact spelling preserves the matcher while avoiding a false
    semantic-comparison failure for providers such as ``direct``.
    """

    source_set = set(rules)
    redundant_exact = {
        rule
        for rule in source_set
        if not rule.startswith(("+.", ".", "*.")) and f"+.{rule}" in source_set
    }
    return source_set - redundant_exact, len(redundant_exact)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=pathlib.Path)
    parser.add_argument("--roundtrip", required=True, type=pathlib.Path)
    parser.add_argument("--json-out", required=True, type=pathlib.Path)
    args = parser.parse_args()

    try:
        source = load_rules(args.source)
        roundtrip = load_rules(args.roundtrip)
    except (OSError, UnicodeDecodeError, ValueError) as error:
        print(f"semantic validation failed: {error}", file=sys.stderr)
        return 1

    source_set, normalized_exact_rules = normalize_source_rules(source)
    roundtrip_set = set(roundtrip)
    source_only = sorted(source_set - roundtrip_set)
    roundtrip_only = sorted(roundtrip_set - source_set)
    result = {
        "source_rule_count": len(source),
        "source_effective_rule_count": len(source_set),
        "normalized_redundant_exact_rules": normalized_exact_rules,
        "roundtrip_rule_count": len(roundtrip),
        "source_only": len(source_only),
        "roundtrip_only": len(roundtrip_only),
    }
    args.json_out.write_text(
        json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    if source_only or roundtrip_only or len(source_set) != len(roundtrip):
        print(json.dumps(result, sort_keys=True), file=sys.stderr)
        if source_only:
            print(f"source-only sample: {source_only[:5]}", file=sys.stderr)
        if roundtrip_only:
            print(f"roundtrip-only sample: {roundtrip_only[:5]}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
