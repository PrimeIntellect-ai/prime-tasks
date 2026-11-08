#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import io
import os
import json
import tarfile
import hashlib
import tempfile
import re
import secrets
import shutil
import subprocess
import pytest

FINAL_TAR = "/home/user/final_backup.tar"
SCRIPT_PATH = "/home/user/safe_backup.py"
SOURCE_DIR = "/home/user/source_data"
STAGING_DIR = "/home/user/staging"


def get_sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def normalized_tar_name(name: str) -> str:
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def read_outer_member(outer: tarfile.TarFile, wanted: str) -> bytes:
    matches = [m for m in outer.getmembers() if normalized_tar_name(m.name) == wanted]
    assert len(matches) == 1, f"Expected exactly one {wanted} in final tarball."
    assert matches[0].isfile(), f"{wanted} is not a regular file."
    extracted = outer.extractfile(matches[0])
    assert extracted is not None, f"Could not read {wanted}."
    return extracted.read()


def validate_nested_archive(archive_bytes: bytes, top_dir: str, expected_files: dict):
    try:
        with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as nested:
            members = nested.getmembers()
            normalized = [(normalized_tar_name(m.name), m) for m in members]

            for name, _ in normalized:
                assert "loop_to_B" not in name, f"Infinite loop path found in {top_dir}.tar.gz: {name}"
                assert "loop_to_A" not in name, f"Infinite loop path found in {top_dir}.tar.gz: {name}"

            for relative_path, expected_content in expected_files.items():
                allowed_names = {relative_path, f"{top_dir}/{relative_path}"}
                matches = [m for name, m in normalized if name in allowed_names]
                assert len(matches) == 1, (
                    f"Expected {relative_path} exactly once in {top_dir}.tar.gz."
                )
                member = matches[0]
                assert member.isfile(), (
                    f"{relative_path} in {top_dir}.tar.gz must be archived as a regular file."
                )
                extracted = nested.extractfile(member)
                assert extracted is not None
                assert extracted.read() == expected_content, (
                    f"Content mismatch for {relative_path} in {top_dir}.tar.gz."
                )
    except tarfile.TarError as exc:
        pytest.fail(f"{top_dir}.tar.gz is not a valid gzip-compressed tar archive: {exc}")


def test_final_backup_exists_and_extracts():
    assert os.path.isfile(FINAL_TAR), f"Final backup archive {FINAL_TAR} does not exist."
    assert tarfile.is_tarfile(FINAL_TAR), f"{FINAL_TAR} is not a valid tar file."


def test_manifest_and_archives_in_tarball():
    assert os.path.isfile(FINAL_TAR), "Final tarball missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(FINAL_TAR, "r") as tar:
            tar.extractall(path=tmpdir)

        # Look for manifest.json
        manifest_path = os.path.join(tmpdir, "manifest.json")
        assert os.path.isfile(manifest_path), "manifest.json is missing from the final tarball."

        # Check nested archives
        dir_a_archive = os.path.join(tmpdir, "dirA.tar.gz")
        dir_b_archive = os.path.join(tmpdir, "dirB.tar.gz")
        assert os.path.isfile(dir_a_archive), "dirA.tar.gz is missing from the tarball."
        assert os.path.isfile(dir_b_archive), "dirB.tar.gz is missing from the tarball."

        # Validate that the nested archives contain the real source files.
        with open(dir_a_archive, "rb") as f:
            validate_nested_archive(f.read(), "dirA", {
                "fileA.txt": b"data_A\n",
                "valid_link.txt": b"root_file\n",
            })
        with open(dir_b_archive, "rb") as f:
            validate_nested_archive(f.read(), "dirB", {
                "fileB.txt": b"data_B\n",
            })

        # Validate manifest content
        with open(manifest_path, "r") as f:
            try:
                manifest = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("manifest.json is not valid JSON.")

        expected_hashes = {
            "dirA/fileA.txt": get_sha256(b"data_A\n"),
            "dirB/fileB.txt": get_sha256(b"data_B\n"),
            "root.txt": get_sha256(b"root_file\n"),
            "dirA/valid_link.txt": get_sha256(b"root_file\n")
        }

        for path, expected_hash in expected_hashes.items():
            assert path in manifest, f"Expected path {path} missing in manifest.json"
            assert manifest[path] == expected_hash, f"Hash mismatch for {path}. Expected {expected_hash}, got {manifest[path]}"

        # Check that no infinite loop paths are present
        for path in manifest.keys():
            assert "loop_to_B" not in path, f"Infinite loop path found in manifest: {path}"
            assert "loop_to_A" not in path, f"Infinite loop path found in manifest: {path}"


