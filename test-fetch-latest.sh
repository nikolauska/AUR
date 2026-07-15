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
printf '%s\n' "$1" >>"$CALLS_FILE"
EOF
chmod +x "$tmp_dir/fetch-latest-release.sh"

for pkg_dir in a b; do
	mkdir "$tmp_dir/$pkg_dir"
	touch "$tmp_dir/$pkg_dir/PKGBUILD" "$tmp_dir/$pkg_dir/fetch-latest.conf"
done

calls_file="$tmp_dir/calls"
CALLS_FILE="$calls_file" "$tmp_dir/fetch-latest-all.sh" >/dev/null
diff -u <(printf 'a\nb\n') "$calls_file"

: >"$calls_file"
CALLS_FILE="$calls_file" "$tmp_dir/fetch-latest-all.sh" b a >/dev/null
diff -u <(printf 'b\na\n') "$calls_file"

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

echo "fetch-latest tests passed."
