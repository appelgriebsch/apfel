# nixpkgs distribution

apfel ships on [nixpkgs](https://github.com/NixOS/nixpkgs) under the attribute `apfel-llm`. This page explains the name choice, how the automation works, and how to test or repair the package locally.

## Install (end users)

```bash
nix profile install nixpkgs#apfel-llm
```

Runtime requirements are the same as Homebrew: macOS 26 Tahoe or later, Apple Silicon, Apple Intelligence enabled, Siri language matching device language.

The binary on your `$PATH` is still `apfel` - only the install-time attribute is `apfel-llm`.

## Why `apfel-llm` and not `apfel`

nixpkgs already has an unrelated package at [`pkgs/by-name/ap/apfel`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ap/apfel/package.nix): the [scarrazza/apfel](https://github.com/scarrazza/apfel) particle-physics PDF Evolution Library (GPL3, maintained by `veprbl`). The name was taken years before apfel existed in its AI form, so nixpkgs convention requires disambiguation.

The disambiguator that landed upstream is `apfel-llm` (via [NixOS/nixpkgs#508084](https://github.com/NixOS/nixpkgs/pull/508084)). An earlier proposal used `apfel-ai`, but the upstream maintainer chose `-llm` as the more descriptive suffix. The binary on `$PATH` is still `apfel` either way - only the install attribute differs.

## Why a pre-built binary derivation

apfel links against Apple's [`FoundationModels`](https://developer.apple.com/documentation/foundationmodels) framework, which requires the macOS 26 SDK and Apple Silicon at build time. The nixpkgs darwin stdenv does not currently ship those prerequisites, so building from source inside a Nix sandbox is not reliably supported today.

The derivation installs the same signed release tarball that Homebrew consumes (`apfel-${version}-arm64-macos.tar.gz` attached to each GitHub Release), and declares `sourceProvenance = [ binaryNativeCode ]` to be honest about that.

If nixpkgs' darwin stdenv later gains macOS 26 SDK support, we switch to a source build in a follow-up PR.

## Update automation (two layers)

Every `make release` that publishes a new GitHub Release is picked up by both layers in parallel - whichever opens the bump PR first wins; the second detects the PR already exists and no-ops.

### Layer 1 - community `r-ryantm` bot

nixpkgs has a well-established community [update bot](https://github.com/ryantm/nixpkgs-update) that scans packages weekly for upstream version changes, computes the new SRI hash, and opens a bump PR with CI. Our `package.nix` uses `passthru.updateScript = nix-update-script { }`, which `r-ryantm` reads to drive the update. No action from us.

Expected latency: within ~7 days of release.

### Layer 2 - our own workflow

[`.github/workflows/bump-nixpkgs.yml`](../.github/workflows/bump-nixpkgs.yml) fires on every `release: published` event from `make release`. It:

1. Checks out a fresh copy of `Arthur-Ficial/nixpkgs` (our fork, synced with upstream master).
2. Runs [`scripts/bump-nixpkgs.sh`](../scripts/bump-nixpkgs.sh) to rewrite `version` and `hash` in `pkgs/by-name/ap/apfel-llm/package.nix`.
3. Commits on a branch `apfel-llm-<version>`, force-pushes to the fork.
4. Opens a PR on `NixOS/nixpkgs` (or updates the existing one if already open).

Expected latency: within ~5 minutes of release.

The workflow also supports `workflow_dispatch` with an explicit version, so you can trigger it manually:

```bash
gh workflow run bump-nixpkgs.yml --repo Arthur-Ficial/apfel -f version=1.2.3
```

## The `NIXPKGS_BUMP_PAT` secret

Layer 2 needs a GitHub token with two scopes:

- `contents:write` on `Arthur-Ficial/nixpkgs` (the fork we push branches to)
- `pull-requests:write` on `NixOS/nixpkgs` (to open the bump PR)

A fine-grained Personal Access Token is the right shape. **Setup is a one-time action:**

1. Create the token at <https://github.com/settings/personal-access-tokens/new> with:
   - Resource owner: `Arthur-Ficial`
   - Repository access: Only select repositories: `Arthur-Ficial/nixpkgs`
   - Repository permissions: Contents (Read and write), Pull requests (Read and write), Metadata (Read)
   - Also grant a public-repo token (or fine-grained) with `pull-requests:write` on `NixOS/nixpkgs` - or use classic PAT with `public_repo` scope limited to PR creation.
2. Store it in pass:
   ```bash
   pass insert github/nixpkgs-bump-pat
   ```
3. Add it to the apfel repo secrets:
   ```bash
   gh secret set NIXPKGS_BUMP_PAT --repo Arthur-Ficial/apfel --body "$(pass show github/nixpkgs-bump-pat)"
   ```

If the secret is missing, the workflow logs a warning and no-ops rather than failing - Layer 1 (r-ryantm) still covers the release, just with higher latency.

## Testing the package locally

On any Mac with Nix installed (we use the Determinate Systems installer on Apple Silicon):

```bash
git clone --depth 1 https://github.com/NixOS/nixpkgs.git /tmp/nixpkgs-test
cd /tmp/nixpkgs-test
nix-build -A apfel-llm --no-out-link

# The resulting binary:
ls /nix/store/*-apfel-llm-*/bin/apfel
```

Run it: `/nix/store/...-apfel-llm-.../bin/apfel --version`.

To test a version bump before pushing, point `--file` at your local checkout:

```bash
./scripts/bump-nixpkgs.sh --version 1.2.3 \
  --file /tmp/nixpkgs-test/pkgs/by-name/ap/apfel-llm/package.nix \
  --dry-run
```

## Manual fallback (if both layers fail)

Very rare, but: if r-ryantm is down and the workflow is broken, you can bump by hand:

```bash
cd /tmp/nixpkgs-test
git fetch origin master && git checkout -B apfel-llm-manual origin/master

/path/to/apfel/scripts/bump-nixpkgs.sh \
  --version 1.2.3 \
  --file pkgs/by-name/ap/apfel-llm/package.nix

git add pkgs/by-name/ap/apfel-llm/package.nix
git commit -m "apfel-llm: 1.2.3"
git push fork apfel-llm-manual   # where `fork` is Arthur-Ficial/nixpkgs
gh pr create --repo NixOS/nixpkgs --head Arthur-Ficial:apfel-llm-manual --base master \
  --title "apfel-llm: 1.2.3"
```

## Tracking

- Package source: <https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ap/apfel-llm/package.nix>
- nixpkgs PRs: <https://github.com/NixOS/nixpkgs/pulls?q=is%3Apr+apfel-llm>
- r-ryantm PRs for apfel-llm: <https://github.com/NixOS/nixpkgs/pulls/r-ryantm?q=apfel-llm>
