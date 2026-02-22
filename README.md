# AUR Package Collection (Personal)

This repository is a personal collection of Arch Linux packages. It is maintained primarily for my own use and convenience.

## Status and Expectations

- **Personal use only:** These packages are here so I can build/install them locally.
- **No maintenance commitment:** I’m not actively maintaining this for others.
- **Fork-friendly:** If you need some changes for yourself you are free to fork and fix it for yourself. Not interested in pull requests.
- **Not intended for AUR:** I’m not interested in publishing these packages to the AUR. If you want to do so, feel free to fork and publish.

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
./validate-packages.sh mcp-proxy-bin openai-codex-bin
```
