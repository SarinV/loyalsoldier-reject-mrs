#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/loyalsoldier-publish-test.XXXXXXXX")"
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
cp "$repo_root/scripts/versions.env" "$checkout/scripts/versions.env"

write_artifacts() {
  local reject_seed="$1"
  local direct_seed="$2"
  local proxy_seed="$3"
  local meta_marker="$4"
  local name seed source_sha mrs_sha

  for name in reject direct proxy; do
    case "$name" in
      reject) seed="$reject_seed" ;;
      direct) seed="$direct_seed" ;;
      proxy) seed="$proxy_seed" ;;
    esac
    source_sha="$(printf '%s-%s' "$name" "$seed" | sha256sum | awk '{print $1}')"
    printf 'mrs-%s-%s\n' "$name" "$seed" > "$dist/$name.mrs"
    mrs_sha="$(sha256sum "$dist/$name.mrs" | awk '{print $1}')"
    printf '%s  %s.mrs\n' "$mrs_sha" "$name" > "$dist/$name.mrs.sha256"
    {
      printf 'schema_version=1\n'
      printf 'provider_name=%s\n' "$name"
      printf 'source_sha256=%s\n' "$source_sha"
      printf 'mrs_sha256=%s\n' "$mrs_sha"
      printf 'marker=%s\n' "$meta_marker"
    } > "$dist/$name.meta"
  done
}

write_artifacts a a a first
(
  cd "$checkout"
  ALLOW_LOCAL_PUBLISH_TEST=1 ./scripts/publish-release.sh "$dist"
)
first_count="$(git --git-dir="$origin" rev-list --count release)"
[[ "$first_count" == "1" ]]
published_files="$(git --git-dir="$origin" ls-tree --name-only release | wc -l | tr -d '[:space:]')"
[[ "$published_files" == "9" ]]

# Metadata changes, but every source and MRS hash is unchanged: no commit.
write_artifacts a a a timestamp-only-change
(
  cd "$checkout"
  ALLOW_LOCAL_PUBLISH_TEST=1 ./scripts/publish-release.sh "$dist"
)
same_count="$(git --git-dir="$origin" rev-list --count release)"
[[ "$same_count" == "$first_count" ]]

# One provider changing publishes all nine files in one new commit.
write_artifacts a b a direct-changed
(
  cd "$checkout"
  ALLOW_LOCAL_PUBLISH_TEST=1 ./scripts/publish-release.sh "$dist"
)
second_count="$(git --git-dir="$origin" rev-list --count release)"
[[ "$second_count" == "2" ]]

# A damaged artifact fails before the release ref can change.
printf 'corrupt\n' >> "$dist/proxy.mrs"
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
