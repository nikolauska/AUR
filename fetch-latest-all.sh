#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ./fetch-latest-all.sh [--dry-run] [--continue-on-error] [package-dir...]

Runs ./fetch-latest-release.sh for all packages in this repo (or for the
specified package dirs).

Examples:
  ./fetch-latest-all.sh
  ./fetch-latest-all.sh --dry-run
  ./fetch-latest-all.sh mcp-proxy-bin openai-codex-bin
EOF
  exit 1
}

dry_run=0
continue_on_error=0
package_dirs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --dry-run) dry_run=1 ;;
    --continue-on-error) continue_on_error=1 ;;
    *)
      package_dirs+=("$1")
      ;;
  esac
  shift || true
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$script_dir"

fetch_script="./fetch-latest-release.sh"
[[ -f "$fetch_script" ]] || { echo "Missing $fetch_script" >&2; exit 2; }
[[ -x "$fetch_script" ]] || { echo "Not executable: $fetch_script" >&2; exit 2; }

if [[ ${#package_dirs[@]} -eq 0 ]]; then
  package_dirs=(
    mcp-proxy-bin
    openai-codex-bin
    tidewave-app
    tidewave-cli
    typescript-go
  )
fi

args=()
[[ "$dry_run" -eq 1 ]] && args+=(--dry-run)

failed=0
for pkg_dir in "${package_dirs[@]}"; do
  echo "=== ${pkg_dir} ==="
  if "$fetch_script" "$pkg_dir" "${args[@]}"; then
    :
  else
    failed=$((failed + 1))
    if [[ "$continue_on_error" -eq 0 ]]; then
      exit 1
    fi
  fi
  echo
done

if [[ "$failed" -ne 0 ]]; then
  echo "Completed with failures: $failed" >&2
  exit 1
fi

echo "Done."
