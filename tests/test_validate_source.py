from __future__ import annotations

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from validate_source import ValidationError, extract_rules, validate  # noqa: E402


class ValidateSourceTests(unittest.TestCase):
    def test_supported_scalars(self) -> None:
        data = (
            b"# generated\n"
            b"payload:\n"
            b"  - plain.example\n"
            b"  - '+.single.example'\n"
            b"  - 'it''s.example'\n"
            b'  - "double.example" # comment\n'
        )
        self.assertEqual(
            extract_rules(data),
            [
                "plain.example",
                "+.single.example",
                "it's.example",
                "double.example",
            ],
        )

    def test_rejects_nul(self) -> None:
        with self.assertRaisesRegex(ValidationError, "NUL"):
            extract_rules(b"payload:\n  - 'ok.example'\x00\n")

    def test_rejects_missing_payload(self) -> None:
        with self.assertRaisesRegex(ValidationError, "payload"):
            extract_rules(b"rules:\n  - 'example.com'\n")

    def test_rejects_invalid_indentation(self) -> None:
        with self.assertRaisesRegex(ValidationError, "two-space"):
            extract_rules(b"payload:\n   - 'example.com'\n")

    def test_rejects_unclosed_single_quote(self) -> None:
        with self.assertRaisesRegex(ValidationError, "unclosed"):
            extract_rules(b"payload:\n  - 'example.com\n")

    def test_rejects_unclosed_double_quote(self) -> None:
        with self.assertRaisesRegex(ValidationError, "double-quoted"):
            extract_rules(b'payload:\n  - "example.com\n')

    def test_rejects_domain_rule_with_slash(self) -> None:
        with self.assertRaisesRegex(ValidationError, "contains '/'"):
            extract_rules(b"payload:\n  - 'example.com/path'\n")

    def test_size_rule_threshold_and_duplicate_guards(self) -> None:
        path = ROOT / "tests" / ".validate-source-test-input.tmp"
        try:
            path.write_bytes(b"payload:\n  - 'a.example'\n  - 'a.example'\n")
            with self.assertRaisesRegex(ValidationError, "duplicate"):
                validate(path, min_bytes=1, max_bytes=1000, min_rules=2)

            path.write_bytes(b"payload:\n  - 'a.example'\n")
            with self.assertRaisesRegex(ValidationError, "below"):
                validate(path, min_bytes=1, max_bytes=1000, min_rules=2)
            with self.assertRaisesRegex(ValidationError, "outside"):
                validate(path, min_bytes=1000, max_bytes=2000, min_rules=1)
        finally:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
