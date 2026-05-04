#!/usr/bin/env bash
set -euo pipefail

# flutter_gemma 0.14.1 ships macOS Native Asset dylibs without enough Mach-O
# header padding for Flutter tester's long absolute install_name rewrite. Keep
# the tester build root short so install_name_tool can rewrite the dylib IDs
# without mutating the user's global Flutter config.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
short_build_dir="${FLUTTER_TEST_BUILD_DIR:-/tmp/gla_ft}"
config_dir="$repo_root/.dart_tool/flutter_test_config"
settings_file="$config_dir/settings"
flutter_bin="${FLUTTER_BIN:-flutter}"

mkdir -p "$config_dir" "$short_build_dir"
relative_build_dir="$(python3 - "$repo_root" "$short_build_dir" <<'PY'
import os
import sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
)"

cat > "$settings_file" <<JSON
{"build-dir":"$relative_build_dir"}
JSON

exec env XDG_CONFIG_HOME="$config_dir" "$flutter_bin" test --no-pub "$@"
