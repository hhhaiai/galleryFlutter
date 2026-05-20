#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${GEMMA4_SOURCE_DIR:-/Users/sanbo/Desktop/models/gemma/Gemma_4_E2B_it/20260325}"
source_file="${GEMMA4_SOURCE_FILE:-$source_dir/gemma4_2b_v09_obfus_fix_all_modalities_thinking.litertlm}"
local_file="${GEMMA4_REPO_MODEL_FILE:-$repo_root/local_models/Gemma_4_E2B_it/20260325/gemma-4-E2B-it.litertlm}"
expected_size="${GEMMA4_MODEL_SIZE:-2538766336}"

size_of() {
  stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"
}

if [[ ! -f "$source_file" ]]; then
  echo "Source Gemma 4 model not found: $source_file" >&2
  exit 1
fi
source_size="$(size_of "$source_file")"
if [[ "$source_size" != "$expected_size" ]]; then
  echo "Source Gemma 4 model size mismatch: $source_size != $expected_size ($source_file)" >&2
  exit 1
fi

mkdir -p "$(dirname "$local_file")"
if [[ -f "$local_file" ]]; then
  local_size="$(size_of "$local_file")"
  if [[ "$local_size" == "$expected_size" ]]; then
    echo "Repo-local Gemma 4 model already ready: $local_file ($local_size bytes)"
    exit 0
  fi
  echo "Replacing incomplete repo-local model: $local_file ($local_size bytes)" >&2
  rm -f "$local_file"
fi

# APFS clonefile keeps this fast and space-efficient on macOS; fallback to cp.
if ! /bin/cp -c "$source_file" "$local_file" 2>/dev/null; then
  cp -p "$source_file" "$local_file"
fi
chmod 0644 "$local_file"
local_size="$(size_of "$local_file")"
if [[ "$local_size" != "$expected_size" ]]; then
  echo "Repo-local Gemma 4 model size mismatch after copy: $local_size != $expected_size" >&2
  exit 1
fi

echo "Repo-local Gemma 4 model ready: $local_file ($local_size bytes)"
