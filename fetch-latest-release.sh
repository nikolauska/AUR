#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
Usage: ./fetch-latest-release.sh <package-dir> [--dry-run]

Fetches the latest upstream release for a supported package, downloads the
matching asset into the package directory, updates PKGBUILD (pkgver, pkgrel,
checksums), and refreshes .SRCINFO.

Supported package dirs:
  acolyte-agent-bin
  chrome-devtools-axi-bin
  dexter-bin
  gnhf-bin
  gh-axi-bin
  lavish-axi-bin
  mcp-proxy-bin
  no-mistakes-bin
  stripe-mock-bin
  treehouse-bin
  tidewave-app-bin
  tidewave-cli-bin
  typescript-go
  github-copilot-cli
  pi-agent-bin
  skills-bin

Environment:
  GITHUB_TOKEN (optional) to raise GitHub API rate limits.
EOF
	exit 1
}

[[ $# -lt 1 ]] && usage

dry_run=0
pkg_dir="$1"
shift || true

while [[ $# -gt 0 ]]; do
	case "$1" in
	--dry-run) dry_run=1 ;;
	*) usage ;;
	esac
	shift || true
done

[[ -d "$pkg_dir" ]] || {
	echo "Package dir not found: $pkg_dir" >&2
	exit 1
}
[[ -f "$pkg_dir/PKGBUILD" ]] || {
	echo "PKGBUILD missing in $pkg_dir" >&2
	exit 1
}

resolve_dest_name_from_pkgbuild() {
	local pkgbuild_path="$1"
	local asset_basename="$2"
	local pkgver="$3"
	local pkgrel="$4"
	local carch="${CARCH:-x86_64}"

	local token=""
	local candidate=""
	while IFS= read -r candidate; do
		local resolved="$candidate"
		resolved="${resolved//\$\{pkgver\}/$pkgver}"
		resolved="${resolved//\$pkgver/$pkgver}"
		resolved="${resolved//\$\{pkgrel\}/$pkgrel}"
		resolved="${resolved//\$pkgrel/$pkgrel}"
		resolved="${resolved//\$\{CARCH\}/$carch}"
		resolved="${resolved//\$CARCH/$carch}"
		if [[ "$resolved" == *"$asset_basename"* ]]; then
			token="$resolved"
			break
		fi
	done < <(
		awk '
      {
        line = $0
        while (match(line, /"[^"]+"/)) {
          token = substr(line, RSTART + 1, RLENGTH - 2)
          print token
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$pkgbuild_path" 2>/dev/null || true
	)

	local dest_name=""
	if [[ -n "$token" && "$token" == *"::"* ]]; then
		dest_name="${token%%::*}"
	else
		dest_name="$asset_basename"
	fi

	dest_name="${dest_name//\$\{pkgver\}/$pkgver}"
	dest_name="${dest_name//\$pkgver/$pkgver}"
	dest_name="${dest_name//\$\{pkgrel\}/$pkgrel}"
	dest_name="${dest_name//\$pkgrel/$pkgrel}"
	dest_name="${dest_name//\$\{CARCH\}/$carch}"
	dest_name="${dest_name//\$CARCH/$carch}"
	dest_name="$(printf '%s' "$dest_name" | sed -E 's/\$\{[[:alpha:]_][[:alnum:]_]*\}//g; s/\$[[:alpha:]_][[:alnum:]_]*//g')"

	printf '%s' "$dest_name"
}

pkg_type=""
repo=""
asset_regex=""
strip_prefix=""
npm_pkg=""
npm_tag="latest"

case "$(basename "$pkg_dir")" in
acolyte-agent-bin)
	pkg_type="github"
	repo="cniska/acolyte"
	asset_regex='acolyte-linux-x64\.tar\.gz'
	strip_prefix="v"
	;;
dexter-bin)
	pkg_type="github"
	repo="remoteoss/dexter"
	asset_regex='dexter_Linux_x86_64\.tar\.gz'
	strip_prefix="v"
	;;
mcp-proxy-bin)
	pkg_type="github"
	repo="tidewave-ai/mcp_proxy_rust"
	asset_regex='mcp-proxy-x86_64-unknown-linux-gnu\.tar\.gz'
	strip_prefix="v"
	;;
no-mistakes-bin)
	pkg_type="github"
	repo="kunchenguid/no-mistakes"
	asset_regex='^no-mistakes-v[0-9.]+-linux-amd64\.tar\.gz$'
	strip_prefix="v"
	;;
