#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cp "$script_dir/install-all.sh" "$tmp_dir/install-all.sh"
mkdir "$tmp_dir/bin" "$tmp_dir/demo"
touch "$tmp_dir/demo/PKGBUILD"

cat >"$tmp_dir/bin/makepkg" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --printsrcinfo ]]; then
  printf 'pkgname = demo\npkgver = 1\npkgrel = 1\n'
else
  if [[ "${wait_for_refresh:-0}" == 1 ]]; then
    for ((attempt = 0; attempt < 200; attempt++)); do
      [[ -e "$refresh_log" ]] && break
      /bin/sleep 0.01
    done
    [[ -e "$refresh_log" ]] || exit 1
  fi
  # makepkg's default sudo -k ignores the credentials kept alive by the installer.
  if [[ -n "${PACMAN_AUTH:-}" ]]; then
    "$PACMAN_AUTH" pacman -U demo.pkg.tar.zst || exit "$?"
  else
    sudo -k pacman -U demo.pkg.tar.zst || exit "$?"
  fi
  printf '%s\n' "$PWD" >>"$install_log"
  exit "${install_status:-0}"
fi
EOF
cat >"$tmp_dir/bin/pacman" <<'EOF'
#!/usr/bin/env bash
[[ -n "${installed_version:-}" ]] && printf 'demo %s\n' "$installed_version"
EOF
cat >"$tmp_dir/bin/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == -v ]]; then
  printf 'authenticate\n' >>"$auth_log"
  exit "${auth_status:-0}"
elif [[ "$*" == '-n -v' ]]; then
  printf 'refresh\n' >>"$refresh_log"
elif [[ "${1:-}" == -k ]]; then
  printf 'authenticate\n' >>"$auth_log"
elif [[ "${1:-}" == pacman ]]; then
  [[ -e "$auth_log" ]] || exit 1
else
  exit 1
fi
EOF
cat >"$tmp_dir/bin/sleep" <<'EOF'
#!/usr/bin/env bash
# Exercise timestamp renewal without making the test wait thirty seconds.
exec /bin/sleep 0.01
EOF
chmod +x "$tmp_dir/install-all.sh" "$tmp_dir/bin/"*

export PATH="$tmp_dir/bin:$PATH"
export install_log="$tmp_dir/installed"
export auth_log="$tmp_dir/authenticated"
export refresh_log="$tmp_dir/refreshed"

"$tmp_dir/install-all.sh" >/dev/null
[[ ! -e "$install_log" ]]

"$tmp_dir/install-all.sh" --install-missing >/dev/null
[[ -e "$install_log" ]]

mkdir "$tmp_dir/second"
touch "$tmp_dir/second/PKGBUILD"
rm -f "$install_log" "$auth_log" "$refresh_log"
wait_for_refresh=1 "$tmp_dir/install-all.sh" --install-missing >/dev/null
[[ "$(wc -l <"$auth_log")" -eq 1 ]]
[[ "$(wc -l <"$install_log")" -eq 2 ]]
[[ -e "$refresh_log" ]]

rm -f "$install_log"
if auth_status=1 "$tmp_dir/install-all.sh" --install-missing >/dev/null; then
  echo "Expected authentication failure" >&2
  exit 1
fi
[[ ! -e "$install_log" ]]

status=0
install_status=42 "$tmp_dir/install-all.sh" --install-missing >/dev/null || status=$?
[[ "$status" -eq 42 ]]

refreshes="$(wc -l <"$refresh_log")"
/bin/sleep 0.05
[[ "$(wc -l <"$refresh_log")" -eq "$refreshes" ]]

echo "install-all tests passed."
