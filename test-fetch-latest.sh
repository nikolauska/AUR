#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

while IFS= read -r pkg_dir; do
	[[ -f "$pkg_dir/fetch-latest.conf" ]]
	bash -n "$pkg_dir/fetch-latest.conf"
done < <(find "$script_dir" -mindepth 2 -maxdepth 2 -type f -name PKGBUILD -printf '%h\n' | sort)

cp "$script_dir/fetch-latest-all.sh" "$tmp_dir/fetch-latest-all.sh"
cat >"$tmp_dir/fetch-latest-release.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC2153
printf '%s\n' "$1" >>"$CALLS_FILE"
if [[ -n "${ACTIVE_DIR:-}" ]]; then
	if mkdir "$ACTIVE_DIR/marker" 2>/dev/null; then
		trap 'rmdir "$ACTIVE_DIR/marker"' EXIT
	else
# shellcheck disable=SC2153
		: >"$PARALLEL_FILE"
	fi
	sleep 0.2
fi
EOF
chmod +x "$tmp_dir/fetch-latest-release.sh"

mkdir "$tmp_dir/bin" "$tmp_dir/active"
cat >"$tmp_dir/bin/nproc" <<'EOF'
#!/usr/bin/env bash
printf '2\n'
EOF
chmod +x "$tmp_dir/bin/nproc"

for pkg_dir in a b; do
	mkdir "$tmp_dir/$pkg_dir"
	touch "$tmp_dir/$pkg_dir/PKGBUILD" "$tmp_dir/$pkg_dir/fetch-latest.conf"
done

calls_file="$tmp_dir/calls"
parallel_file="$tmp_dir/parallel"
PATH="$tmp_dir/bin:$PATH" CALLS_FILE="$calls_file" ACTIVE_DIR="$tmp_dir/active" PARALLEL_FILE="$parallel_file" "$tmp_dir/fetch-latest-all.sh" >/dev/null
[[ -f "$parallel_file" ]]
diff -u <(printf 'a\nb\n') <(sort "$calls_file")

: >"$calls_file"
CALLS_FILE="$calls_file" "$tmp_dir/fetch-latest-all.sh" b a >/dev/null
diff -u <(printf 'a\nb\n') <(sort "$calls_file")

rm "$tmp_dir/b/fetch-latest.conf"
: >"$calls_file"
if CALLS_FILE="$calls_file" "$tmp_dir/fetch-latest-all.sh" >/dev/null 2>&1; then
	echo "fetch-latest-all accepted a package without config" >&2
	exit 1
fi
[[ ! -s "$calls_file" ]]

cp "$script_dir/fetch-latest-release.sh" "$tmp_dir/release.sh"
mkdir "$tmp_dir/manual" "$tmp_dir/invalid" "$tmp_dir/missing"
touch "$tmp_dir/manual/PKGBUILD" "$tmp_dir/invalid/PKGBUILD" "$tmp_dir/missing/PKGBUILD"
printf 'pkg_type=manual\n' >"$tmp_dir/manual/fetch-latest.conf"
printf 'pkg_type=unknown\n' >"$tmp_dir/invalid/fetch-latest.conf"
printf 'pkg_type=github\n' >"$tmp_dir/missing/fetch-latest.conf"
"$tmp_dir/release.sh" "$tmp_dir/manual" >/dev/null
if "$tmp_dir/release.sh" "$tmp_dir/invalid" >/dev/null 2>&1; then
	echo "fetch-latest-release accepted an unknown package type" >&2
	exit 1
fi
if "$tmp_dir/release.sh" "$tmp_dir/missing" >/dev/null 2>&1; then
	echo "fetch-latest-release accepted incomplete GitHub config" >&2
	exit 1
fi

mkdir "$tmp_dir/stable" "$tmp_dir/prerelease" "$tmp_dir/bad-prerelease"
for pkg_dir in stable prerelease bad-prerelease; do
	cat >"$tmp_dir/$pkg_dir/PKGBUILD" <<'EOF'
pkgver=0
pkgrel=1
EOF
done
cat >"$tmp_dir/stable/fetch-latest.conf" <<'EOF'
pkg_type=github
repo=example/tool
asset_regex='linux-amd64\.tar\.gz$'
strip_prefix=v
EOF
cat >"$tmp_dir/prerelease/fetch-latest.conf" <<'EOF'
pkg_type=github
repo=example/tool
asset_regex='linux-amd64\.tar\.gz$'
strip_prefix=v
allow_prerelease=true
EOF
cat >"$tmp_dir/bad-prerelease/fetch-latest.conf" <<'EOF'
pkg_type=github
repo=example/tool
asset_regex='linux-amd64\.tar\.gz$'
allow_prerelease=yes
EOF
cat >"$tmp_dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${*: -1}"
case "$url" in
*/releases/latest)
	printf '%s\n' '{"tag_name":"v1.0.0","assets":[{"name":"tool-linux-amd64.tar.gz","browser_download_url":"https://example.test/tool-linux-amd64.tar.gz"}]}'
	;;
*/releases?per_page=100)
	printf '%s\n' '[{"tag_name":"v2.0.0-rc.1","draft":false,"prerelease":true,"assets":[{"name":"tool-linux-amd64.tar.gz","browser_download_url":"https://example.test/tool-linux-amd64.tar.gz"}]}]'
	;;
*)
	echo "Unexpected URL: $url" >&2
	exit 1
	;;
esac
EOF
chmod +x "$tmp_dir/bin/curl"

stable_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/release.sh" "$tmp_dir/stable" --dry-run)"
[[ "$stable_output" == *"Latest tag: v1.0.0 -> pkgver=1.0.0"* ]]
prerelease_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/release.sh" "$tmp_dir/prerelease" --dry-run)"
[[ "$prerelease_output" == *"Latest tag: v2.0.0-rc.1 -> pkgver=2.0.0-rc.1"* ]]
if PATH="$tmp_dir/bin:$PATH" "$tmp_dir/release.sh" "$tmp_dir/bad-prerelease" --dry-run >/dev/null 2>&1; then
	echo "fetch-latest-release accepted an invalid allow_prerelease value" >&2
	exit 1
fi

echo "fetch-latest tests passed."
