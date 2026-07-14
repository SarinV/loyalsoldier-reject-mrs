# Local test results

Test date: 2026-07-14

The local workstation was used only for validation. No router, AdGuard host, or
GitHub repository was changed.

## Audited full input

Input: the preserved 2026-07-14 Loyalsoldier `reject.txt` snapshot captured
during the Mihomo OOM audit.

| Check | Result |
| --- | --- |
| Input bytes | 4,731,145 |
| Input SHA-256 | `ce8186fc60626e57e814acb856dca6c91b698d6e9053406dc2f22a084cade363` |
| Rules | 165,713 |
| Unique rules | 165,713 |
| Strict source validation | PASS |
| MRS bytes | 1,583,605 |
| MRS SHA-256 | `326f265d2ce23471853af7782c2988bc0a5773c28a6c85c44c3a04d8ae68f30e` |
| MRS round-trip source-only rules | 0 |
| MRS round-trip output-only rules | 0 |

An already-built official Mihomo source baseline was used for the local
functional conversion. It reproduced the audited MRS byte-for-byte in about
4.34 seconds. This confirms the command, validator, rule-count check, and
full-set semantic comparison on the complete input.

## Automated tests

- `python3 -m unittest discover -s tests -p 'test_*.py' -v`: 12/12 PASS.
- GitHub workflow YAML parsed successfully with `gopkg.in/yaml.v3`.
- `tests/test_publish.sh` covers first publication, unchanged-input no-op, and
  a second changed-input fast-forward publication, plus a corrupted-artifact
  rejection that leaves the release ref unchanged. It is executed by the
  GitHub workflow before any production build or push.

## Deliberately pending CI checks

The local Windows sandbox has neither a working Bash runtime nor outbound
access to GitHub release assets. Therefore these checks are intentionally left
for the first reviewed `workflow_dispatch` run on GitHub's Ubuntu runner:

- `bash -n` over all shell scripts;
- the transactional publication shell test;
- download of the pinned official Mihomo v1.19.28 Linux AMD64 asset;
- verification of its pinned SHA-256;
- `mihomo -v` equality check and the complete v1.19.28 conversion pipeline.

Do not deploy the raw URL until that first workflow run passes and the three
files on the `release` branch have been inspected.