def test_script_uses_atomic_write():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Check for temporary file usage and rename/replace/move
    has_tmp = ".tmp" in content or "manifest.json.tmp" in content
    has_atomic_op = re.search(r'(os\.rename|os\.replace|shutil\.move)\s*\(', content)

    assert has_tmp and has_atomic_op, "Script does not appear to use an atomic write pattern (writing to a .tmp file and renaming/replacing)."


def test_script_rebuilds_archives_with_unpredictable_files():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."

    token = secrets.token_hex(12)
    name_a = f"runtime_{token}_a.bin"
    name_b = f"runtime_{token}_b.bin"
    content_a = secrets.token_bytes(97)
    content_b = secrets.token_bytes(131)
    path_a = os.path.join(SOURCE_DIR, "dirA", name_a)
    path_b = os.path.join(SOURCE_DIR, "dirB", name_b)

    with open(path_a, "wb") as f:
        f.write(content_a)
    with open(path_b, "wb") as f:
        f.write(content_b)

    shutil.rmtree(STAGING_DIR, ignore_errors=True)
    os.makedirs(STAGING_DIR, exist_ok=True)
    if os.path.lexists(FINAL_TAR):
        os.unlink(FINAL_TAR)

    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Backup script failed when executed. stdout={result.stdout!r} stderr={result.stderr!r}"
        )
        assert os.path.isfile(FINAL_TAR), "Script did not regenerate final_backup.tar."
        assert tarfile.is_tarfile(FINAL_TAR), "Regenerated final_backup.tar is invalid."

        with tarfile.open(FINAL_TAR, "r") as outer:
            manifest_bytes = read_outer_member(outer, "manifest.json")
            dir_a_bytes = read_outer_member(outer, "dirA.tar.gz")
            dir_b_bytes = read_outer_member(outer, "dirB.tar.gz")

        try:
            manifest = json.loads(manifest_bytes.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            pytest.fail(f"Regenerated manifest.json is invalid: {exc}")

        expected_hashes = {
            "dirA/fileA.txt": get_sha256(b"data_A\n"),
            "dirB/fileB.txt": get_sha256(b"data_B\n"),
            "root.txt": get_sha256(b"root_file\n"),
            "dirA/valid_link.txt": get_sha256(b"root_file\n"),
            f"dirA/{name_a}": get_sha256(content_a),
            f"dirB/{name_b}": get_sha256(content_b),
        }
        for path, expected_hash in expected_hashes.items():
            assert manifest.get(path) == expected_hash, (
                f"Regenerated manifest has wrong or missing hash for {path}."
            )
        for path in manifest:
            assert "loop_to_B" not in path, f"Infinite loop path found in manifest: {path}"
            assert "loop_to_A" not in path, f"Infinite loop path found in manifest: {path}"

        validate_nested_archive(dir_a_bytes, "dirA", {
            "fileA.txt": b"data_A\n",
            "valid_link.txt": b"root_file\n",
            name_a: content_a,
        })
        validate_nested_archive(dir_b_bytes, "dirB", {
            "fileB.txt": b"data_B\n",
            name_b: content_b,
        })
    finally:
        for path in (path_a, path_b):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
