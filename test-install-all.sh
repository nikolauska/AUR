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
  touch "$install_log"
fi
EOF
cat >"$tmp_dir/bin/pacman" <<'EOF'
#!/usr/bin/env bash
[[ -n "${installed_version:-}" ]] && printf 'demo %s\n' "$installed_version"
EOF
chmod +x "$tmp_dir/install-all.sh" "$tmp_dir/bin/makepkg" "$tmp_dir/bin/pacman"

export PATH="$tmp_dir/bin:$PATH"
export install_log="$tmp_dir/installed"

"$tmp_dir/install-all.sh" >/dev/null
[[ ! -e "$install_log" ]]

"$tmp_dir/install-all.sh" --install-missing >/dev/null
[[ -e "$install_log" ]]

echo "install-all tests passed."
