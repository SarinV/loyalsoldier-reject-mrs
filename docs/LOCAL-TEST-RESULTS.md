# Local test results

Test date: 2026-07-14

The local workstation was used only for download, validation, and conversion.
No router or AdGuard host was changed.

## Full current inputs

All three sources were downloaded from the URLs pinned in
`scripts/versions.env`, passed strict validation, converted with the audited
official Mihomo source baseline, exported back to normalized text, and compared
as complete effective rule sets.

| Provider | Input bytes | Input rules | Input SHA-256 | MRS bytes | MRS SHA-256 |
| --- | ---: | ---: | --- | ---: | --- |
| reject | 4,731,145 | 165,713 | `ce8186fc60626e57e814acb856dca6c91b698d6e9053406dc2f22a084cade363` | 1,583,605 | `326f265d2ce23471853af7782c2988bc0a5773c28a6c85c44c3a04d8ae68f30e` |
| direct | 2,324,011 | 112,274 | `9567b45a71359851ea28f8e42d5664d0da9ba1970b485a1fa2a59d6514ac559e` | 543,947 | `79901a429cc8b6998c57b93703334ddf11d3b3179a8b92ede5233b4a563400e4` |
| proxy | 611,983 | 26,842 | `21709f4b368ae3908495c7d484e3821a6efcdc5e0634553157c555b3a6f5154d` | 196,640 | `17551485656665dcf58ddda8412d228b00ef6ac8a098d7cf20940492cee96111` |

Mihomo's DomainSet text export intentionally suppresses an exact domain when
the same source also contains `+.<domain>`, because the suffix rule already
creates the exact matcher node. This normalized 52 redundant exact spellings
in `direct` and one in `proxy`; all remaining effective rules matched exactly,
with zero source-only and zero output-only rules. The MRS header still records
the source strategy count, so the expected provider API counts are 112,274 and
26,842 respectively.

## Automated checks

- Python unit and repository-policy tests: 14/14 PASS.
- GitHub workflow YAML: parsed successfully with `gopkg.in/yaml.v3`.
- Complete source validation and semantic MRS round-trip: PASS for all three.
- `reject.mrs` remained byte-identical to the already-audited production file.
- `tests/test_publish.sh` now covers atomic nine-file publication, a no-op when
  all source/MRS hashes are unchanged, an update where only one provider
  changes, and corruption rejection before the release ref changes.

## CI checks still required

The local Windows runtime does not include Bash. The first reviewed GitHub
Actions run must therefore execute:

- `bash -n` over all shell scripts;
- the transactional publication shell test;
- download and SHA-256 verification of the pinned official Mihomo v1.19.28
  Linux AMD64 asset;
- `mihomo -v` equality and the complete three-provider build using that exact
  release binary;
- atomic update of the existing `release` branch from three files to nine.

Do not switch `direct` or `proxy` on the router until that run passes and both
new MRS files, checksum files, and metadata files are visible on `release`.
