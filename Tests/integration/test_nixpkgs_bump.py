"""Tests for scripts/bump-nixpkgs.sh.

The bump script updates `version` and `hash` fields in a nixpkgs
package.nix, driven either by a local tarball (for testing) or by
downloading the GitHub release tarball (production).

These tests use --tarball to avoid network and run deterministically.
"""
import base64
import hashlib
import pathlib
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "bump-nixpkgs.sh"

OLD_VERSION = "1.0.0"
NEW_VERSION = "9.9.9"
OLD_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

TEMPLATE = '''{{
  lib,
  stdenvNoCC,
  fetchurl,
  nix-update-script,
}}:

stdenvNoCC.mkDerivation (finalAttrs: {{
  pname = "apfel-llm";
  version = "{version}";

  src = fetchurl {{
    url = "https://github.com/Arthur-Ficial/apfel/releases/download/v${{finalAttrs.version}}/apfel-${{finalAttrs.version}}-arm64-macos.tar.gz";
    hash = "{hash}";
  }};

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    install -Dm755 apfel $out/bin/apfel
  '';

  passthru.updateScript = nix-update-script {{ }};

  meta = {{
    description = "test";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    maintainers = [ ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "apfel";
  }};
}})
'''


def sri_of(data: bytes) -> str:
    digest = hashlib.sha256(data).digest()
    return "sha256-" + base64.standard_b64encode(digest).decode()


@pytest.fixture
def package_nix(tmp_path):
    p = tmp_path / "package.nix"
    p.write_text(TEMPLATE.format(version=OLD_VERSION, hash=OLD_HASH))
    return p


@pytest.fixture
def tarball(tmp_path):
    """Tiny fake tarball with deterministic bytes; used so SRI hash is predictable."""
    content = b"fake-tarball-content-for-testing\n"
    t = tmp_path / "apfel-9.9.9-arm64-macos.tar.gz"
    t.write_bytes(content)
    return t, sri_of(content)


def run_script(*args, expect_rc=0):
    result = subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True,
        text=True,
    )
    assert result.returncode == expect_rc, (
        f"expected rc={expect_rc}, got {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


class TestBumpNixpkgs:
    def test_script_exists_and_is_executable(self):
        assert SCRIPT.exists(), f"missing: {SCRIPT}"
        assert SCRIPT.stat().st_mode & 0o111, f"not executable: {SCRIPT}"

    def test_dry_run_does_not_modify_file(self, package_nix, tarball):
        tarball_path, _ = tarball
        before = package_nix.read_text()
        run_script(
            "--version", NEW_VERSION,
            "--file", str(package_nix),
            "--tarball", str(tarball_path),
            "--dry-run",
        )
        after = package_nix.read_text()
        assert before == after, "dry-run must not modify the file"

    def test_dry_run_prints_diff(self, package_nix, tarball):
        tarball_path, expected_sri = tarball
        result = run_script(
            "--version", NEW_VERSION,
            "--file", str(package_nix),
            "--tarball", str(tarball_path),
            "--dry-run",
        )
        assert OLD_VERSION in result.stdout
        assert NEW_VERSION in result.stdout
        assert OLD_HASH in result.stdout
        assert expected_sri in result.stdout

    def test_real_run_updates_version(self, package_nix, tarball):
        tarball_path, _ = tarball
        run_script(
            "--version", NEW_VERSION,
            "--file", str(package_nix),
            "--tarball", str(tarball_path),
        )
        contents = package_nix.read_text()
        assert f'version = "{NEW_VERSION}";' in contents
        assert f'version = "{OLD_VERSION}";' not in contents

    def test_real_run_updates_hash(self, package_nix, tarball):
        tarball_path, expected_sri = tarball
        run_script(
            "--version", NEW_VERSION,
            "--file", str(package_nix),
            "--tarball", str(tarball_path),
        )
        contents = package_nix.read_text()
        assert f'hash = "{expected_sri}";' in contents
        assert OLD_HASH not in contents

    def test_real_run_preserves_other_content(self, package_nix, tarball):
        tarball_path, _ = tarball
        before = package_nix.read_text()
        run_script(
            "--version", NEW_VERSION,
            "--file", str(package_nix),
            "--tarball", str(tarball_path),
        )
        after = package_nix.read_text()
        # Diff should be exactly the version + hash lines, nothing else.
        before_lines = [l for l in before.splitlines() if "version = " not in l and "hash = " not in l]
        after_lines = [l for l in after.splitlines() if "version = " not in l and "hash = " not in l]
        assert before_lines == after_lines, "bump must only touch version and hash lines"

    def test_idempotent_when_already_at_version(self, package_nix, tarball):
        tarball_path, _expected_sri = tarball
        # First run
        run_script(
            "--version", NEW_VERSION,
            "--file", str(package_nix),
            "--tarball", str(tarball_path),
        )
        snapshot = package_nix.read_text()
        # Second run with same args
        run_script(
            "--version", NEW_VERSION,
            "--file", str(package_nix),
            "--tarball", str(tarball_path),
        )
        assert package_nix.read_text() == snapshot, "re-running bump must be a no-op"

    def test_missing_required_args_fails(self, package_nix):
        run_script(
            "--version", NEW_VERSION,
            "--file", str(package_nix),
            expect_rc=1,
        )

    def test_missing_file_fails(self, tmp_path, tarball):
        tarball_path, _ = tarball
        missing = tmp_path / "nonexistent.nix"
        run_script(
            "--version", NEW_VERSION,
            "--file", str(missing),
            "--tarball", str(tarball_path),
            expect_rc=1,
        )

    def test_missing_tarball_fails(self, package_nix, tmp_path):
        missing = tmp_path / "nonexistent.tar.gz"
        run_script(
            "--version", NEW_VERSION,
            "--file", str(package_nix),
            "--tarball", str(missing),
            expect_rc=1,
        )

    def test_dry_run_output_does_not_call_git_or_gh(self, package_nix, tarball, tmp_path, monkeypatch):
        """The bump script must not shell out to git or gh - that's the workflow's job.

        We enforce this by pointing PATH at an empty directory where the only
        git/gh available would fail loudly, and verifying --dry-run still succeeds.
        """
        tarball_path, _ = tarball
        empty_bin = tmp_path / "empty-bin"
        empty_bin.mkdir()
        # Stubs that exit with a clear error if called
        for name in ("git", "gh"):
            stub = empty_bin / name
            stub.write_text("#!/bin/sh\necho 'FORBIDDEN: bump script must not call $0' >&2\nexit 99\n")
            stub.chmod(0o755)
        # Keep essentials (nix-prefetch-url, sha256sum, python3, bash) visible.
        preserved = "/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        monkeypatch.setenv("PATH", f"{empty_bin}:{preserved}")
        result = subprocess.run(
            ["bash", str(SCRIPT),
             "--version", NEW_VERSION,
             "--file", str(package_nix),
             "--tarball", str(tarball_path),
             "--dry-run"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"dry-run must not require git/gh\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert "FORBIDDEN" not in result.stderr
