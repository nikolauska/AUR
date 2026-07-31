#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
Usage: ./fetch-latest-all.sh [--dry-run] [--continue-on-error] [package-dir...]

Runs ./fetch-latest-release.sh for all top-level package dirs containing a
PKGBUILD (or for the specified package dirs).
Independent package updates run in parallel, up to one worker per CPU.

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

require_cmd() {
	local cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		printf 'Missing required command: %s\n' "$cmd" >&2
		exit 2
	fi
}

require_cmd nproc

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

fetch_package() {
	local pkg_dir="$1"
	local fetch_args=()
	[[ "$dry_run" -eq 1 ]] && fetch_args+=(--dry-run)

	echo "=== ${pkg_dir} ==="
	if "$fetch_script" "$pkg_dir" "${fetch_args[@]}"; then
		echo
		return 0
	fi
	echo
	return 1
}

parallel_jobs="$(nproc)"
failed=0
package_count="${#package_dirs[@]}"
# Batches keep fail-fast mode from starting later packages while filling all workers.
for ((batch_start = 0; batch_start < package_count; batch_start += parallel_jobs)); do
	pids=()
	for ((batch_end = batch_start; batch_end < batch_start + parallel_jobs && batch_end < package_count; batch_end++)); do
		fetch_package "${package_dirs[batch_end]}" &
		pids+=("$!")
	done
	for pid in "${pids[@]}"; do
		if wait "$pid"; then
			:
		else
			failed=$((failed + 1))
		fi
	done
	if [[ "$failed" -ne 0 && "$continue_on_error" -eq 0 ]]; then
		exit 1
	fi
done

if [[ "$failed" -ne 0 ]]; then
	echo "Completed with failures: $failed" >&2
	exit 1
fi

echo "Done."
