#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import hashlib
import secrets
import subprocess
import tarfile
import pytest

PROJECT_DIR = "/home/user/doc_packager"
RAW_DIR = "/home/user/docs_raw"
OUTPUT_DIR = "/home/user/docs_packaged"
MANIFEST_PATH = os.path.join(OUTPUT_DIR, "manifest.json")
ARCHIVE_PATH = os.path.join(OUTPUT_DIR, "archive.tar.gz")


def test_00_project_is_rust_and_application_runs():
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isdir(PROJECT_DIR), f"Rust project missing at {PROJECT_DIR}"
    assert os.path.isfile(cargo_toml), f"Cargo.toml missing at {cargo_toml}"

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["CARGO_HOME"] = "/home/user/.cargo"

    metadata_result = subprocess.run(
        ["/usr/bin/cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", cargo_toml],
        cwd=PROJECT_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Invalid Rust Cargo project:\n{metadata_result.stdout}"
    metadata = json.loads(metadata_result.stdout)
    assert metadata.get("packages"), "Cargo metadata contains no package"
    assert any("bin" in target.get("kind", []) for package in metadata["packages"] for target in package.get("targets", [])), "Project has no Rust binary target"
    assert any(dep.get("name") == "memmap2" for package in metadata["packages"] for dep in package.get("dependencies", [])), "Rust project does not depend on memmap2"

    rust_sources = []
    for root, dirs, files in os.walk(PROJECT_DIR):
        dirs[:] = [d for d in dirs if d != "target"]
        for filename in files:
            if filename.endswith(".rs"):
                path = os.path.join(root, filename)
                with open(path, "r", encoding="utf-8", errors="replace") as source_file:
                    rust_sources.append(source_file.read())
    assert rust_sources, "Project contains no Rust source files"
    source = "\n".join(rust_sources)
    assert re.search(r"\bmemmap2\b", source), "Rust source does not use memmap2"
    assert re.search(r"\bMmap(?:Options)?\b", source) and re.search(r"(?:\.|::)map\s*\(", source), "Rust source does not create a memory map"

    # Add an unpredictable file so the submitted application must actually traverse
    # and process the current input rather than relying on precomputed artifacts.
    probe_dir = os.path.join(RAW_DIR, "verifier_probe", secrets.token_hex(8))
    os.makedirs(probe_dir, exist_ok=False)
    probe_path = os.path.join(probe_dir, secrets.token_hex(8) + ".bin")
    with open(probe_path, "wb") as probe:
        probe.write(secrets.token_bytes(8193))

    for output_path in (MANIFEST_PATH, ARCHIVE_PATH):
        if os.path.lexists(output_path):
            assert os.path.isfile(output_path) or os.path.islink(output_path), f"Expected output path is not a file: {output_path}"
            os.unlink(output_path)

    run_result = subprocess.run(
        ["/usr/bin/cargo", "run", "--quiet", "--manifest-path", cargo_toml],
        cwd=PROJECT_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert run_result.returncode == 0, f"Rust application failed:\n{run_result.stdout}"


def test_manifest_exists_and_hashes_correct():
    manifest_path = "/home/user/docs_packaged/manifest.json"
    raw_dir = "/home/user/docs_raw"

    assert os.path.exists(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("manifest.json is not valid JSON")

    assert isinstance(manifest, dict), "manifest.json must contain a single JSON object"

    # Verify hashes in manifest
    files_checked = 0
    for root, _, files in os.walk(raw_dir):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, raw_dir)
            # Using forward slashes for relative paths as required
            rel_path_fwd = rel_path.replace(os.sep, '/')

            with open(full_path, 'rb') as f:
                content = f.read()
                expected_hash = hashlib.sha256(content).hexdigest()

            assert rel_path_fwd in manifest, f"Missing {rel_path_fwd} in manifest.json"
            assert manifest[rel_path_fwd] == expected_hash, f"Hash mismatch for {rel_path_fwd}. Expected {expected_hash}, got {manifest[rel_path_fwd]}"
            files_checked += 1

    assert files_checked > 0, "No files were found in the raw directory to verify"


def test_archive_exists_and_contents_correct():
    archive_path = "/home/user/docs_packaged/archive.tar.gz"
    raw_dir = "/home/user/docs_raw"

    assert os.path.exists(archive_path), f"Archive file missing at {archive_path}"

    try:
        with tarfile.open(archive_path, 'r:gz') as tar:
            members = tar.getmembers()
            names = tar.getnames()

            # Normalize names (remove leading ./)
            normalized_names = [name[2:] if name.startswith('./') else name for name in names]

            # Check that files exist and are not under docs_raw
            assert 'intro.md' in normalized_names, "Archive is missing intro.md at root"

            for name in normalized_names:
                assert not name.startswith('docs_raw/'), f"Archive contains docs_raw parent directory for '{name}', should be relative to docs_raw root"

            # Check that all files from raw_dir are in the archive and that each
            # archived regular file has exactly the source file's bytes.
            for root, _, files in os.walk(raw_dir):
                for file in files:
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, raw_dir)
                    rel_path_fwd = rel_path.replace(os.sep, '/')

                    assert rel_path_fwd in normalized_names, f"File {rel_path_fwd} is missing from the archive"
                    matching = [member for member, normalized in zip(members, normalized_names) if normalized == rel_path_fwd]
                    assert len(matching) == 1, f"Archive must contain exactly one entry for {rel_path_fwd}"
                    member = matching[0]
                    assert member.isfile(), f"Archive entry {rel_path_fwd} is not a regular file"
                    archived = tar.extractfile(member)
                    assert archived is not None, f"Could not read archive entry {rel_path_fwd}"
                    with open(full_path, 'rb') as source_file:
                        expected_content = source_file.read()
                    assert archived.read() == expected_content, f"Archived content differs from docs_raw for {rel_path_fwd}"
    except tarfile.ReadError:
        pytest.fail(f"Archive at {archive_path} is not a valid gzip-compressed tarball")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
