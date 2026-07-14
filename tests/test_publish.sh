#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/reject-publish-test.XXXXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

origin="$test_root/origin.git"
checkout="$test_root/checkout"
dist="$test_root/dist"

git init --bare "$origin" >/dev/null
git clone "$origin" "$checkout" >/dev/null 2>&1
git -C "$checkout" switch -c main >/dev/null
git -C "$checkout" config user.name test
git -C "$checkout" config user.email test@example.invalid
printf 'seed\n' > "$checkout/README.md"
git -C "$checkout" add README.md
git -C "$checkout" commit -m seed >/dev/null
git -C "$checkout" push -u origin main >/dev/null
mkdir -p "$checkout/scripts" "$dist"
cp "$repo_root/scripts/publish-release.sh" "$checkout/scripts/publish-release.sh"

write_artifacts() {
  local source_sha="$1"
  local mrs_marker="$2"
  local meta_marker="$3"
  local mrs_sha
  printf 'mrs-%s\n' "$mrs_marker" > "$dist/reject.mrs"
  mrs_sha="$(sha256sum "$dist/reject.mrs" | awk '{print $1}')"
  printf '%s  reject.mrs\n' "$mrs_sha" > "$dist/reject.mrs.sha256"
  {
    printf 'schema_version=1\n'
    printf 'source_sha256=%s\n' "$source_sha"
    printf 'mrs_sha256=%s\n' "$mrs_sha"
    printf 'marker=%s\n' "$meta_marker"
  } > "$dist/reject.meta"
}

sha_a="$(printf a | sha256sum | awk '{print $1}')"
sha_b="$(printf b | sha256sum | awk '{print $1}')"

write_artifacts "$sha_a" first first
(
  cd "$checkout"
  ALLOW_LOCAL_PUBLISH_TEST=1 ./scripts/publish-release.sh "$dist"
)
first_count="$(git --git-dir="$origin" rev-list --count release)"
[[ "$first_count" == "1" ]]

# Metadata outside source_sha256 changes, but the source is the same: no commit.
write_artifacts "$sha_a" first timestamp-only-change
(
  cd "$checkout"
  ALLOW_LOCAL_PUBLISH_TEST=1 ./scripts/publish-release.sh "$dist"
)
same_count="$(git --git-dir="$origin" rev-list --count release)"
[[ "$same_count" == "$first_count" ]]

write_artifacts "$sha_b" second second
(
  cd "$checkout"
  ALLOW_LOCAL_PUBLISH_TEST=1 ./scripts/publish-release.sh "$dist"
)
second_count="$(git --git-dir="$origin" rev-list --count release)"
[[ "$second_count" == "2" ]]

# A damaged artifact must fail before any release ref changes.
printf 'corrupt\n' >> "$dist/reject.mrs"
if (
  cd "$checkout"
  ALLOW_LOCAL_PUBLISH_TEST=1 ./scripts/publish-release.sh "$dist"
); then
  echo "corrupted MRS was unexpectedly published" >&2
  exit 1
fi
failed_count="$(git --git-dir="$origin" rev-list --count release)"
[[ "$failed_count" == "$second_count" ]]

printf 'publish transaction tests passed\n'
