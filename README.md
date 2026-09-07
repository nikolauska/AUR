# AUR Package Collection (Personal)

This repository is a personal collection of Arch Linux packages. It is maintained primarily for my own use and convenience.

## Status and Expectations

- **Personal use only:** These packages are here so I can build/install them locally.
- **No maintenance commitment:** I’m not actively maintaining this for others.
- **Fork-friendly:** If you need some changes for yourself you are free to fork and fix it for yourself. Not interested in pull requests.
- **Not intended for AUR:** I’m not interested in publishing these packages to the AUR. If you want to do so, feel free to fork and publish.

## Installation

Install packages one at a time, skipping those whose installed version matches the `PKGBUILD`:

```bash
./install-all.sh
```

The script authenticates with `sudo` once before checking packages, then refreshes
the cached credentials every 30 seconds so long builds do not cause repeated
password prompts. It passes `PACMAN_AUTH=sudo` to `makepkg` so installs reuse those
credentials instead of makepkg's default `sudo -k`, which ignores cached credentials.
Builds still run as your normal user. The refresh stops when the script exits.
This requires sudo credential caching; a sudo policy that disables caching (such
as `timestamp_timeout=0`) can still prompt on each install. An explicit
`PACMAN_AUTH` setting in your makepkg configuration overrides the script's setting.

## Validation

Use the validation script to lint shell code and verify package metadata/builds:

```bash
./validate-packages.sh
```

`namcap` errors are strict by default. Use advisory mode only when needed:

```bash
./validate-packages.sh --advisory-namcap
```

Validate specific package directories only:

```bash
./validate-packages.sh sentry-cli-bin oh-my-pi-bin
```
