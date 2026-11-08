#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import pytest
import secrets
import shutil
import struct
import subprocess
import sys


def test_extract_docs_script_exists():
    """Verify that the user created the extraction script."""
    script_path = "/home/user/extract_docs.py"
    assert os.path.isfile(script_path), f"Python script is missing at {script_path}"


def test_output_dir_exists():
    """Verify that the output directory was created."""
    output_dir = "/home/user/extracted_docs"
    assert os.path.isdir(output_dir), f"Expected output directory {output_dir} does not exist."


def test_extracted_files_exist_and_flattened():
    """Verify that all files were extracted to the output directory with flattened paths."""
    output_dir = "/home/user/extracted_docs"
    expected_files = {"intro.md", "logo.png", "passwd_override.txt"}

    if not os.path.isdir(output_dir):
        pytest.fail(f"Output directory {output_dir} missing, cannot check files.")

    actual_files = set(os.listdir(output_dir))
    assert actual_files == expected_files, f"Extracted files do not match expected. Expected {expected_files}, got {actual_files}"


def test_no_directory_traversal():
    """Verify that zip-slip mitigation worked and files weren't extracted outside the output dir."""
    bad_path_1 = "/home/user/etc/passwd_override.txt"
    bad_path_2 = "/etc/passwd_override.txt"

    assert not os.path.exists(bad_path_1), f"Directory traversal occurred: file written to {bad_path_1}"
    assert not os.path.exists(bad_path_2), f"Directory traversal occurred: file written to {bad_path_2}"


def test_manifest_json_correct():
    """Verify that the manifest.json file exists and contains the correct mapping."""
    manifest_path = "/home/user/manifest.json"
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{manifest_path} is not valid JSON.")

    expected_hashes = {
        "intro.md": "ab2221650bde48644ed1bd1710817c1815147bf140228e3b7b99ba14c4da4397",
        "logo.png": "e11505bd27bb9480cf890f845a7bdc31aef70bc3caebbb12eb36cb07ed564b07",
        "passwd_override.txt": "76ab5a8e2cc89d363717ea2a514d7dcdd9ba33de8e762c2f60d6964a2bd017c6"
    }

    assert manifest == expected_hashes, f"Manifest contents do not match expected. Got: {manifest}"


def test_extracted_file_contents_match():
    """Verify that the extracted files have the correct contents matching the expected hashes."""
    expected_hashes = {
        "intro.md": "ab2221650bde48644ed1bd1710817c1815147bf140228e3b7b99ba14c4da4397",
        "logo.png": "e11505bd27bb9480cf890f845a7bdc31aef70bc3caebbb12eb36cb07ed564b07",
        "passwd_override.txt": "76ab5a8e2cc89d363717ea2a514d7dcdd9ba33de8e762c2f60d6964a2bd017c6"
    }

    for filename, expected_hash in expected_hashes.items():
        filepath = os.path.join("/home/user/extracted_docs", filename)
        assert os.path.isfile(filepath), f"File {filename} is missing from output directory."

        with open(filepath, "rb") as f:
            content = f.read()
            actual_hash = hashlib.sha256(content).hexdigest()

        assert actual_hash == expected_hash, f"Hash mismatch for {filename}. Expected {expected_hash}, got {actual_hash}"


def test_script_parses_dynamic_archive_config_and_flattens_paths():
    """Execute the submitted script against a fresh, unpredictable fixture."""
    token = secrets.token_hex(10)
    archive_path = "/home/user/docs_archive.docpack"
    config_path = "/home/user/doc_config.ini"
    manifest_path = "/home/user/manifest.json"
    script_path = "/home/user/extract_docs.py"
    output_dir = f"/home/user/verify_output_{token}"
    escaped_path = f"/tmp/escaped_{token}.bin"

    entries = [
        (f"manual/sections/topic_{token}.md", b"dynamic documentation\n" + os.urandom(37)),
        (f"images/deep/icon_{token}.dat", os.urandom(81)),
        (f"../../../../tmp/escaped_{token}.bin", b"safe traversal payload\x00" + os.urandom(29)),
    ]
    expected = {os.path.basename(path): content for path, content in entries}
    expected_manifest = {
        name: hashlib.sha256(content).hexdigest()
        for name, content in expected.items()
    }

    archive_backup = open(archive_path, "rb").read()
    config_backup = open(config_path, "rb").read()
    manifest_existed = os.path.exists(manifest_path)
    manifest_backup = open(manifest_path, "rb").read() if manifest_existed else None

    shutil.rmtree(output_dir, ignore_errors=True)
    if os.path.lexists(escaped_path):
        os.remove(escaped_path)

    try:
        with open(archive_path, "wb") as archive:
            archive.write(b"DOCP")
            archive.write(struct.pack("<I", len(entries)))
            for stored_path, content in entries:
                path_bytes = stored_path.encode("utf-8")
                archive.write(struct.pack("<H", len(path_bytes)))
                archive.write(path_bytes)
                archive.write(struct.pack("<I", len(content)))
                archive.write(content)

        with open(config_path, "w", encoding="utf-8") as config:
            config.write(f"[Settings]\noutput_dir = {output_dir}\n")
        if os.path.exists(manifest_path):
            os.remove(manifest_path)

        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"extract_docs.py failed on a fresh archive (exit {result.returncode}). "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        assert os.path.isdir(output_dir), "Script did not honor output_dir from the changed INI file"
        assert set(os.listdir(output_dir)) == set(expected), (
            "Dynamic archive entries were not all extracted using only their base filenames"
        )
        for name, content in expected.items():
            path = os.path.join(output_dir, name)
            assert os.path.isfile(path), f"Dynamic extracted file is missing: {name}"
            with open(path, "rb") as extracted:
                assert extracted.read() == content, f"Dynamic extracted content is wrong for {name}"

        assert not os.path.exists(escaped_path), (
            f"Directory traversal occurred while processing the dynamic fixture: {escaped_path}"
        )
        assert os.path.isfile(manifest_path), "Script did not regenerate /home/user/manifest.json"
        with open(manifest_path, "r", encoding="utf-8") as manifest_file:
            assert json.load(manifest_file) == expected_manifest
    finally:
        with open(archive_path, "wb") as archive:
            archive.write(archive_backup)
        with open(config_path, "wb") as config:
            config.write(config_backup)
        if manifest_existed:
            with open(manifest_path, "wb") as manifest_file:
                manifest_file.write(manifest_backup)
        elif os.path.exists(manifest_path):
            os.remove(manifest_path)
        shutil.rmtree(output_dir, ignore_errors=True)
        if os.path.lexists(escaped_path):
            os.remove(escaped_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
