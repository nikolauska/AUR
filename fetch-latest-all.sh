#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
Usage: ./fetch-latest-all.sh [--dry-run] [--continue-on-error] [package-dir...]

Runs ./fetch-latest-release.sh for all top-level package dirs containing a
PKGBUILD (or for the specified package dirs).

Examples:
  ./fetch-latest-all.sh
  ./fetch-latest-all.sh --dry-run
  ./fetch-latest-all.sh package-dir
EOF
	exit 1
}

dry_run=0
continue_on_error=0
package_dirs=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help) usage ;;
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
[[ -f "$fetch_script" ]] || {
	echo "Missing $fetch_script" >&2
	exit 2
}
[[ -x "$fetch_script" ]] || {
	echo "Not executable: $fetch_script" >&2
	exit 2
}

if [[ ${#package_dirs[@]} -eq 0 ]]; then
	mapfile -t package_dirs < <(find . -mindepth 2 -maxdepth 2 -type f -name PKGBUILD -printf '%h\n' | sed 's|^\./||' | sort)
fi

for pkg_dir in "${package_dirs[@]}"; do
	[[ -f "$pkg_dir/PKGBUILD" ]] || {
		echo "PKGBUILD missing in $pkg_dir" >&2
		exit 1
	}
	[[ -f "$pkg_dir/fetch-latest.conf" ]] || {
		echo "Updater config missing in $pkg_dir" >&2
		exit 1
	}
	bash -n "$pkg_dir/fetch-latest.conf"
done

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
