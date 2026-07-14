#!/usr/bin/env python3
"""Strict validator for Loyalsoldier's canonical domain-provider YAML shape.

This intentionally accepts a small, auditable subset of YAML: one top-level
`payload:` sequence containing plain, single-quoted, or JSON-compatible
double-quoted scalar values. Mihomo remains the authoritative YAML parser; this
validator is an independent supply-chain guard before conversion.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
from dataclasses import dataclass


class ValidationError(ValueError):
    pass


@dataclass(frozen=True)
class ValidationResult:
    byte_count: int
    sha256: str
    rule_count: int
    unique_rule_count: int

    def as_dict(self) -> dict[str, int | str]:
        return {
            "bytes": self.byte_count,
            "sha256": self.sha256,
            "rule_count": self.rule_count,
            "unique_rule_count": self.unique_rule_count,
        }


def _strip_comment(rest: str) -> str:
    match = re.search(r"\s+#", rest)
    return rest[: match.start()].rstrip() if match else rest.rstrip()


def parse_scalar(token: str, line_number: int) -> str:
    token = token.strip()
    if not token:
        raise ValidationError(f"line {line_number}: empty payload scalar")

    if token.startswith("'"):
        value: list[str] = []
        index = 1
        while index < len(token):
            char = token[index]
            if char != "'":
                value.append(char)
                index += 1
                continue
            if index + 1 < len(token) and token[index + 1] == "'":
                value.append("'")
                index += 2
                continue
            trailing = token[index + 1 :].strip()
            if trailing and not trailing.startswith("#"):
                raise ValidationError(
                    f"line {line_number}: content after single-quoted scalar"
                )
            return "".join(value)
        raise ValidationError(f"line {line_number}: unclosed single-quoted scalar")

    if token.startswith('"'):
        try:
            value, end = json.JSONDecoder().raw_decode(token)
        except json.JSONDecodeError as error:
            raise ValidationError(
                f"line {line_number}: invalid double-quoted scalar: {error.msg}"
            ) from error
        if not isinstance(value, str):
            raise ValidationError(f"line {line_number}: scalar is not a string")
        trailing = token[end:].strip()
        if trailing and not trailing.startswith("#"):
            raise ValidationError(
                f"line {line_number}: content after double-quoted scalar"
            )
        return value

    value = _strip_comment(token)
    if not value or any(character.isspace() for character in value):
        raise ValidationError(f"line {line_number}: invalid plain scalar")
    if value[0] in "[]{}&*!|>@`":
        raise ValidationError(f"line {line_number}: unsupported YAML scalar syntax")
    return value


def extract_rules(data: bytes) -> list[str]:
    if b"\x00" in data:
        raise ValidationError("input contains NUL bytes")
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise ValidationError(f"input is not valid UTF-8: {error}") from error

    rules: list[str] = []
    payload_found = False
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        if "\t" in raw_line[: len(raw_line) - len(raw_line.lstrip())]:
            raise ValidationError(f"line {line_number}: tab indentation is forbidden")
        stripped = raw_line.strip()
        if not payload_found:
            if not stripped or stripped.startswith("#"):
                continue
            if raw_line == "payload:":
                payload_found = True
                continue
            raise ValidationError(
                f"line {line_number}: expected a top-level payload: key"
            )

        if not stripped or stripped.startswith("#"):
            continue
        match = re.fullmatch(r"  -\s+(.+)", raw_line)
        if match is None:
            raise ValidationError(
                f"line {line_number}: payload entries must use exactly two-space indentation"
            )
        value = parse_scalar(match.group(1), line_number)
        if not value:
            raise ValidationError(f"line {line_number}: empty rule")
        if any(ord(character) < 0x20 for character in value):
            raise ValidationError(f"line {line_number}: rule contains a control character")
        if any(character.isspace() for character in value):
            raise ValidationError(f"line {line_number}: rule contains whitespace")
        if "/" in value:
            raise ValidationError(
                f"line {line_number}: domain rule contains '/', which Mihomo rejects"
            )
        rules.append(value.lower())

    if not payload_found:
        raise ValidationError("missing payload: key")
    return rules


def validate(
    path: pathlib.Path, min_bytes: int, max_bytes: int, min_rules: int
) -> tuple[ValidationResult, list[str]]:
    data = path.read_bytes()
    if not min_bytes <= len(data) <= max_bytes:
        raise ValidationError(
            f"input size {len(data)} is outside [{min_bytes}, {max_bytes}]"
        )
    rules = extract_rules(data)
    if len(rules) < min_rules:
        raise ValidationError(
            f"rule count {len(rules)} is below the safety threshold {min_rules}"
        )
    unique_rules = set(rules)
    if len(unique_rules) != len(rules):
        raise ValidationError(
            f"input contains {len(rules) - len(unique_rules)} duplicate rule(s)"
        )
    return (
        ValidationResult(
            byte_count=len(data),
            sha256=hashlib.sha256(data).hexdigest(),
            rule_count=len(rules),
            unique_rule_count=len(unique_rules),
        ),
        rules,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=pathlib.Path)
    parser.add_argument("--min-bytes", required=True, type=int)
    parser.add_argument("--max-bytes", required=True, type=int)
    parser.add_argument("--min-rules", required=True, type=int)
    parser.add_argument("--json-out", required=True, type=pathlib.Path)
    parser.add_argument("--canonical-out", required=True, type=pathlib.Path)
    args = parser.parse_args()

    try:
        result, rules = validate(
            args.input, args.min_bytes, args.max_bytes, args.min_rules
        )
    except (OSError, ValidationError) as error:
        print(f"source validation failed: {error}", file=sys.stderr)
        return 1

    args.json_out.write_text(
        json.dumps(result.as_dict(), sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    args.canonical_out.write_text("\n".join(rules) + "\n", encoding="utf-8")
    print(json.dumps(result.as_dict(), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
