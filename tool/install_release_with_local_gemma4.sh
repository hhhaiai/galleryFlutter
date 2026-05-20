#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

flutter_bin="${FLUTTER_BIN:-flutter}"
adb_bin="${ADB_BIN:-adb}"
model_dir="${GEMMA4_MODEL_DIR:-$repo_root/local_models/Gemma_4_E2B_it/20260325}"
source_model="${GEMMA4_MODEL_FILE:-$model_dir/gemma-4-E2B-it.litertlm}"
expected_size="${GEMMA4_MODEL_SIZE:-2538766336}"
expected_name="gemma-4-E2B-it.litertlm"
android_name="gemma-4-e2b-it.litertlm"
normalized_name="Gemma_4_E2B_it"
model_version="7fa1d78473894f7e736a21d920c3aa80f950c0db"
android_package="com.example.gemma_local_app"
ios_bundle="com.example.gemmaLocalApp"
android_apk="build/app/outputs/flutter-apk/app-release.apk"
ios_app="build/ios/iphoneos/Runner.app"

if [[ ! -f "$source_model" ]]; then
  echo "Repo-local Gemma 4 model not found; preparing it from the canonical local source..."
  "$repo_root/tool/prepare_local_gemma4_model.sh"
fi
if [[ ! -f "$source_model" ]]; then
  echo "Local Gemma 4 model not found: $source_model" >&2
  exit 1
fi
actual_size="$(stat -f '%z' "$source_model" 2>/dev/null || stat -c '%s' "$source_model")"
if [[ "$actual_size" != "$expected_size" ]]; then
  echo "Local Gemma 4 model size mismatch: $actual_size != $expected_size ($source_model)" >&2
  exit 1
fi

if [[ "${BUILD_RELEASE:-1}" != "0" ]]; then
  "$flutter_bin" build apk --release
  "$flutter_bin" build ios --release
fi

if [[ "${INSTALL_ANDROID:-1}" != "0" ]]; then
  android_device="${ANDROID_DEVICE:-}"
  if [[ -z "$android_device" ]]; then
    android_device="$($adb_bin devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  fi
  if [[ -n "$android_device" ]]; then
    echo "Installing Android release on $android_device"
    "$adb_bin" -s "$android_device" install -r -d "$android_apk"
    android_dir="/sdcard/Android/data/$android_package/files"
    android_dest="$android_dir/$android_name"
    "$adb_bin" -s "$android_device" shell "mkdir -p '$android_dir'"
    echo "Preseeding Android model: $android_dest"
    "$adb_bin" -s "$android_device" push "$source_model" "$android_dest"
    android_size="$($adb_bin -s "$android_device" shell "stat -c %s '$android_dest'" | tr -d '\r[:space:]')"
    if [[ "$android_size" != "$expected_size" ]]; then
      echo "Android model size mismatch after push: $android_size != $expected_size" >&2
      exit 1
    fi
    "$adb_bin" -s "$android_device" shell monkey -p "$android_package" -c android.intent.category.LAUNCHER 1 >/dev/null
    echo "Android installed, model preseeded, and app launched. pid=$($adb_bin -s "$android_device" shell pidof "$android_package" | tr -d '\r')"
  else
    echo "No connected Android device; skipped Android install." >&2
  fi
fi

if [[ "${INSTALL_IOS:-1}" != "0" ]]; then
  ios_device="${IOS_DEVICE:-}"
  if [[ -z "$ios_device" ]]; then
    ios_device="$(xcrun devicectl list devices 2>/dev/null | awk '/available/ && /iPhone/ {print $3; exit}')"
  fi
  if [[ -n "$ios_device" ]]; then
    echo "Installing iOS release on $ios_device"
    xcrun devicectl device install app --device "$ios_device" "$ios_app"
    staging="build/local_model_preseed"
    final_dir="$staging/$normalized_name/$model_version"
    rm -rf "$staging"
    mkdir -p "$final_dir"
    if ! /bin/cp -c "$source_model" "$final_dir/$expected_name" 2>/dev/null; then
      cp -p "$source_model" "$final_dir/$expected_name"
    fi
    chmod 0644 "$final_dir/$expected_name"
    echo "Preseeding iOS model under Library/Application Support/$normalized_name/$model_version"
    copy_ok=0
    for attempt in 1 2; do
      if xcrun devicectl device copy to \
        --device "$ios_device" \
        --source "$staging/$normalized_name" \
        --destination "Library/Application Support/$normalized_name" \
        --domain-type appDataContainer \
        --domain-identifier "$ios_bundle" \
        --remove-existing-content false \
        --timeout 900; then
        copy_ok=1
        break
      fi
      echo "iOS model copy attempt $attempt failed; retrying after a short pause..." >&2
      sleep 5
    done
    if [[ "$copy_ok" != "1" ]]; then
      echo "iOS model copy did not complete cleanly; launching once to let the app recover any already copied candidate." >&2
    fi
    # Launch before verification: IOSModelDownloadManager.refreshStatus can
    # migrate a complete model found elsewhere under Application Support into
    # the canonical Gemma_4_E2B_it/<commit>/ path.
    xcrun devicectl device process launch --device "$ios_device" "$ios_bundle"
    sleep 3
    ios_listing="$(xcrun devicectl device info files --device "$ios_device" --domain-type appDataContainer --domain-identifier "$ios_bundle" --subdirectory "Library/Application Support/$normalized_name/$model_version" --recurse 2>/dev/null || true)"
    echo "$ios_listing" | grep -F "$expected_name" >/dev/null || {
      echo "iOS model file not visible after copy/recovery." >&2
      echo "$ios_listing" >&2
      exit 1
    }
    echo "iOS installed, model preseeded, and app launched."
  else
    echo "No available iOS device; skipped iOS install." >&2
  fi
fi