stripe-mock-bin)
	pkg_type="github"
	repo="stripe/stripe-mock"
	asset_regex='^stripe-mock_[0-9.]+_linux_amd64\.tar\.gz$'
	strip_prefix="v"
	;;
treehouse-bin)
	pkg_type="github"
	repo="kunchenguid/treehouse"
	asset_regex='^treehouse-v[0-9.]+-linux-amd64\.tar\.gz$'
	strip_prefix="v"
	;;
tidewave-cli-bin)
	pkg_type="github"
	repo="tidewave-ai/tidewave_app"
	asset_regex='tidewave-cli-x86_64-unknown-linux-gnu$'
	strip_prefix="v"
	;;
tidewave-app-bin)
	pkg_type="github"
	repo="tidewave-ai/tidewave_app"
	asset_regex='tidewave-app-amd64\.AppImage$'
	strip_prefix="v"
	;;
typescript-go)
	pkg_type="npm"
	npm_pkg="@typescript/native-preview"
	npm_tag="beta"
	;;
github-copilot-cli)
	pkg_type="npm"
	npm_pkg="@github/copilot"
	;;
chrome-devtools-axi-bin | gh-axi-bin | lavish-axi-bin | skills-bin)
	pkg_type="npm"
	npm_pkg="$(basename "$pkg_dir" -bin)"
	;;
gnhf-bin)
	pkg_type="npm"
	npm_pkg="gnhf"
	;;
pi-agent-bin)
	pkg_type="github"
	repo="earendil-works/pi"
	asset_regex='^pi-linux-x64\.tar\.gz$'
	strip_prefix="v"
	;;
*)
	echo "Unsupported package: $(basename "$pkg_dir")" >&2
	usage
	;;
esac

if [[ "$pkg_type" == "github" ]]; then
	api_url="https://api.github.com/repos/${repo}/releases/latest"
	auth_header=()
	[[ -n "${GITHUB_TOKEN:-}" ]] && auth_header=(-H "Authorization: token ${GITHUB_TOKEN}")

	current_pkgver="$(awk -F= '/^pkgver=/{print $2; exit}' "$pkg_dir/PKGBUILD")"
	current_pkgrel="$(awk -F= '/^pkgrel=/{print $2; exit}' "$pkg_dir/PKGBUILD")"
	[[ -n "$current_pkgrel" ]] || current_pkgrel="1"

	echo "Querying latest release for ${repo}…"
	release_json="$(curl -sfL "${auth_header[@]}" "$api_url")"

	tag_name="$(jq -r '.tag_name' <<<"$release_json")"
	[[ "$tag_name" != "null" ]] || {
		echo "Could not read tag_name from release JSON" >&2
		exit 1
	}

	asset_url="$(jq -r --arg re "$asset_regex" '.assets[] | select(.name|test($re)) | .browser_download_url' <<<"$release_json" | head -n1)"
	[[ -n "$asset_url" ]] || {
		echo "No asset matching /$asset_regex/ found in latest release" >&2
		exit 1
	}

	pkgver="${tag_name#"$strip_prefix"}"
	if [[ "$pkgver" == "$current_pkgver" ]]; then
		pkgrel="$current_pkgrel"
	else
		pkgrel="1"
	fi
	asset_name="$(basename "$asset_url")"
	dest_name="$(resolve_dest_name_from_pkgbuild "$pkg_dir/PKGBUILD" "$asset_name" "$pkgver" "$pkgrel")"

	echo "Latest tag: $tag_name -> pkgver=${pkgver} (current ${current_pkgver}-${current_pkgrel})"
	echo "Asset: $asset_name"
	echo "Download as: $dest_name"

	if [[ "$dry_run" -eq 1 ]]; then
		echo "[dry-run] Would download to ${pkg_dir}/${dest_name}"
		exit 0
	fi

	cd "$pkg_dir"

	echo "Downloading asset…"
	curl -fL "$asset_url" -o "$dest_name"

	echo "Updating PKGBUILD (pkgver=${pkgver}, pkgrel=${pkgrel})…"
	sed -i -E "s/^pkgver=.*/pkgver=${pkgver}/" PKGBUILD
	sed -i -E "s/^pkgrel=.*/pkgrel=${pkgrel}/" PKGBUILD

	echo "Regenerating checksums…"
	updpkgsums

