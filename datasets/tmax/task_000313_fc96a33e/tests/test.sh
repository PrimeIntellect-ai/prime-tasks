#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = Path("/home/user/process_audit.py")
LOG_PATH = Path("/home/user/storage_audit.log")
MANIFEST_PATH = Path("/home/user/backed_up_manifest.txt")


def parse_backed_up_paths(log_path):
    content = log_path.read_text(encoding="utf-16le")
    paths = []
    current = None

    for line in content.splitlines():
        if line == "=== RECORD ===":
            current = {}
        elif line == "=== END ===":
            if current is not None and current.get("Action") == "BackedUp":
                assert "Path" in current, "A BackedUp record is missing its Path field."
                paths.append(current["Path"])
            current = None
        elif current is not None and ": " in line:
            key, value = line.split(": ", 1)
            current[key] = value

    return paths


def get_expected_manifest(log_path=LOG_PATH):
    manifest_entries = []
    for filepath in parse_backed_up_paths(log_path):
        assert os.path.isfile(filepath), f"Expected file {filepath} is missing from the system."
        with open(filepath, "rb") as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()
        manifest_entries.append((filepath, f"{file_hash} *{filepath}"))

    manifest_entries.sort(key=lambda entry: entry[0])
    return [line for _, line in manifest_entries]


def run_submission():
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"process_audit.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_manifest(expected_lines):
    assert os.path.isfile(MANIFEST_PATH), (
        f"Output manifest file {MANIFEST_PATH} was not created."
    )

    try:
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            actual_content = f.read()
    except UnicodeDecodeError:
        pytest.fail(f"Manifest file {MANIFEST_PATH} is not encoded in valid UTF-8.")

    actual_lines = actual_content.splitlines()
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in manifest, but found {len(actual_lines)}."
    )

    for i, (actual_line, expected_line) in enumerate(zip(actual_lines, expected_lines)):
        assert actual_line == expected_line, (
            f"Line {i + 1} mismatch.\nExpected: {expected_line}\nActual:   {actual_line}"
        )


def test_script_exists_and_is_regular_python_file():
    assert SCRIPT_PATH.exists(), f"Required script {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), (
        f"Required script {SCRIPT_PATH} is not a regular file."
    )


def test_original_log_and_manifest():
    expected_lines = get_expected_manifest()
    run_submission()
    assert_manifest(expected_lines)


def test_script_parses_utf16_log_instead_of_using_a_fixed_file_list():
    original_log = LOG_PATH.read_bytes()
    original_manifest = MANIFEST_PATH.read_bytes() if MANIFEST_PATH.exists() else None
    temp_dir = Path(tempfile.mkdtemp(prefix="audit_verify_", dir="/home/user/storage"))

    try:
        alpha = temp_dir / "alpha.txt"
        middle = temp_dir / "middle.bin"
        zeta = temp_dir / "zeta.data"
        skipped = temp_dir / "skipped.txt"
        alpha.write_bytes(b"dynamic alpha content\n")
        middle.write_bytes(bytes(range(32)))
        zeta.write_bytes(b"dynamic zeta content")
        skipped.write_bytes(b"this file must not appear")

        records = [
            (zeta, "File", "BackedUp"),
            (Path("/home/user/storage/docs/report.txt"), "File", "Skipped"),
            (skipped, "File", "Skipped"),
            (alpha, "File", "BackedUp"),
            (middle, "File", "BackedUp"),
        ]
        lines = []
        for path, file_type, action in records:
            lines.extend([
                "=== RECORD ===",
                f"Path: {path}",
                f"Type: {file_type}",
                f"Action: {action}",
                "=== END ===",
            ])
        LOG_PATH.write_text("\n".join(lines) + "\n", encoding="utf-16le")

        expected_lines = get_expected_manifest()
        run_submission()
        assert_manifest(expected_lines)
    finally:
        LOG_PATH.write_bytes(original_log)
        if original_manifest is None:
            try:
                MANIFEST_PATH.unlink()
            except FileNotFoundError:
                pass
        else:
            MANIFEST_PATH.write_bytes(original_manifest)
        shutil.rmtree(temp_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
