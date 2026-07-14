from __future__ import annotations

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from compare_rules import normalize_source_rules  # noqa: E402


class CompareRulesTests(unittest.TestCase):
    def test_normalizes_exact_rule_redundant_with_suffix_rule(self) -> None:
        normalized, removed = normalize_source_rules(
            ["example.com", "+.example.com", "exact.example"]
        )
        self.assertEqual(normalized, {"+.example.com", "exact.example"})
        self.assertEqual(removed, 1)

    def test_does_not_drop_unrelated_or_wildcard_rules(self) -> None:
        rules = ["example.com", ".suffix.example", "*.one.example"]
        normalized, removed = normalize_source_rules(rules)
        self.assertEqual(normalized, set(rules))
        self.assertEqual(removed, 0)


if __name__ == "__main__":
    unittest.main()
