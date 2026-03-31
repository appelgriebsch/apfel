# Install with Homebrew

`apfel` is available through the `Arthur-Ficial/tap` tap:

```bash
brew tap Arthur-Ficial/tap
brew install Arthur-Ficial/tap/apfel
```

Verify the install:

```bash
apfel --version
apfel --release
```

## Requirements

- Apple Silicon
- macOS 26.4 or newer
- Apple Intelligence enabled

Homebrew installs the `apfel` binary. You do **not** need Xcode.

## Troubleshooting

If the binary runs but generation is unavailable, check:

```bash
apfel --model-info
```

If you already installed `apfel` manually into `/usr/local/bin/apfel`, make sure the Homebrew binary is first in your `PATH`:

```bash
which apfel
brew --prefix
```

## Maintainer Release Flow

1. Keep `.version` at the intended release version.
2. Refresh `Sources/BuildInfo.swift` without bumping the version:

```bash
make generate-build-info
```

3. Build the release binary:

```bash
swift build -c release
```

4. Package the binary asset:

```bash
tar -C .build/release -czf apfel-$(cat .version)-arm64-macos.tar.gz apfel
shasum -a 256 apfel-$(cat .version)-arm64-macos.tar.gz
```

5. Tag and publish the release:

```bash
git tag v$(cat .version)
git push origin v$(cat .version)
gh release create v$(cat .version) apfel-$(cat .version)-arm64-macos.tar.gz --title "v$(cat .version)" --notes "Homebrew release"
```

6. Update `Arthur-Ficial/homebrew-tap`:
   - set the new `url`
   - set the new `sha256`
   - commit and push

7. Validate:

```bash
brew update
brew tap Arthur-Ficial/tap
brew reinstall Arthur-Ficial/tap/apfel
brew test Arthur-Ficial/tap/apfel
brew audit --strict Arthur-Ficial/tap/apfel
```
