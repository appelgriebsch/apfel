# TICKET-018: Publish apfel via Homebrew tap

**Status:** Closed
**Priority:** P2
**Type:** Distribution / packaging

---

## Goal

Make `apfel` installable with:

```bash
brew install Arthur-Ficial/tap/apfel
```

## Implemented

1. Created the tap repository:
   - `Arthur-Ficial/homebrew-tap`
   - Formula path: `Formula/apfel.rb`

2. Published a stable release asset:
   - Git tag: `v0.6.4`
   - Release asset: `apfel-0.6.4-arm64-macos.tar.gz`

3. Added user-facing docs:
   - `brew-install.md`
   - README link + install snippet

4. Published the live install path:

```bash
brew tap Arthur-Ficial/tap
brew install Arthur-Ficial/tap/apfel
```

## Validation

- `brew tap Arthur-Ficial/tap`
- `brew install Arthur-Ficial/tap/apfel`
- `brew test Arthur-Ficial/tap/apfel`
- `brew audit --strict Arthur-Ficial/tap/apfel`
