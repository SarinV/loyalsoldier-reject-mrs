# Loyalsoldier MRS builder

This repository converts Loyalsoldier's three largest domain providers used by
the target ShellCrash deployment—`reject`, `direct`, and `proxy`—into Mihomo
MRS on a GitHub-hosted Linux AMD64 runner. Conversion and hosting never happen
on the router or on an AdGuard node.

## Published files

After a successful workflow run, the `release` branch contains one atomic set
of nine files:

- `reject.mrs`, `reject.mrs.sha256`, `reject.meta`
- `direct.mrs`, `direct.mrs.sha256`, `direct.meta`
- `proxy.mrs`, `proxy.mrs.sha256`, `proxy.meta`

Stable download addresses:

```text
https://raw.githubusercontent.com/SarinV/loyalsoldier-reject-mrs/release/reject.mrs
https://raw.githubusercontent.com/SarinV/loyalsoldier-reject-mrs/release/direct.mrs
https://raw.githubusercontent.com/SarinV/loyalsoldier-reject-mrs/release/proxy.mrs
```

## Schedule and sources

- Sources: `reject.txt`, `direct.txt`, and `proxy.txt` from
  <https://github.com/Loyalsoldier/clash-rules/tree/release> through jsDelivr.
- Loyalsoldier documents its daily build at 06:30 Asia/Shanghai.
- This workflow runs at 00:30 UTC, or 08:30 Asia/Shanghai and Asia/Singapore,
  leaving two hours for upstream publication and CDN propagation.
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
`mihomo -v`, rejects a version mismatch, and never resolves `latest`.

The only reusable Action is GitHub's own `actions/checkout`, pinned to the full
v6.0.2 commit SHA `de0fac2e4500dabe0009e67214ff5f5447ce83dd`.

## Validation and publication guarantees

Each source must pass an independent HTTP, UTF-8, NUL, byte-size, YAML-shape,
minimum-rule-count, uniqueness, scalar, and indentation check. The per-provider
thresholds are deliberately different and are recorded in
`scripts/versions.env`.

The workflow then runs the equivalent of:

```bash
mihomo convert-ruleset domain yaml reject.txt reject.mrs
mihomo convert-ruleset domain yaml direct.txt direct.mrs
mihomo convert-ruleset domain yaml proxy.txt proxy.mrs
```

Every MRS must be non-empty and meet its minimum size. The same pinned Mihomo
binary exports each MRS back to text, and the workflow compares the complete
normalized rule set with the corresponding source.

The `release` branch changes only after all three providers pass. One Git commit
replaces all nine files together. If every source and published MRS SHA-256 is
unchanged, generated-time-only differences do not create a commit. A failed
job leaves the previous complete release intact.

## Mihomo configuration

See `config/rule-providers.yaml` and `docs/DEPLOYMENT.md`.

```yaml
rule-providers:
  reject:
    type: http
    behavior: domain
    format: mrs
    interval: 86400
    url: https://raw.githubusercontent.com/SarinV/loyalsoldier-reject-mrs/release/reject.mrs
    path: ./ruleset/loyalsoldier/reject.mrs
  direct:
    type: http
    behavior: domain
    format: mrs
    interval: 86400
    url: https://raw.githubusercontent.com/SarinV/loyalsoldier-reject-mrs/release/direct.mrs
    path: ./ruleset/loyalsoldier/direct.mrs
  proxy:
    type: http
    behavior: domain
    format: mrs
    interval: 86400
    url: https://raw.githubusercontent.com/SarinV/loyalsoldier-reject-mrs/release/proxy.mrs
    path: ./ruleset/loyalsoldier/proxy.mrs
```

## Manual build

On Linux AMD64 with `curl`, `gzip`, Python 3 and standard GNU tools:

```bash
./scripts/build.sh dist
for checksum in dist/*.mrs.sha256; do (cd dist && sha256sum --check "$(basename "$checksum")"); done
cat dist/*.meta
```

For offline tests, put all three source files in one directory and set
`SOURCE_DIR`. `MIHOMO_BIN` and `SOURCE_DIR` are local test overrides and are not
set by the GitHub workflow.

## Rollback

The workflow never force-pushes `release`. Revert a bad release commit on that
branch and push the revert; all three raw URLs then resolve to the preceding
complete set. Do not fall back to large YAML providers merely to roll back a
bad generated artifact.

## License and attribution

- Source rules: [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules), GPL-3.0.
- Converter: [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo), GPL-3.0.
- This automation repository is distributed under GPL-3.0.

The MRS files are machine-converted forms of Loyalsoldier's rules. Preserve
the source attribution, metadata, and GPL-3.0 notice when redistributing them.
Mihomo is downloaded from its official release page during the workflow and is
not committed to this repository.
