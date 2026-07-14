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
        self.assertIn(
            "      - name: Publish the release branch\n"
            "        if: github.ref == format('refs/heads/{0}', "
            "github.event.repository.default_branch)",
            workflow,
        )
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

    def test_converter_and_sources_are_explicitly_pinned(self) -> None:
        versions = (ROOT / "scripts/versions.env").read_text(encoding="utf-8")
        self.assertIn('MIHOMO_VERSION="v1.19.28"', versions)
        self.assertRegex(versions, r'(?m)^MIHOMO_ASSET_SHA256="[0-9a-f]{64}"$')
        self.assertIn('RULESETS="reject direct proxy"', versions)
        for name in ("reject", "direct", "proxy"):
            self.assertIn(
                f'{name.upper()}_SOURCE_URL="https://fastly.jsdelivr.net/gh/'
                f'Loyalsoldier/clash-rules@release/{name}.txt"',
                versions,
            )
            self.assertRegex(
                versions,
                rf'(?m)^{name.upper()}_MIN_RULES="[0-9]+"$',
            )
        self.assertNotIn("latest", versions.lower())

    def test_publication_is_non_forced_and_configs_use_mrs(self) -> None:
        publisher = (ROOT / "scripts/publish-release.sh").read_text(encoding="utf-8")
        builder = (ROOT / "scripts/build.sh").read_text(encoding="utf-8")
        self.assertNotRegex(publisher, r"(?m)^.*git\s+.*push\s+.*--force")
        self.assertIn('push origin HEAD:release', publisher)
        self.assertIn("normalized_redundant_exact_rules=", builder)
        self.assertIn("mrs_export_rule_count=", builder)
        config = (ROOT / "config/rule-providers.yaml").read_text(encoding="utf-8")
        self.assertEqual(config.count("format: mrs"), 3)
        for name in ("reject", "direct", "proxy"):
            self.assertIn(f"path: ./ruleset/loyalsoldier/{name}.mrs", config)
            self.assertIn(f"release/{name}.mrs", config)


if __name__ == "__main__":
    unittest.main()
