# ShellCrash / Mihomo deployment and rollback

This document covers the `reject`, `direct`, and `proxy` MRS cutover. It never
converts YAML on the router or on the AdGuard host.

## 1. Verify the cloud publication

After a successful GitHub Actions run, verify all nine files on a development
workstation:

```bash
base="https://raw.githubusercontent.com/SarinV/loyalsoldier-reject-mrs/release"
for name in reject direct proxy; do
  curl --fail --location --output "$name.mrs" "$base/$name.mrs"
  curl --fail --location --output "$name.mrs.sha256" "$base/$name.mrs.sha256"
  curl --fail --location --output "$name.meta" "$base/$name.meta"
  sha256sum --check "$name.mrs.sha256"
  cat "$name.meta"
done
```

Check that each metadata file contains `provider_name`, `source_sha256`,
`source_rule_count`, `normalized_redundant_exact_rules`,
`mrs_export_rule_count`, `mrs_sha256`, `mrs_bytes`, `mihomo_version`, and
`generated_at_utc`. All nine files must come from the same `release` commit.

## 2. Update the persistent override

Use the entries in `config/rule-providers.yaml`. Preserve each provider name,
`behavior: domain`, and existing rule references; change only its `format`,
URL, and cache path from YAML to MRS.

Do not change the override until `direct.mrs` and `proxy.mrs` have actually
appeared on the release branch and passed checksum verification. Do not delete
or refresh the old YAML caches during this cutover.

## 3. Apply and verify

1. Save exact copies and hashes of the persistent and generated runtime config.
2. Apply the updated persistent override once, so all three provider entries
   are generated from one script revision.
3. Let ShellCrash/CrashCore download the already-converted MRS files. No YAML
   conversion should run on the router.
4. Verify through the rule-provider API:

```text
reject.format = MrsRule
direct.format = MrsRule
proxy.format  = MrsRule
```

5. Compare each API rule count with the corresponding `source_rule_count` in
   the published metadata.
6. Monitor CrashCore PID, RSS, RssAnon, VmHWM, MemAvailable, kernel OOM logs,
   and provider errors across the reload and first update.

An entire configuration reload initializes more than these three providers and
has a different memory envelope from one isolated MRS update. Record reload and
provider-update peaks separately.

## 4. Rollback

### Roll back bad generated files

Prefer reverting the complete bad release commit:

```bash
git switch release
git revert <BAD_RELEASE_COMMIT>
git push origin release
```

Recheck all three hashes. This preserves an atomic and auditable release set.

### Roll back the router configuration

If the provider configuration itself is invalid, restore the saved override
and runtime configuration as one transaction and reload CrashCore while
monitoring memory. Restoring `direct` or `proxy` to HTTP/YAML also restores its
high-allocation parse path, so it is an emergency rollback rather than the
normal response to one bad cloud artifact.
