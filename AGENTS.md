# Repository Guidelines

## Project Structure & Module Organization
- Root contains one AUR-style package per directory: `mcp-proxy-bin/`, `openai-codex-bin/`, and `typescript-go/`. Each holds `PKGBUILD`, generated `pkg/` and `src/` trees (ignored in git), plus any cached tarballs for reproducible builds.
- Treat each directory as its own package workspace. Updates rarely touch sibling packages unless shared tooling changes.

## Build, Test, and Development Commands
- `cd <package> && makepkg -si`: build and install the selected package locally; omits test suites unless upstream bundles them.
- `makepkg --printsrcinfo > .SRCINFO`: refresh metadata after any PKGBUILD edit (commit the result).
- `updpkgsums`: regenerate checksums when sources change.
- `namcap PKGBUILD *.pkg.tar.*`: static lint for packaging mistakes before pushing.
- `./update-pkgbuild.sh <pkg> [--pkgver X] [--pkgrel N]`: convenience wrapper to bump versions, refresh sums, and regenerate `.SRCINFO`.
- `./fetch-latest-release.sh <pkg> [--dry-run]`: pull latest upstream (GitHub or npm) release, update `PKGBUILD`, run `updpkgsums`, and sync `.SRCINFO`. Supports `mcp-proxy-bin`, `openai-codex-bin`, `typescript-go`.
- Scripts assume `curl`, `jq`, `makepkg`, and `updpkgsums` are available (Arch base-devel + pacman-contrib).

## Coding Style & Naming Conventions
- PKGBUILDs are POSIX shell; prefer two-space indentation inside functions and align array entries on new lines.
- Use lowercase variable names consistent with Arch packaging (`pkgname`, `pkgver`, `source_x86_64`, etc.).
- Keep source URLs and checksums in sync; place versioned archives in the package directory to aid reproducibility.
- Comment only when deviating from typical Arch patterns (e.g., unusual `prepare()` steps).

## Testing Guidelines
- Primary validation is a clean `makepkg -si` on Arch or clean chroot; run `namcap` for lint coverage.
- If upstream ships tests, enable them via `check()` and document any disabled cases in comments.
- For new versions, verify binaries run (`codex --version`, `mcp-proxy --help`, `tsc --version`) after install.

## Commit & Pull Request Guidelines
- Write commits in imperative mood, scoped to one package when possible (e.g., `mcp-proxy-bin: bump to 0.2.4`).
- Include `.SRCINFO` and updated sums in the same commit as PKGBUILD changes.
- PRs should list: upstream release or issue link, build/test commands run, and any namcap warnings you chose to waive (with justification).
- Avoid committing built `pkg/` or `src/` contents; `.gitignore` already excludes them—leave it that way.

## Security & Packaging Tips
- Validate vendor tarballs with upstream signatures or release checksums before updating `sha256sums`.
- Keep `optdepends` and `provides/conflicts` aligned with upstream capabilities to prevent upgrade breakage.
- When bumping versions, scan for renamed archives or architecture changes in upstream release pages.
