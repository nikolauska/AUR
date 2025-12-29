#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ./fetch-latest-release.sh <package-dir> [--dry-run]

Fetches the latest upstream release for a supported package, downloads the
matching asset into the package directory, updates PKGBUILD (pkgver, pkgrel,
checksums), and refreshes .SRCINFO.

Supported package dirs:
  mcp-proxy-bin
  openai-codex-bin
  tidewave-app
  tidewave-cli
  typescript-go
  github-copilot-cli

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

[[ -d "$pkg_dir" ]] || { echo "Package dir not found: $pkg_dir" >&2; exit 1; }
[[ -f "$pkg_dir/PKGBUILD" ]] || { echo "PKGBUILD missing in $pkg_dir" >&2; exit 1; }

resolve_dest_name_from_pkgbuild() {
  local pkgbuild_path="$1"
  local asset_basename="$2"
  local pkgver="$3"
  local pkgrel="$4"

  local token=""
  token="$(
    awk -v needle="$asset_basename" '
      {
        line = $0
        while (match(line, /"[^"]+"/)) {
          token = substr(line, RSTART + 1, RLENGTH - 2)
          if (index(token, needle)) {
            print token
            exit
          }
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$pkgbuild_path" 2>/dev/null || true
  )"

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
  dest_name="$(printf '%s' "$dest_name" | sed -E 's/\$\{[[:alpha:]_][[:alnum:]_]*\}//g; s/\$[[:alpha:]_][[:alnum:]_]*//g')"

  printf '%s' "$dest_name"
}

pkg_type=""
repo=""
asset_regex=""
strip_prefix=""
npm_pkg=""

case "$(basename "$pkg_dir")" in
  mcp-proxy-bin)
    pkg_type="github"
    repo="tidewave-ai/mcp_proxy_rust"
    asset_regex='mcp-proxy-x86_64-unknown-linux-gnu\.tar\.gz'
    strip_prefix="v"
    ;;
  openai-codex-bin)
    pkg_type="github"
    repo="openai/codex"
    asset_regex='codex-x86_64-unknown-linux-gnu\.tar\.gz'
    strip_prefix="rust-v"
    ;;
  tidewave-cli)
    pkg_type="github"
    repo="tidewave-ai/tidewave_app"
    asset_regex='tidewave-cli-x86_64-unknown-linux-gnu$'
    strip_prefix="v"
    ;;
  tidewave-app)
    pkg_type="github"
    repo="tidewave-ai/tidewave_app"
    asset_regex='tidewave-app-amd64\.AppImage$'
    strip_prefix="v"
    ;;
  typescript-go)
    pkg_type="npm"
    npm_pkg="@typescript/native-preview"
    ;;
  github-copilot-cli)
    pkg_type="npm"
    npm_pkg="@github/copilot"
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
  [[ "$tag_name" != "null" ]] || { echo "Could not read tag_name from release JSON" >&2; exit 1; }

  asset_url="$(jq -r --arg re "$asset_regex" '.assets[] | select(.name|test($re)) | .browser_download_url' <<<"$release_json" | head -n1)"
  [[ -n "$asset_url" ]] || { echo "No asset matching /$asset_regex/ found in latest release" >&2; exit 1; }

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
  echo "Querying npm registry for ${npm_pkg}…"
  npm_json="$(NPM_CONFIG_CACHE=${NPM_CONFIG_CACHE:-$pkg_dir/.npm-cache} npm view "${npm_pkg}" version dist.tarball dist.shasum --json)"

  version="$(jq -r 'if type=="array" then (.[-1].version // .[-1]) else (.version // .) end' <<<"$npm_json")"
  tarball="$(jq -r 'if type=="array" then (.[-1]["dist.tarball"]) else (."dist.tarball") end' <<<"$npm_json")"
  shasum="$(jq -r 'if type=="array" then (.[-1]["dist.shasum"]) else (."dist.shasum") end' <<<"$npm_json")"

  [[ -n "$version" && "$version" != "null" ]] || { echo "Failed to read version from npm" >&2; exit 1; }
  [[ -n "$tarball" && "$tarball" != "null" ]] || { echo "Failed to read tarball URL from npm" >&2; exit 1; }
  [[ -n "$shasum" && "$shasum" != "null" ]] || { echo "Failed to read shasum from npm" >&2; exit 1; }

  if [[ "$version" =~ ^7\.0\.0-dev\.([0-9]+)\.([0-9]+)$ ]]; then
    pkgver="${BASH_REMATCH[1]}"
    pkgrel="${BASH_REMATCH[2]}"
  else
    # Fallback: use full version as pkgver, reset pkgrel to 1
    pkgver="$version"
    pkgrel="1"
  fi

  asset_name="$(basename "$tarball")"

  echo "Latest npm version: ${version} -> pkgver=${pkgver}, pkgrel=${pkgrel}"
  echo "Tarball: ${asset_name}"
  echo "sha1: ${shasum}"

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
  sed -i -E "s|^sha1sums=\\('.*'\\)|sha1sums=('${shasum}')|" PKGBUILD
fi

echo "Refreshing .SRCINFO…"
makepkg --printsrcinfo > .SRCINFO

echo "Done."
