#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/scripts/versions.env"

python_bin="${PYTHON_BIN:-python3}"
output_dir="${1:-$repo_root/dist}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/reject-mrs-build.XXXXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

mkdir -p "$output_dir"
source_file="$work_dir/reject.txt"
source_http_status="local"

if [[ -n "${SOURCE_FILE:-}" ]]; then
  cp -- "$SOURCE_FILE" "$source_file"
else
  source_http_status="$({
    curl \
      --proto '=https' \
      --tlsv1.2 \
      --fail \
      --location \
      --silent \
      --show-error \
      --retry 3 \
      --retry-all-errors \
      --connect-timeout 20 \
      --max-time 180 \
      --output "$source_file" \
      --write-out '%{http_code}' \
      "$SOURCE_URL"
  })"
  if [[ ! "$source_http_status" =~ ^2[0-9][0-9]$ ]]; then
    echo "unexpected final HTTP status: $source_http_status" >&2
    exit 1
  fi
fi

"$python_bin" "$repo_root/scripts/validate_source.py" \
  --input "$source_file" \
  --min-bytes "$MIN_SOURCE_BYTES" \
  --max-bytes "$MAX_SOURCE_BYTES" \
  --min-rules "$MIN_RULES" \
  --json-out "$work_dir/source.json" \
  --canonical-out "$work_dir/source-rules.txt"

mihomo_mode="official_release"
if [[ -n "${MIHOMO_BIN:-}" ]]; then
  mihomo_bin="$(cd "$(dirname "$MIHOMO_BIN")" && pwd)/$(basename "$MIHOMO_BIN")"
  mihomo_mode="local_override"
else
  mihomo_archive="$work_dir/$MIHOMO_ASSET"
  curl \
    --proto '=https' \
    --tlsv1.2 \
    --fail \
    --location \
    --silent \
    --show-error \
    --retry 3 \
    --retry-all-errors \
    --connect-timeout 20 \
    --max-time 300 \
    --output "$mihomo_archive" \
    "$MIHOMO_RELEASE_URL"
  printf '%s  %s\n' "$MIHOMO_ASSET_SHA256" "$mihomo_archive" | sha256sum --check --strict
  gzip --test "$mihomo_archive"
  mihomo_bin="$work_dir/mihomo"
  gzip --decompress --stdout "$mihomo_archive" > "$mihomo_bin"
  chmod 0755 "$mihomo_bin"
fi

mihomo_reported_version="$($mihomo_bin -v | tr '\r\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//')"
echo "Mihomo version: $mihomo_reported_version"
if [[ "${ALLOW_VERSION_MISMATCH:-0}" != "1" ]] && \
   [[ "$mihomo_reported_version" != *"${MIHOMO_VERSION#v}"* ]]; then
  echo "Mihomo reported version does not match pinned $MIHOMO_VERSION" >&2
  exit 1
fi

"$mihomo_bin" convert-ruleset domain yaml "$source_file" "$work_dir/reject.mrs"
if [[ ! -s "$work_dir/reject.mrs" ]]; then
  echo "MRS output is empty" >&2
  exit 1
fi
mrs_bytes="$(wc -c < "$work_dir/reject.mrs" | tr -d '[:space:]')"
if (( mrs_bytes < MIN_MRS_BYTES )); then
  echo "MRS output is unexpectedly small: $mrs_bytes bytes" >&2
  exit 1
fi

# The official converter can export MRS back to text. Comparing the full set
# catches a non-empty but semantically incomplete or malformed artifact.
"$mihomo_bin" convert-ruleset domain mrs "$work_dir/reject.mrs" "$work_dir/roundtrip.txt"
"$python_bin" "$repo_root/scripts/compare_rules.py" \
  --source "$work_dir/source-rules.txt" \
  --roundtrip "$work_dir/roundtrip.txt" \
  --json-out "$work_dir/semantic.json"

source_sha256="$($python_bin -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["sha256"])' "$work_dir/source.json")"
source_bytes="$($python_bin -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["bytes"])' "$work_dir/source.json")"
source_rule_count="$($python_bin -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["rule_count"])' "$work_dir/source.json")"
mrs_sha256="$(sha256sum "$work_dir/reject.mrs" | awk '{print $1}')"
generated_at_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
publish_repository="${PUBLISH_REPOSITORY:-local/unpublished}"

printf '%s  reject.mrs\n' "$mrs_sha256" > "$work_dir/reject.mrs.sha256"
cat > "$work_dir/reject.meta" <<EOF
schema_version=1
source_url=$SOURCE_URL
source_http_status=$source_http_status
source_sha256=$source_sha256
source_bytes=$source_bytes
source_rule_count=$source_rule_count
mrs_sha256=$mrs_sha256
mrs_bytes=$mrs_bytes
mihomo_version=$MIHOMO_VERSION
mihomo_asset=$MIHOMO_ASSET
mihomo_asset_sha256=$MIHOMO_ASSET_SHA256
mihomo_release_url=$MIHOMO_RELEASE_URL
mihomo_reported_version=$mihomo_reported_version
mihomo_mode=$mihomo_mode
generated_at_utc=$generated_at_utc
repository=$publish_repository
source_license=GPL-3.0
converter_license=GPL-3.0
EOF

# Copy only after every validation has succeeded. The release branch itself is
# updated later by one Git commit, so partial build output is never published.
cp -- "$work_dir/reject.mrs" "$output_dir/reject.mrs.new"
cp -- "$work_dir/reject.mrs.sha256" "$output_dir/reject.mrs.sha256.new"
cp -- "$work_dir/reject.meta" "$output_dir/reject.meta.new"
mv -f -- "$output_dir/reject.mrs.new" "$output_dir/reject.mrs"
mv -f -- "$output_dir/reject.mrs.sha256.new" "$output_dir/reject.mrs.sha256"
mv -f -- "$output_dir/reject.meta.new" "$output_dir/reject.meta"

echo "Build complete:"
cat "$output_dir/reject.meta"
