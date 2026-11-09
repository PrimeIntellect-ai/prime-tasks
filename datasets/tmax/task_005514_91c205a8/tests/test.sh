#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

TARGET_FILE = "/home/user/recovered_token.txt"


def find_original_worker():
    candidates = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\x00", b" ")
            if b"legacy_worker.sh" not in cmdline:
                continue

            fd_path = f"/proc/{entry}/fd/4"
            if "(deleted)" not in os.readlink(fd_path):
                continue

            with open(f"/proc/{entry}/stat", "r") as f:
                start_time = int(f.read().split()[21])
            with open(fd_path, "rb") as f:
                token = f.read().decode("utf-8").strip()

            if token:
                candidates.append((start_time, int(entry), token))
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError, UnicodeDecodeError, IndexError, ValueError):
            continue

    assert candidates, "Could not find the running legacy_worker.sh process with its deleted token file open."
    return min(candidates, key=lambda item: item[0])


def test_recovered_token_file_exists():
    assert os.path.exists(TARGET_FILE), f"Verification failed: {TARGET_FILE} does not exist."
    assert os.path.isfile(TARGET_FILE), f"Verification failed: {TARGET_FILE} is not a regular file."


def test_recovered_token_content():
    assert os.path.exists(TARGET_FILE), f"Cannot check content, {TARGET_FILE} is missing."
    _, _, expected_token = find_original_worker()
    with open(TARGET_FILE, "r") as f:
        content = f.read().strip()
    assert content == expected_token, f"Verification failed: Incorrect recovered token '{content}'."


def test_legacy_worker_still_running():
    try:
        output = subprocess.check_output(["pgrep", "-f", "legacy_worker.sh"], text=True)
        pids = output.strip().split("\n")
        assert len(pids) >= 1, "legacy_worker.sh process is no longer running. It should not have been killed."
        find_original_worker()
    except subprocess.CalledProcessError:
        pytest.fail("legacy_worker.sh process is no longer running (pgrep returned no matches). It should not have been killed.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
