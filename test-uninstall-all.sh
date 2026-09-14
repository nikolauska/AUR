#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

new_fixture() {
  fixture="$tmp_dir/$1"
  mkdir -p "$fixture/bin" "$fixture/alpha-dir" "$fixture/split-dir" "$fixture/zeta-dir" \
    "$fixture/ignored/nested"
  cp "$script_dir/uninstall-all.sh" "$fixture/uninstall-all.sh"
  touch "$fixture/alpha-dir/PKGBUILD" "$fixture/split-dir/PKGBUILD" \
    "$fixture/zeta-dir/PKGBUILD" "$fixture/ignored/nested/PKGBUILD"

  cat >"$fixture/bin/makepkg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == --printsrcinfo ]] || exit 2
printf '%s\n' "${PWD##*/}" >>"$makepkg_log"
case "${PWD##*/}" in
  alpha-dir)
    printf 'pkgbase = alpha-base\npkgname = alpha\npkgname = common\n'
    ;;
  split-dir)
    printf 'pkgbase = split-base\npkgname = split-one\npkgname = common\npkgname = split-two\n'
    ;;
  zeta-dir)
    [[ "${metadata_failure:-0}" == 0 ]] || exit 23
    printf 'pkgbase = zeta-base\npkgname = zeta\n'
    ;;
  *)
    exit 99
    ;;
esac
EOF

  cat >"$fixture/bin/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == -Qq ]]; then
  [[ $# -eq 1 ]] || exit 98
  printf 'Qq\n' >>"$pacman_log"
  [[ "${query_status:-0}" == 0 ]] || exit "$query_status"
  printf '%s\n' "${installed_packages//,/$'\n'}"
  exit 0
fi
printf 'REMOVE' >>"$pacman_log"
printf '|%s' "$@" >>"$pacman_log"
printf '\n' >>"$pacman_log"
exit "${removal_status:-0}"
EOF

  cat >"$fixture/bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s' "${1:-}" >>"$sudo_log"
if (( $# > 1 )); then printf '|%s' "${@:2}"; fi >>"$sudo_log"
printf '\n' >>"$sudo_log"
if [[ "${1:-}" == -v ]]; then
  [[ $# -eq 1 ]] || exit 97
  exit 0
fi
[[ "${1:-}" == pacman ]] || exit 96
shift
exec pacman "$@"
EOF
  chmod +x "$fixture/uninstall-all.sh" "$fixture/bin/"*

  makepkg_log="$fixture/makepkg.log"
  pacman_log="$fixture/pacman.log"
  sudo_log="$fixture/sudo.log"
  output_log="$fixture/output.log"
  export makepkg_log pacman_log sudo_log
}

new_fixture installed
PATH="$fixture/bin:$PATH" installed_packages='alpha,common,split-two' \
  "$fixture/uninstall-all.sh" >"$output_log"

expected_makepkg=$'alpha-dir\nsplit-dir\nzeta-dir'
[[ "$(<"$makepkg_log")" == "$expected_makepkg" ]] || fail 'package directories were not discovered in deterministic immediate-child order'
expected_sudo=$'-v\npacman|-Rns|--|alpha|common|split-two'
[[ "$(<"$sudo_log")" == "$expected_sudo" ]] || fail 'packages were not removed once, in order, without duplicates'
expected_pacman=$'Qq\nREMOVE|-Rns|--|alpha|common|split-two'
[[ "$(<"$pacman_log")" == "$expected_pacman" ]] || fail 'installed packages were not queried once or removal was incorrect'
output="$(<"$output_log")"
[[ "$output" == *'Skipping split-one (not installed)'* ]] || fail 'split package skip was not printed'
[[ "$output" == *'Skipping zeta (not installed)'* ]] || fail 'uninstalled package skip was not printed'

new_fixture none
PATH="$fixture/bin:$PATH" installed_packages='' "$fixture/uninstall-all.sh" >"$output_log"
[[ ! -e "$sudo_log" ]] || fail 'sudo was invoked when no packages were installed'
[[ "$(<"$pacman_log")" != *REMOVE* ]] || fail 'removal was invoked when no packages were installed'
[[ "$(<"$output_log")" == *'No matching installed packages found.'* ]] || fail 'zero-installed no-op was not reported'

new_fixture query-failure
status=0
PATH="$fixture/bin:$PATH" query_status=41 installed_packages=alpha \
  "$fixture/uninstall-all.sh" >"$output_log" 2>/dev/null || status=$?
[[ "$status" -eq 41 ]] || fail "package query failure returned $status instead of 41"
[[ "$(<"$pacman_log")" == Qq ]] || fail 'failed installed-package query was not called exactly once'
[[ ! -e "$sudo_log" ]] || fail 'sudo was invoked after installed-package query failure'
[[ "$(<"$pacman_log")" != *REMOVE* ]] || fail 'removal was invoked after installed-package query failure'

new_fixture metadata-failure
status=0
PATH="$fixture/bin:$PATH" metadata_failure=1 installed_packages=alpha \
  "$fixture/uninstall-all.sh" >"$output_log" 2>/dev/null || status=$?
[[ "$status" -eq 23 ]] || fail "metadata failure returned $status instead of 23"
[[ ! -e "$sudo_log" ]] || fail 'sudo was invoked after metadata failure'

new_fixture removal-failure
status=0
PATH="$fixture/bin:$PATH" installed_packages=alpha removal_status=47 \
  "$fixture/uninstall-all.sh" >"$output_log" || status=$?
[[ "$status" -eq 47 ]] || fail "removal failure returned $status instead of 47"
expected_sudo=$'-v\npacman|-Rns|--|alpha'
[[ "$(<"$sudo_log")" == "$expected_sudo" ]] || fail 'removal failure did not come from the single expected transaction'

printf 'uninstall-all tests passed.\n'
