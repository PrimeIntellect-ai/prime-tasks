#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import signal
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT_DIR = Path("/home/user/manifest_builder")
MANIFEST_PATH = Path("/home/user/manifest.txt")
ORIGINAL_ROOT = Path("/home/user/project_data")


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def run_command(command, cwd=None, timeout=120):
    process = subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        pytest.fail(
            f"Command timed out after {timeout}s (possible symlink loop): {command}\n"
            f"stdout:\n{stdout}\nstderr:\n{stderr}"
        )
    assert process.returncode == 0, (
        f"Command failed with exit code {process.returncode}: {command}\n"
        f"stdout:\n{stdout}\nstderr:\n{stderr}"
    )
    return stdout


@pytest.fixture(scope="session")
def built_binary():
    metadata_text = run_command(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT_DIR,
        timeout=60,
    )
    metadata = json.loads(metadata_text)
    matching_packages = [
        package for package in metadata["packages"]
        if Path(package["manifest_path"]).resolve() == (PROJECT_DIR / "Cargo.toml").resolve()
    ]
    assert matching_packages, "Cargo.toml does not define a Cargo package."
    assert matching_packages[0]["name"] == "manifest_builder", (
        "The Cargo package must be named manifest_builder."
    )
    assert any(
        target["name"] == "manifest_builder" and "bin" in target["kind"]
        for target in matching_packages[0]["targets"]
    ), "The project must define a manifest_builder binary target."

    # Force the submitted Rust source to be compiled rather than trusting a stale binary.
    run_command(["cargo", "clean"], cwd=PROJECT_DIR, timeout=60)
    run_command(["cargo", "build", "--release", "--offline"], cwd=PROJECT_DIR, timeout=180)

    binary = PROJECT_DIR / "target" / "release" / "manifest_builder"
    assert binary.is_file(), f"Compiled binary {binary} is missing."
    assert os.access(binary, os.X_OK), f"Compiled binary {binary} is not executable."
    return binary


def run_builder(binary, root):
    if MANIFEST_PATH.exists() or MANIFEST_PATH.is_symlink():
        MANIFEST_PATH.unlink()
    run_command([str(binary), str(root)], cwd=PROJECT_DIR, timeout=20)
    assert MANIFEST_PATH.is_file(), (
        "The program did not create /home/user/manifest.txt when executed."
    )


def expected_manifest(files):
    canonical_files = sorted({Path(path).resolve() for path in files}, key=lambda p: str(p))
    return [f"{get_sha256(path)}  {path}" for path in canonical_files]


def assert_exact_manifest(files):
    assert MANIFEST_PATH.is_file(), f"Manifest file {MANIFEST_PATH} is missing."
    actual_lines = MANIFEST_PATH.read_text().splitlines()
    expected_lines = expected_manifest(files)
    assert actual_lines == expected_lines, (
        "Generated manifest does not exactly match the unique canonical files, checksums, "
        "two-space format, and canonical-path ordering.\n"
        f"Expected: {expected_lines!r}\nActual:   {actual_lines!r}"
    )


def test_rust_project_exists():
    manifest_builder_dir = "/home/user/manifest_builder"
    cargo_toml = os.path.join(manifest_builder_dir, "Cargo.toml")

    assert os.path.isdir(manifest_builder_dir), f"Rust project directory {manifest_builder_dir} is missing."
    assert os.path.isfile(cargo_toml), f"Cargo.toml is missing in {manifest_builder_dir}."


def test_manifest_file_correctness(built_binary):
    # Generate the required final manifest by actually executing the submitted program.
    run_builder(built_binary, ORIGINAL_ROOT)

    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    # The three unique regular files we expect to be processed
    expected_files = [
        "/home/user/project_data/docs/readme.txt",
        "/home/user/project_data/assets/blob.bin",
        "/home/user/project_data/src/main.rs"
    ]

    expected_lines = []
    for f in expected_files:
        assert os.path.exists(f), f"Expected test file {f} is missing, environment might be corrupted."
        real_path = os.path.realpath(f)
        sha_hex = get_sha256(real_path)
        expected_lines.append(f"{sha_hex}  {real_path}")

    # Sort lines alphabetically by the canonical absolute path
    expected_lines.sort(key=lambda line: line.split("  ")[1])

    with open(manifest_path, "r") as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Manifest has {len(actual_lines)} lines, expected {len(expected_lines)}. "
        "Ensure symlinks are deduplicated and loops are avoided."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: '{expected}'\nActual:   '{actual}'"


def test_dynamic_traversal_symlink_loops_and_repeated_runs(built_binary):
    try:
        with tempfile.TemporaryDirectory(prefix="manifest-verifier-") as temporary:
            root = Path(temporary).resolve()
            docs = root / "docs"
            assets = root / "assets"
            nested = root / "nested"
            docs.mkdir()
            assets.mkdir()
            nested.mkdir()

            text_file = docs / "random.txt"
            binary_file = assets / "random.bin"
            empty_file = nested / "empty.dat"
            text_file.write_bytes(b"dynamic-" + os.urandom(37))
            binary_file.write_bytes(os.urandom(8193))
            empty_file.write_bytes(b"")

            # Duplicate file and directory aliases plus two recursive directory loops.
            (docs / "binary_alias.bin").symlink_to(binary_file)
            (root / "docs_alias").symlink_to(docs, target_is_directory=True)
            (nested / "back_to_root").symlink_to(root, target_is_directory=True)
            (docs / "self_loop").symlink_to(docs, target_is_directory=True)

            files = [text_file, binary_file, empty_file]
            run_builder(built_binary, root)
            assert_exact_manifest(files)

            # Change the input and rerun to ensure the CLI argument is honored and the
            # manifest is freshly generated rather than copied from a fixed fixture.
            text_file.write_bytes(b"changed-" + os.urandom(53))
            added_file = nested / "new.bin"
            added_file.write_bytes(os.urandom(257))
            files.append(added_file)
            run_builder(built_binary, root)
            assert_exact_manifest(files)
    finally:
        # Leave the required manifest populated for the instructed project_data input.
        run_builder(built_binary, ORIGINAL_ROOT)

    assert_exact_manifest([
        ORIGINAL_ROOT / "docs" / "readme.txt",
        ORIGINAL_ROOT / "assets" / "blob.bin",
        ORIGINAL_ROOT / "src" / "main.rs",
    ])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
