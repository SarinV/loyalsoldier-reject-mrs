#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/scripts/versions.env"

dist_dir="${1:?usage: publish-release.sh DIST_DIR}"
dist_dir="$(cd "$dist_dir" && pwd)"
read -r -a rulesets <<< "$RULESETS"

declare -A source_sha256s
declare -A mrs_sha256s

# Validate the complete release set before inspecting or modifying Git state.
for name in "${rulesets[@]}"; do
  for artifact in "$name.mrs" "$name.mrs.sha256" "$name.meta"; do
    if [[ ! -s "$dist_dir/$artifact" ]]; then
      echo "missing or empty artifact: $dist_dir/$artifact" >&2
      exit 1
    fi
  done

  checksum_line="$(cat "$dist_dir/$name.mrs.sha256")"
  if [[ "$checksum_line" =~ ^([0-9a-f]{64})[[:space:]][[:space:]]([a-z0-9-]+\.mrs)$ ]] &&
     [[ "${BASH_REMATCH[2]}" == "$name.mrs" ]]; then
    mrs_sha256="${BASH_REMATCH[1]}"
  else
    echo "$name.mrs.sha256 must contain exactly one canonical checksum line" >&2
    exit 1
  fi

  actual_mrs_sha256="$(sha256sum "$dist_dir/$name.mrs" | awk '{print $1}')"
  meta_mrs_sha256="$(sed -n 's/^mrs_sha256=//p' "$dist_dir/$name.meta")"
  meta_provider_name="$(sed -n 's/^provider_name=//p' "$dist_dir/$name.meta")"
  if [[ "$actual_mrs_sha256" != "$mrs_sha256" ||
        "$meta_mrs_sha256" != "$mrs_sha256" ||
        "$meta_provider_name" != "$name" ]]; then
    echo "$name artifact, checksum, and metadata do not agree" >&2
    exit 1
  fi

  source_sha256="$(sed -n 's/^source_sha256=//p' "$dist_dir/$name.meta")"
  if [[ ! "$source_sha256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "$name.meta has an invalid source_sha256" >&2
    exit 1
  fi
  source_sha256s["$name"]="$source_sha256"
  mrs_sha256s["$name"]="$mrs_sha256"
done

if [[ "${GITHUB_ACTIONS:-false}" != "true" && "${ALLOW_LOCAL_PUBLISH_TEST:-0}" != "1" ]]; then
  echo "refusing to publish outside GitHub Actions" >&2
  exit 1
fi

release_exists=false
if git -C "$repo_root" ls-remote --exit-code --heads origin release >/dev/null 2>&1; then
  release_exists=true
  git -C "$repo_root" fetch --no-tags origin \
    refs/heads/release:refs/remotes/origin/release

  all_unchanged=true
  for name in "${rulesets[@]}"; do
    old_source_sha256="$(
      git -C "$repo_root" show "refs/remotes/origin/release:$name.meta" 2>/dev/null |
        sed -n 's/^source_sha256=//p' || true
    )"
    old_mrs_sha256="$(
      git -C "$repo_root" show "refs/remotes/origin/release:$name.meta" 2>/dev/null |
        sed -n 's/^mrs_sha256=//p' || true
    )"
    old_actual_mrs_sha256="$(
      git -C "$repo_root" show "refs/remotes/origin/release:$name.mrs" 2>/dev/null |
        sha256sum | awk '{print $1}' || true
    )"
    if [[ "$old_source_sha256" != "${source_sha256s[$name]}" ||
          "$old_mrs_sha256" != "${mrs_sha256s[$name]}" ||
          "$old_actual_mrs_sha256" != "${mrs_sha256s[$name]}" ]]; then
      all_unchanged=false
    fi
  done
  if [[ "$all_unchanged" == "true" ]]; then
    echo "All input and published MRS SHA-256 values are unchanged; release branch remains untouched."
    exit 0
  fi
fi

worktree_parent="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/loyalsoldier-release-worktree.XXXXXXXX")"
release_worktree="$worktree_parent/release"
cleanup() {
  git -C "$repo_root" worktree remove --force "$release_worktree" >/dev/null 2>&1 || true
  rm -rf -- "$worktree_parent"
}
trap cleanup EXIT

if [[ "$release_exists" == "true" ]]; then
  git -C "$repo_root" worktree add -B release "$release_worktree" refs/remotes/origin/release
else
  git -C "$repo_root" worktree add --detach "$release_worktree" HEAD
  git -C "$release_worktree" switch --orphan release
fi

find "$release_worktree" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf -- {} +
for name in "${rulesets[@]}"; do
  cp -- "$dist_dir/$name.mrs" "$release_worktree/$name.mrs"
  cp -- "$dist_dir/$name.mrs.sha256" "$release_worktree/$name.mrs.sha256"
  cp -- "$dist_dir/$name.meta" "$release_worktree/$name.meta"
done

git -C "$release_worktree" add --all
if git -C "$release_worktree" diff --cached --quiet; then
  echo "Artifacts are byte-identical; release branch remains untouched."
  exit 0
fi

git -C "$release_worktree" config user.name "github-actions[bot]"
git -C "$release_worktree" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$release_worktree" commit -m "chore(release): update MRS rulesets $(date -u '+%Y-%m-%d')"
git -C "$release_worktree" push origin HEAD:release
echo "Published release commit $(git -C "$release_worktree" rev-parse HEAD)"
