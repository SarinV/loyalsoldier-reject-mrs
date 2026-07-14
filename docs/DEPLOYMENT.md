# ShellCrash / Mihomo deployment and rollback

This document prepares a production cutover; it does not perform one. Do not
convert YAML on the router or on the AdGuard host.

## 1. Verify the cloud publication

After the first successful GitHub Actions run, download all three files on a
development workstation:

```bash
base="https://raw.githubusercontent.com/SarinV/loyalsoldier-reject-mrs/release"
curl --fail --location --output reject.mrs "$base/reject.mrs"
curl --fail --location --output reject.mrs.sha256 "$base/reject.mrs.sha256"
curl --fail --location --output reject.meta "$base/reject.meta"
sha256sum --check reject.mrs.sha256
cat reject.meta
```

For the audited source snapshot, the expected rule count is 165,713. A future
upstream build may change that exact count, but the workflow refuses fewer than
150,000 rules. Confirm that `source_sha256`, `source_rule_count`, `mrs_sha256`,
`mrs_bytes`, `mihomo_version` and `generated_at_utc` are present.

## 2. Prepare the configuration

Replace the existing `reject` provider with:

```yaml
reject:
  type: http
  behavior: domain
  format: mrs
  interval: 86400
  url: https://raw.githubusercontent.com/SarinV/loyalsoldier-reject-mrs/release/reject.mrs
  path: ./ruleset/loyalsoldier/reject.mrs
```

Apply the change in ShellCrash's persistent configuration generator or overlay,
not only in `/tmp/ShellCrash/config.yaml`. The current Mihomo-OIX source
repository does not contain ShellCrash's generator, so its exact integration
file must be reviewed in the ShellCrash configuration repository separately.

## 3. Stage both files before reloading

1. Keep the old YAML cache. Do not refresh it and do not delete it yet.
2. Upload the verified MRS as
   `ruleset/loyalsoldier/reject.mrs.new`.
3. Upload the new persistent and runtime configuration as `.new` files.
4. Recompute SHA-256 on the router and compare it with `reject.mrs.sha256`.
5. Run `CrashCore -t` against the candidate runtime configuration. Configuration
   test mode constructs providers but must not be used to convert the YAML.
6. In one maintenance window, rename `reject.mrs.new` to `reject.mrs`, then
   atomically replace both configuration files.
7. Reload the default CrashCore configuration through its controller. Do not
   invoke the old YAML provider's update endpoint.

Pre-staging matters: during the configuration reload, the HTTP/MRS provider can
load the verified local cache immediately instead of depending on a network
download while the old provider is being replaced.

## 4. Verify the cutover

Check the rule-provider API:

```text
reject.vehicleType = HTTP
reject.format      = MrsRule
reject.ruleCount   = 165713   # for the audited snapshot
```

Also verify:

- the new URL and `.mrs` path are present in persistent and runtime configs;
- DNS and normal routed traffic still work;
- CrashCore PID/health, RSS, RssAnon and MemAvailable remain safe;
- no `.new` file remains after the transaction.

The `<25 MiB` memory target applies to isolated MRS parsing and subsequent
`reject` updates. A first full `/configs` reload reinitializes every configured
provider and has a different memory envelope. In the earlier controlled router
cutover, isolated MRS parsing was about +13.4 MiB RSS, while the full config
reload was about +108.3 MiB RSS. Record these two measurements separately.

Only after a stable observation window should the obsolete damaged YAML cache
be archived or removed.

## 5. Rollback

### Roll back a bad published MRS

Prefer this path. Revert the bad commit on the `release` branch:

```bash
git switch release
git revert <BAD_RELEASE_COMMIT>
git push origin release
```

Verify the raw file SHA again, then update the provider normally. The release
history remains auditable and the branch is never force-pushed by automation.

### Roll back the router configuration

Before cutover, save exact copies and hashes of both persistent and runtime
configurations. If a configuration rollback is unavoidable, restore both files
as one transaction and reload CrashCore while monitoring memory.

Restoring the former `HTTP/YAML` provider also restores the known OOM path. It
must not be treated as the normal rollback for a bad MRS artifact; prefer
reverting the `release` branch to the preceding valid MRS.
