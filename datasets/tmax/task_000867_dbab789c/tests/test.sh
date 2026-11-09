#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

import pytest

LOG_DIR = "/home/user/logs"
ARCHIVE_DIR = "/home/user/archive"
MANIFEST_PATH = os.path.join(ARCHIVE_DIR, "manifest.json")
IPV4_PATTERN = re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')


def get_sha256(filepath):
    hasher = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def expected_source_files():
    log_a = [
        "[INFO] 192.168.1.10 - System started\n",
        "[DEBUG] 10.0.0.5 - Initializing modules\n",
        "[INFO] 172.16.0.2 - User admin logged in\n",
        "[DEBUG] 192.168.1.10 - Querying database\n",
        "[ERROR] 8.8.8.8 - DNS resolution failed\n",
    ]
    for i in range(1, 41):
        log_a.append(f"[INFO] 192.168.1.{i} - Action {i} completed\n")
        log_a.append(f"[DEBUG] 10.0.0.{i} - Debug info {i}\n")

    log_b = [
        "[WARNING] 10.10.10.10 - High memory usage\n",
        "[INFO] 127.0.0.1 - Health check passed\n",
    ]
    for i in range(41, 101):
        log_b.append(f"[INFO] 192.168.1.{i} - Action {i} completed\n")
        log_b.append(f"[DEBUG] 10.0.0.{i} - Debug info {i}\n")

    return {
        "log_a.txt": "".join(log_a),
        "log_b.txt": "".join(log_b),
    }


def verify_source_logs_and_derive_chunks():
    expected_sources = expected_source_files()
    txt_files = sorted(
        name for name in os.listdir(LOG_DIR)
        if name.endswith(".txt") and os.path.isfile(os.path.join(LOG_DIR, name))
    )
    assert txt_files == sorted(expected_sources), "Source log files were removed, replaced, or added"

    cleaned_lines = []
    for name in txt_files:
        path = os.path.join(LOG_DIR, name)
        with open(path, "r", encoding="utf-8", newline="") as f:
            contents = f.read()
        assert contents == expected_sources[name], f"Source log {name} was modified"

        for line in contents.splitlines(keepends=True):
            if "DEBUG" not in line:
                cleaned_lines.append(IPV4_PATTERN.sub("[REDACTED]", line))

    return [
        "".join(cleaned_lines[i:i + 50]).encode("utf-8")
        for i in range(0, len(cleaned_lines), 50)
    ]


def verify_manifest_exists_and_contents():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest is not valid JSON")

    assert isinstance(manifest, dict), "Manifest must be a JSON object (dictionary)"
    assert len(manifest) > 0, "Manifest is empty"

    chunk_files = sorted(
        f for f in os.listdir(ARCHIVE_DIR)
        if f.startswith("chunk_") and f.endswith(".txt")
    )
    assert len(chunk_files) > 0, "No chunk files found in archive directory"
    assert set(manifest.keys()) == set(chunk_files), "Manifest keys do not match the chunk files present"

    for chunk_file, expected_hash in manifest.items():
        chunk_path = os.path.join(ARCHIVE_DIR, chunk_file)
        actual_hash = get_sha256(chunk_path)
        assert actual_hash == expected_hash, (
            f"Checksum mismatch for {chunk_file}. Expected {expected_hash}, got {actual_hash}"
        )


def verify_chunk_shape_and_contents(expected_chunks):
    chunk_files = sorted(
        f for f in os.listdir(ARCHIVE_DIR)
        if f.startswith("chunk_") and f.endswith(".txt")
    )

    expected_names = [f"chunk_{i:02d}.txt" for i in range(len(expected_chunks))]
    assert chunk_files == expected_names, "Chunk filenames or chunk count are incorrect"

    for i, chunk_file in enumerate(chunk_files):
        chunk_path = os.path.join(ARCHIVE_DIR, chunk_file)
        with open(chunk_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        if i < len(chunk_files) - 1:
            assert len(lines) == 50, f"{chunk_file} does not have exactly 50 lines"
        else:
            assert len(lines) <= 50, f"{chunk_file} has more than 50 lines"
            assert len(lines) > 0, f"{chunk_file} is empty"

        for line_num, line in enumerate(lines, 1):
            assert "DEBUG" not in line, f"Found 'DEBUG' in {chunk_file} at line {line_num}"
            assert not IPV4_PATTERN.search(line), (
                f"Found unmasked IPv4 address in {chunk_file} at line {line_num}"
            )

        with open(chunk_path, "rb") as f:
            actual = f.read()
        assert actual == expected_chunks[i], f"{chunk_file} does not match the cleaned source logs"


def restore_chunks(expected_chunks):
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    for name in os.listdir(ARCHIVE_DIR):
        if name.startswith("chunk_") and name.endswith(".txt"):
            os.unlink(os.path.join(ARCHIVE_DIR, name))
    for i, contents in enumerate(expected_chunks):
        with open(os.path.join(ARCHIVE_DIR, f"chunk_{i:02d}.txt"), "wb") as f:
            f.write(contents)


def test_final_state_and_manifest_script():
    expected_chunks = verify_source_logs_and_derive_chunks()

    # Preserve all original final-state assertions before invoking submitted code.
    verify_manifest_exists_and_contents()
    verify_chunk_shape_and_contents(expected_chunks)

    scripts = sorted(
        p for p in Path("/home/user").rglob("*.py")
        if p.is_file() and not p.is_symlink()
    )
    assert scripts, "No Python script was written under /home/user"

    generated = False
    errors = []
    for script in scripts:
        restore_chunks(expected_chunks)
        if os.path.lexists(MANIFEST_PATH):
            os.unlink(MANIFEST_PATH)
        try:
            result = subprocess.run(
                ["python3", str(script)],
                cwd=str(script.parent),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            if result.returncode != 0:
                errors.append(f"{script}: exited {result.returncode}")
                continue
            verify_manifest_exists_and_contents()
            verify_chunk_shape_and_contents(expected_chunks)
            verify_source_logs_and_derive_chunks()
            generated = True
            break
        except (AssertionError, OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
            errors.append(f"{script}: {exc}")

    assert generated, "No submitted Python script successfully regenerated the correct manifest: " + "; ".join(errors)

    # Ensure the final state still satisfies every archive and manifest assertion.
    verify_manifest_exists_and_contents()
    verify_chunk_shape_and_contents(expected_chunks)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