else # npm package
	echo "Querying npm registry for ${npm_pkg}@${npm_tag}…"
	npm_json="$(NPM_CONFIG_CACHE=${NPM_CONFIG_CACHE:-$pkg_dir/.npm-cache} npm view "${npm_pkg}@${npm_tag}" version dist.tarball dist.integrity --json)"

	version="$(jq -r 'if type=="array" then (.[-1].version // .[-1]) else (.version // .) end' <<<"$npm_json")"
	tarball="$(jq -r 'if type=="array" then (.[-1]["dist.tarball"]) else (."dist.tarball") end' <<<"$npm_json")"
	integrity="$(jq -r 'if type=="array" then (.[-1]["dist.integrity"]) else (."dist.integrity") end' <<<"$npm_json")"

	[[ -n "$version" && "$version" != "null" ]] || {
		echo "Failed to read version from npm" >&2
		exit 1
	}
	[[ -n "$tarball" && "$tarball" != "null" ]] || {
		echo "Failed to read tarball URL from npm" >&2
		exit 1
	}
	[[ -n "$integrity" && "$integrity" != "null" ]] || {
		echo "Failed to read integrity from npm" >&2
		exit 1
	}
	[[ "$integrity" == sha512-* ]] || {
		echo "Unsupported npm integrity format: $integrity" >&2
		exit 1
	}
	sha512sum="$(printf '%s' "${integrity#sha512-}" | base64 -d | od -An -v -tx1 | tr -d ' \n')"

	if [[ "$version" =~ ^7\.0\.0-dev\.([0-9]+)\.([0-9]+)$ ]]; then
		pkgver="${BASH_REMATCH[1]}"
		pkgrel="${BASH_REMATCH[2]}"
	else
		# Fallback: use full version as pkgver, reset pkgrel to 1
		pkgver="$version"
		pkgrel="1"
	fi

	asset_name="$(basename "$tarball")"

	echo "NPM ${npm_tag} version: ${version} -> pkgver=${pkgver}, pkgrel=${pkgrel}"
	echo "Tarball: ${asset_name}"
	echo "sha512: ${sha512sum}"

	if [[ "$dry_run" -eq 1 ]]; then
		echo "[dry-run] Would download to ${pkg_dir}/${asset_name}"
		exit 0
	fi

	cd "$pkg_dir"

	echo "Downloading tarball…"
	curl -fL "$tarball" -o "$asset_name"

	echo "Updating PKGBUILD (pkgver=${pkgver}, pkgrel=${pkgrel})…"
	sed -i -E "s/^pkgver=.*/pkgver=${pkgver}/" PKGBUILD
	sed -i -E "s/^pkgrel=.*/pkgrel=${pkgrel}/" PKGBUILD
	sed -i -E "s|^sha[0-9]+sums=\\('.*'\\)|sha512sums=('${sha512sum}')|" PKGBUILD
fi

echo "Refreshing .SRCINFO…"
makepkg --printsrcinfo >.SRCINFO

echo "Done."
