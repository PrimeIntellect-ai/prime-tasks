#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
from pathlib import Path
import random
import secrets
import shutil
import subprocess

import pytest


def test_valid_files_moved():
    expected_paths = [
        "/home/user/organized/1.2/linux/amd64/worker_v1.2.3_linux_amd64.bin",
        "/home/user/organized/2.0/windows/amd64/worker_v2.0.0-alpha_windows_amd64.bin",
        "/home/user/organized/2.0/linux/amd64/worker_v2.0.1_linux_amd64.bin",
        "/home/user/organized/2.1/darwin/arm64/worker_v2.1.0-rc.1_darwin_arm64.bin"
    ]
    for path in expected_paths:
        assert os.path.isfile(path), f"Valid file was not moved to the expected location: {path}"

    checksum_path = Path("/home/user/artifacts/checksums.txt")
    assert checksum_path.is_file(), "checksums.txt is missing"
    listed_hashes = {}
    for line in checksum_path.read_text().splitlines():
        digest, filename = line.split(maxsplit=1)
        listed_hashes[filename.lstrip(" *")] = digest.lower()

    for path in expected_paths:
        p = Path(path)
        actual = hashlib.sha256(p.read_bytes()).hexdigest()
        assert actual == listed_hashes[p.name], f"Moved binary has incorrect content: {path}"
        assert not (Path("/home/user/artifacts") / p.name).exists(), f"Valid file was not moved out of the source directory: {p.name}"


def test_invalid_files_not_moved():
    invalid_files = [
        "/home/user/artifacts/worker_v1.3.0_linux_arm64.bin",
        "/home/user/artifacts/worker_v1.2.4_darwin_amd64.bin"
    ]
    for path in invalid_files:
        assert os.path.isfile(path), f"Invalid file should not have been moved, but is missing from source: {path}"


def test_latest_version_file():
    path = "/home/user/latest_version.txt"
    assert os.path.isfile(path), f"Latest version file is missing: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "2.0.1", f"Expected latest version to be '2.0.1', but got '{content}'"


def test_mock_env_json():
    path = "/home/user/organized/2.0/linux/amd64/mock_env.json"
    assert os.path.isfile(path), f"Mock env file is missing: {path}"
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    expected_data = {"test_mode": True, "version": "2.0.1"}
    assert data == expected_data, f"Mock env file content is incorrect. Expected {expected_data}, got {data}"


def test_z_organizer_executes_and_processes_fresh_inputs():
    script = Path("/home/user/organizer.py")
    assert script.is_file(), "Required script /home/user/organizer.py is missing"
    assert not script.is_symlink(), "/home/user/organizer.py must be a regular submitted file"

    artifacts = Path("/home/user/artifacts")
    organized = Path("/home/user/organized")
    latest = Path("/home/user/latest_version.txt")

    shutil.rmtree(artifacts, ignore_errors=True)
    shutil.rmtree(organized, ignore_errors=True)
    if latest.exists() or latest.is_symlink():
        latest.unlink()
    artifacts.mkdir(parents=True)

    major = 2 + secrets.randbelow(7)
    cases = [
        (f"worker_v{major}.9.9_linux_amd64.bin", f"low-{secrets.token_hex(24)}\n".encode(), True),
        (f"worker_v{major}.10.0_darwin_arm64.bin", f"highest-{secrets.token_hex(24)}\n".encode(), True),
        (f"worker_v{major}.2.50_windows_amd64.bin", f"older-{secrets.token_hex(24)}\n".encode(), True),
        (f"worker_v{major + 5}.0.0-rc.1_linux_arm64.bin", f"prerelease-{secrets.token_hex(24)}\n".encode(), True),
        (f"worker_v{major + 9}.0.0_windows_arm64.bin", f"corrupt-{secrets.token_hex(24)}\n".encode(), False),
    ]

    checksum_lines = []
    expected_valid = {}
    invalid_name = None
    invalid_payload = None
    for filename, payload, valid in cases:
        (artifacts / filename).write_bytes(payload)
        digest = hashlib.sha256(payload).hexdigest()
        if not valid:
            invalid_name = filename
            invalid_payload = payload
            digest = ("0" if digest[0] != "0" else "1") + digest[1:]
        else:
            expected_valid[filename] = payload
        checksum_lines.append(f"{digest}  {filename}\n")

    random.SystemRandom().shuffle(checksum_lines)
    (artifacts / "checksums.txt").write_text("".join(checksum_lines))

    result = subprocess.run(
        ["python3", str(script)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"organizer.py failed on fresh inputs:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    destinations = {
        f"worker_v{major}.9.9_linux_amd64.bin": organized / f"{major}.9/linux/amd64/worker_v{major}.9.9_linux_amd64.bin",
        f"worker_v{major}.10.0_darwin_arm64.bin": organized / f"{major}.10/darwin/arm64/worker_v{major}.10.0_darwin_arm64.bin",
        f"worker_v{major}.2.50_windows_amd64.bin": organized / f"{major}.2/windows/amd64/worker_v{major}.2.50_windows_amd64.bin",
        f"worker_v{major + 5}.0.0-rc.1_linux_arm64.bin": organized / f"{major + 5}.0/linux/arm64/worker_v{major + 5}.0.0-rc.1_linux_arm64.bin",
    }
    for filename, destination in destinations.items():
        assert destination.is_file(), f"Valid generated artifact was not moved correctly: {destination}"
        assert destination.read_bytes() == expected_valid[filename], f"Generated artifact content changed or was fabricated: {destination}"
        assert not (artifacts / filename).exists(), f"Valid generated artifact remains in source: {filename}"

    assert invalid_name is not None
    invalid_source = artifacts / invalid_name
    assert invalid_source.is_file(), "Checksum-invalid generated artifact should remain in the source directory"
    assert invalid_source.read_bytes() == invalid_payload, "Checksum-invalid generated artifact was altered"
    assert not list(organized.rglob(invalid_name)), "Checksum-invalid generated artifact was organized"

    highest = f"{major}.10.0"
    assert latest.is_file(), "latest_version.txt was not created during fresh execution"
    assert latest.read_text().strip() == highest, f"Expected generated highest stable version {highest}"

    mock_path = organized / f"{major}.10/darwin/arm64/mock_env.json"
    assert mock_path.is_file(), "mock_env.json was not created beside the generated highest stable artifact"
    with mock_path.open() as f:
        mock_data = json.load(f)
    assert mock_data == {"test_mode": True, "version": highest}, "Generated mock_env.json has incorrect content"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
