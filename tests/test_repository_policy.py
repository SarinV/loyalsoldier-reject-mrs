from __future__ import annotations

import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class RepositoryPolicyTests(unittest.TestCase):
    def test_workflow_has_minimal_permissions_and_expected_triggers(self) -> None:
        workflow = (ROOT / ".github/workflows/build-release.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn('    - cron: "30 0 * * *"', workflow)
        self.assertRegex(workflow, r"(?m)^  workflow_dispatch:\s*$")
        self.assertIn("permissions:\n  contents: write\n", workflow)
        permission_block = re.search(
            r"(?ms)^permissions:\n(.*?)(?=^[a-zA-Z])", workflow
        )
        self.assertIsNotNone(permission_block)
        self.assertEqual(permission_block.group(1).strip(), "contents: write")

    def test_only_official_action_is_pinned_to_full_sha(self) -> None:
        workflow = (ROOT / ".github/workflows/build-release.yml").read_text(
            encoding="utf-8"
        )
        actions = re.findall(r"(?m)^\s+uses:\s+(\S+)", workflow)
        self.assertEqual(
            actions,
            [
                "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"
            ],
        )

    def test_converter_and_source_are_explicitly_pinned(self) -> None:
        versions = (ROOT / "scripts/versions.env").read_text(encoding="utf-8")
        self.assertIn('MIHOMO_VERSION="v1.19.28"', versions)
        self.assertRegex(versions, r'(?m)^MIHOMO_ASSET_SHA256="[0-9a-f]{64}"$')
        self.assertIn(
            'SOURCE_URL="https://fastly.jsdelivr.net/gh/Loyalsoldier/'
            'clash-rules@release/reject.txt"',
            versions,
        )
        self.assertNotIn("latest", versions.lower())

    def test_publication_is_non_forced_and_config_uses_mrs(self) -> None:
        publisher = (ROOT / "scripts/publish-release.sh").read_text(encoding="utf-8")
        self.assertNotRegex(publisher, r"(?m)^.*git\s+.*push\s+.*--force")
        self.assertIn('push origin HEAD:release', publisher)
        config = (ROOT / "config/reject-provider.yaml").read_text(encoding="utf-8")
        self.assertIn("format: mrs", config)
        self.assertIn("path: ./ruleset/loyalsoldier/reject.mrs", config)


if __name__ == "__main__":
    unittest.main()
