#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

install_missing=0
if (( $# )); then
  [[ "$1" == --install-missing && $# -eq 1 ]] || {
    printf 'Usage: %s [--install-missing]\n' "${0##*/}" >&2
    exit 2
  }
  install_missing=1
fi

for pkgbuild in "$script_dir"/*/PKGBUILD; do
  (
    cd "${pkgbuild%/*}"
    pkgname=
    pkgver=
    pkgrel=
    epoch=
    srcinfo="$(makepkg --printsrcinfo)"
    while read -r key _ value; do
      case "$key" in
        pkgname | pkgver | pkgrel | epoch) printf -v "$key" %s "$value" ;;
      esac
    done <<<"$srcinfo"

    expected_version="${epoch:+$epoch:}${pkgver}-${pkgrel}"
    installed_version="$(pacman -Q "$pkgname" 2>/dev/null | cut -d' ' -f2 || true)"

    if [[ -z "$installed_version" && "$install_missing" -eq 0 ]]; then
      printf 'Skipping %s %s (not installed)\n' "$pkgname" "$expected_version"
      exit
    fi

    if [[ "$installed_version" == "$expected_version" ]]; then
      printf 'Skipping %s %s (already installed)\n' "$pkgname" "$expected_version"
    else
      printf 'Installing %s %s (installed: %s)\n' \
        "$pkgname" "$expected_version" "${installed_version:-none}"
      makepkg -si
    fi
  )
done
