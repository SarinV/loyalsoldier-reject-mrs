# Loyalsoldier reject.mrs builder

This is a minimal GitHub Actions repository that converts Loyalsoldier's
`reject.txt` into Mihomo MRS on a GitHub-hosted Linux AMD64 runner. Conversion
and hosting never happen on the router or on an AdGuard node.

The repository is prepared locally for review. It does not create a GitHub
repository and does not push anything by itself.

## Published files

After the first successful workflow run, the `release` branch contains exactly:

- `reject.mrs`
- `reject.mrs.sha256`
- `reject.meta`

The stable download address is:

```text
https://raw.githubusercontent.com/<OWNER>/<REPO>/release/reject.mrs
```

Replace `<OWNER>/<REPO>` only after creating the public repository.

## Schedule and data source

- Source: <https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt>
- Loyalsoldier documents its build at 06:30 Asia/Shanghai each day.
- This workflow runs at 00:30 UTC, which is 08:30 in Asia/Shanghai and
  Asia/Singapore, leaving two hours for publication and CDN propagation.
- `workflow_dispatch` supports an audited manual run.

## Pinned converter

The workflow downloads only this official MetaCubeX release asset:

```text
Mihomo version: v1.19.28
Asset: mihomo-linux-amd64-compatible-v1.19.28.gz
URL: https://github.com/MetaCubeX/mihomo/releases/download/v1.19.28/mihomo-linux-amd64-compatible-v1.19.28.gz
SHA-256: 70d01cfb8cb7bf7a92fd1af16cb4b9553d90bb4eecde3b5c4849103e27c80ddb
```

The version and digest live in `scripts/versions.env`. The workflow prints
`mihomo -v` and rejects a version mismatch. It never resolves `latest`.

The only reusable Action is GitHub's own `actions/checkout`, pinned to the full
v6.0.2 commit SHA `de0fac2e4500dabe0009e67214ff5f5447ce83dd`.

## Validation and publication guarantees

Before conversion, the workflow requires:

- a successful final HTTP 2xx response;
- valid UTF-8 and no NUL bytes;
- source size between 1,000,000 and 16,777,216 bytes;
- one canonical top-level `payload:` sequence;
- at least 150,000 unique domain rules;
- no invalid indentation, unclosed scalar, control character, whitespace or
  slash-containing domain rule.

It then runs exactly:

```bash
mihomo convert-ruleset domain yaml reject.txt reject.mrs
```

The result must be non-empty and at least 100,000 bytes. The same pinned Mihomo
binary converts MRS back to text, and the workflow compares all normalized
rules with the source. Count-only validation is not considered sufficient.

`release` is changed only after all checks pass. One Git commit updates the
three artifacts together. If both the input and already-published MRS SHA-256
are unchanged, generated-time-only differences do not create a commit. A
failed job never changes the old `release` branch; an inconsistent remote MRS
is repaired instead of being mistaken for a no-op.

## Repository setup

1. Create an empty **public** GitHub repository.
2. Copy this directory into it and push the default branch.
3. In **Settings -> Actions -> General -> Workflow permissions**, allow the
   repository `GITHUB_TOKEN` to write repository contents. The workflow itself
   narrows permissions to `contents: write` only.
4. Run **Build and publish reject.mrs** once with `workflow_dispatch`.
5. Inspect `release/reject.meta`, verify `reject.mrs.sha256`, and only then use
   the raw URL in Mihomo.

No personal access token or external secret is required.

## Mihomo configuration

See `config/reject-provider.yaml` and `docs/DEPLOYMENT.md`.

```yaml
reject:
  type: http
  behavior: domain
  format: mrs
  interval: 86400
  url: https://raw.githubusercontent.com/<OWNER>/<REPO>/release/reject.mrs
  path: ./ruleset/loyalsoldier/reject.mrs
```

## Manual build

On Linux AMD64 with `curl`, `gzip`, Python 3 and standard GNU tools:

```bash
./scripts/build.sh dist
cat dist/reject.meta
(cd dist && sha256sum --check reject.mrs.sha256)
```

The script downloads and verifies the same pinned official Mihomo binary.
`MIHOMO_BIN` and `SOURCE_FILE` are test-only local overrides and are not set by
the GitHub workflow.

## Rollback

The workflow never force-pushes `release`. To roll back an artifact, revert the
bad release commit on that branch and push the revert. The raw URL then points
to the preceding complete MRS set. Do not switch the router back to the large
YAML provider merely to roll back one MRS release.

Detailed deployment and rollback steps are in `docs/DEPLOYMENT.md`.
Local full-input validation results and the remaining first-CI checks are in
`docs/LOCAL-TEST-RESULTS.md`.

## License and attribution

- Source rules: [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules), GPL-3.0.
- Converter: [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo), GPL-3.0.
- This automation repository is distributed under GPL-3.0.

`reject.mrs` is a machine-converted form of Loyalsoldier's rules. Preserve the
source attribution, metadata and GPL-3.0 notice when redistributing it. Mihomo
is downloaded from its official release page during the workflow and is not
committed to this repository.
