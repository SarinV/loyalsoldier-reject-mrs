#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/scripts/versions.env"

python_bin="${PYTHON_BIN:-python3}"
output_dir="${1:-$repo_root/dist}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/loyalsoldier-mrs-build.XXXXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

read -r -a rulesets <<< "$RULESETS"
if (( ${#rulesets[@]} == 0 )); then
  echo "RULESETS is empty" >&2
  exit 1
fi

mkdir -p "$output_dir"

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

generated_at_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
publish_repository="${PUBLISH_REPOSITORY:-local/unpublished}"

for name in "${rulesets[@]}"; do
  if [[ ! "$name" =~ ^[a-z0-9-]+$ ]]; then
    echo "invalid ruleset name: $name" >&2
    exit 1
  fi

  upper_name="${name^^}"
  source_url_var="${upper_name}_SOURCE_URL"
  min_source_bytes_var="${upper_name}_MIN_SOURCE_BYTES"
  max_source_bytes_var="${upper_name}_MAX_SOURCE_BYTES"
  min_rules_var="${upper_name}_MIN_RULES"
  min_mrs_bytes_var="${upper_name}_MIN_MRS_BYTES"
  source_file_override_var="${upper_name}_SOURCE_FILE"

  source_url="${!source_url_var:-}"
  min_source_bytes="${!min_source_bytes_var:-}"
  max_source_bytes="${!max_source_bytes_var:-}"
  min_rules="${!min_rules_var:-}"
  min_mrs_bytes="${!min_mrs_bytes_var:-}"
  source_file_override="${!source_file_override_var:-}"

  if [[ -z "$source_url" || -z "$min_source_bytes" ||
        -z "$max_source_bytes" || -z "$min_rules" ||
        -z "$min_mrs_bytes" ]]; then
    echo "incomplete guard configuration for $name" >&2
    exit 1
  fi

  source_file="$work_dir/$name.txt"
  source_http_status="local"
  if [[ -n "$source_file_override" ]]; then
    cp -- "$source_file_override" "$source_file"
  elif [[ -n "${SOURCE_DIR:-}" ]]; then
    cp -- "$SOURCE_DIR/$name.txt" "$source_file"
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
        "$source_url"
    })"
    if [[ ! "$source_http_status" =~ ^2[0-9][0-9]$ ]]; then
      echo "$name: unexpected final HTTP status: $source_http_status" >&2
      exit 1
    fi
  fi

  "$python_bin" "$repo_root/scripts/validate_source.py" \
    --input "$source_file" \
    --min-bytes "$min_source_bytes" \
    --max-bytes "$max_source_bytes" \
    --min-rules "$min_rules" \
    --json-out "$work_dir/$name.source.json" \
    --canonical-out "$work_dir/$name.source-rules.txt"

  "$mihomo_bin" convert-ruleset domain yaml "$source_file" "$work_dir/$name.mrs"
  if [[ ! -s "$work_dir/$name.mrs" ]]; then
    echo "$name: MRS output is empty" >&2
    exit 1
  fi
  mrs_bytes="$(wc -c < "$work_dir/$name.mrs" | tr -d '[:space:]')"
  if (( mrs_bytes < min_mrs_bytes )); then
    echo "$name: MRS output is unexpectedly small: $mrs_bytes bytes" >&2
    exit 1
  fi

  # Exporting MRS back to text and comparing the complete normalized set catches
  # a non-empty but semantically incomplete or malformed artifact.
  "$mihomo_bin" convert-ruleset domain mrs "$work_dir/$name.mrs" "$work_dir/$name.roundtrip.txt"
  "$python_bin" "$repo_root/scripts/compare_rules.py" \
    --source "$work_dir/$name.source-rules.txt" \
    --roundtrip "$work_dir/$name.roundtrip.txt" \
    --json-out "$work_dir/$name.semantic.json"

  source_sha256="$($python_bin -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["sha256"])' "$work_dir/$name.source.json")"
  source_bytes="$($python_bin -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["bytes"])' "$work_dir/$name.source.json")"
  source_rule_count="$($python_bin -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["rule_count"])' "$work_dir/$name.source.json")"
  mrs_export_rule_count="$($python_bin -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["roundtrip_rule_count"])' "$work_dir/$name.semantic.json")"
  normalized_redundant_exact_rules="$($python_bin -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["normalized_redundant_exact_rules"])' "$work_dir/$name.semantic.json")"
  mrs_sha256="$(sha256sum "$work_dir/$name.mrs" | awk '{print $1}')"

  printf '%s  %s.mrs\n' "$mrs_sha256" "$name" > "$work_dir/$name.mrs.sha256"
  cat > "$work_dir/$name.meta" <<EOF
schema_version=1
provider_name=$name
behavior=domain
source_url=$source_url
source_http_status=$source_http_status
source_sha256=$source_sha256
source_bytes=$source_bytes
source_rule_count=$source_rule_count
normalized_redundant_exact_rules=$normalized_redundant_exact_rules
mrs_export_rule_count=$mrs_export_rule_count
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
done

# Publish to the requested output directory only after every provider has
# passed download, strict validation, conversion, and semantic round-trip.
for name in "${rulesets[@]}"; do
  for suffix in mrs mrs.sha256 meta; do
    cp -- "$work_dir/$name.$suffix" "$output_dir/$name.$suffix.new"
  done
done
for name in "${rulesets[@]}"; do
  for suffix in mrs mrs.sha256 meta; do
    mv -f -- "$output_dir/$name.$suffix.new" "$output_dir/$name.$suffix"
  done
done

echo "Build complete:"
for name in "${rulesets[@]}"; do
  echo "--- $name.meta ---"
  cat "$output_dir/$name.meta"
done
