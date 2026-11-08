#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import socket
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/process_backup.py"
TARGET = "/home/user/archived_disk.qcow2"
SOURCE = "/tmp/raw_source.img"
EXPECTED_SIZE = 52428800


def file_digest(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def test_process_backup_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected Python script not found at {SCRIPT_PATH}"


def test_port_forwarding_active_and_correct():
    assert os.path.isfile(SOURCE), f"Raw source image not found at {SOURCE}"

    # Preserve the original assertion that the Gateway Port accepts connections,
    # then exercise that connection and verify the forwarded stream.
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(30)
    try:
        result = s.connect_ex(("127.0.0.1", 8111))
        assert result == 0, "No service listening on Gateway Port 8111. Port forwarding is not functional."

        received_hash = hashlib.sha256()
        received_size = 0
        while True:
            chunk = s.recv(1024 * 1024)
            if not chunk:
                break
            received_hash.update(chunk)
            received_size += len(chunk)
    finally:
        s.close()

    assert received_size == EXPECTED_SIZE, (
        f"Gateway returned {received_size} bytes; expected {EXPECTED_SIZE} bytes"
    )
    assert received_hash.hexdigest() == file_digest(SOURCE), (
        "Data received through Gateway Port 8111 does not match the raw backup served by internal storage"
    )


def test_process_backup_script_runs_and_creates_archive():
    # Remove any pre-created artifact so the demanded script must actually retrieve
    # and process the backup during verification.
    if os.path.lexists(TARGET):
        os.remove(TARGET)

    try:
        res = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", SCRIPT_PATH],
            cwd="/home/user",
            env={**os.environ, "HOME": "/home/user"},
            capture_output=True,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process_backup.py did not finish within 180 seconds")

    assert res.returncode == 0, (
        f"process_backup.py failed with exit code {res.returncode}. "
        f"stdout: {res.stdout}\nstderr: {res.stderr}"
    )
    assert os.path.exists(TARGET), f"Archived disk file not created at {TARGET}"


def test_archived_disk_qcow2_valid_compressed_and_matches_source():
    assert os.path.exists(TARGET), f"Archived disk file not found at {TARGET}"

    # Verify it is a valid qcow2 file.
    res = subprocess.run(
        ["qemu-img", "info", "--output=json", TARGET],
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"qemu-img info failed on {TARGET}. Output: {res.stderr}"

    try:
        info = json.loads(res.stdout)
    except json.JSONDecodeError:
        pytest.fail("Failed to parse JSON output from qemu-img info")

    assert info.get("format") == "qcow2", f"Expected format 'qcow2', but got {info.get('format')}"

    actual_virtual_size = info.get("virtual-size")
    assert actual_virtual_size == EXPECTED_SIZE, (
        f"Incorrect virtual size: expected {EXPECTED_SIZE}, got {actual_virtual_size}"
    )

    # The archive must be self-contained rather than referring back to the source.
    assert not info.get("backing-filename") and not info.get("full-backing-filename"), (
        "Archived QCOW2 must not depend on a backing file"
    )
    assert not info.get("data-file"), "Archived QCOW2 must not depend on an external data file"

    # Check physical file size for compression metric.
    file_size = os.path.getsize(TARGET)
    threshold = 2500000
    assert file_size <= threshold, (
        f"Compression metric failed: file size {file_size} bytes is not <= {threshold} bytes. "
        "Did you use the compression flag?"
    )

    # Materialize the represented disk and compare its complete contents with the
    # source image, including zero-filled regions and isolated data blocks.
    with tempfile.TemporaryDirectory(prefix="verify-qcow2-") as tmpdir:
        converted = os.path.join(tmpdir, "archive.raw")
        conv = subprocess.run(
            ["qemu-img", "convert", "-f", "qcow2", "-O", "raw", TARGET, converted],
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert conv.returncode == 0, (
            f"Failed to read QCOW2 contents. stdout: {conv.stdout}\nstderr: {conv.stderr}"
        )
        assert os.path.getsize(converted) == EXPECTED_SIZE, "Converted archive has an incorrect size"
        assert file_digest(converted) == file_digest(SOURCE), (
            "Archived QCOW2 does not represent the original raw disk image"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
