#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

shopt -s nullglob
pkgbuilds=("$script_dir"/*/PKGBUILD)

pkg_names=()
declare -A seen_pkg_names=()

for pkgbuild in "${pkgbuilds[@]}"; do
  srcinfo="$({ cd -- "${pkgbuild%/*}" && makepkg --printsrcinfo; })"
  while read -r key equals pkg_name; do
    if [[ "$key" == pkgname && "$equals" == = && -n "$pkg_name" && ! -v "seen_pkg_names[$pkg_name]" ]]; then
      seen_pkg_names["$pkg_name"]=1
      pkg_names+=("$pkg_name")
    fi
  done <<<"$srcinfo"
done

installed_pkg_names_output="$(pacman -Qq)"
declare -A installed_pkg_name_set=()
while IFS= read -r installed_pkg_name; do
  [[ -n "$installed_pkg_name" ]] && installed_pkg_name_set["$installed_pkg_name"]=1
done <<<"$installed_pkg_names_output"

installed_pkg_names=()
for pkg_name in "${pkg_names[@]}"; do
  if [[ -v "installed_pkg_name_set[$pkg_name]" ]]; then
    installed_pkg_names+=("$pkg_name")
  else
    printf 'Skipping %s (not installed)\n' "$pkg_name"
  fi
done

if (( ${#installed_pkg_names[@]} == 0 )); then
  printf 'No matching installed packages found.\n'
  exit 0
fi

sudo -v
exec sudo pacman -Rns -- "${installed_pkg_names[@]}"
