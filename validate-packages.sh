#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: ./validate-packages.sh [--advisory-namcap] [package-dir...]

Runs packaging validation for each package:
  - shellcheck on helper scripts
  - shellcheck on PKGBUILD (with Arch-specific excludes)
  - makepkg --printsrcinfo
  - makepkg -f --verifysource
  - makepkg -fs --check --noconfirm
  - namcap PKGBUILD *.pkg.tar.*

If package dirs are omitted, all top-level package dirs with a PKGBUILD are validated.
USAGE
  exit 1
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$cmd" >&2
    exit 2
  fi
}

strict_namcap=1
package_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    --advisory-namcap)
      strict_namcap=0
      ;;
    *)
      package_args+=("$1")
      ;;
  esac
  shift || true
done

require_cmd makepkg
require_cmd namcap
require_cmd shellcheck

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$script_dir"

package_dirs=()
if [[ ${#package_args[@]} -gt 0 ]]; then
  for pkg in "${package_args[@]}"; do
    if [[ ! -f "$pkg/PKGBUILD" ]]; then
      printf 'PKGBUILD missing in %s\n' "$pkg" >&2
      exit 1
    fi
    package_dirs+=("$pkg")
  done
else
  while IFS= read -r pkg; do
    package_dirs+=("$pkg")
  done < <(find . -mindepth 2 -maxdepth 2 -type f -name PKGBUILD -printf '%h\n' | sed 's|^\./||' | sort)
fi

helper_scripts=()
while IFS= read -r script; do
  helper_scripts+=("$script")
done < <(find . -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort)

if [[ ${#helper_scripts[@]} -gt 0 ]]; then
  echo '==> ShellCheck helper scripts'
  shellcheck --shell=bash "${helper_scripts[@]}"
fi

for pkg in "${package_dirs[@]}"; do
  echo "==> Validating ${pkg}"
  (
    cd "$pkg"
    mapfile -t pkg_files < <(makepkg --packagelist)
    if [[ ${#pkg_files[@]} -eq 0 ]]; then
      printf 'No package files produced by makepkg --packagelist in %s\n' "$pkg" >&2
      exit 1
    fi

    shellcheck --shell=bash --exclude=SC2034,SC2154,SC2164 PKGBUILD
    makepkg --printsrcinfo > .SRCINFO
    makepkg -f --verifysource
    makepkg -fs --check --noconfirm
    namcap_output="$(namcap PKGBUILD "${pkg_files[@]}")"
    printf '%s\n' "$namcap_output"
    if grep -q ' E: ' <<<"$namcap_output"; then
      if [[ "$strict_namcap" -eq 1 ]]; then
        printf 'namcap reported errors for %s\n' "$pkg" >&2
        exit 1
      fi
      printf 'namcap reported errors for %s (advisory mode)\n' "$pkg" >&2
    fi
  )
done

echo 'All validations passed.'
