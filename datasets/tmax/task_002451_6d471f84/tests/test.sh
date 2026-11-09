#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import json
import gzip
import tempfile
import pytest

ORACLE_PATH = "/tests/process_archive_oracle.sh"
AGENT_PATH = "/home/user/process_archive.sh"
UNARCHIVE_SCRIPT = "/app/log-archiver-1.0/bin/unarchive.sh"

def generate_archive(filepath):
    """Generate a valid custom backup archive file."""
    metadata_len = random.randint(20, 200)
    key_len = max(1, metadata_len - 20)
    metadata = json.dumps({"meta": "".join(random.choices(string.ascii_letters, k=key_len))})
    metadata_bytes = metadata.encode('utf-8')

    num_logs = random.randint(1, 100)
    severities = ["INFO", "WARN", "ERROR", "DEBUG"]
    log_data = ""
    for _ in range(num_logs):
        sev = random.choice(severities)
        msg_len = random.randint(10, 500)
        msg_chars = random.choices(string.ascii_letters + " \n.,!?", k=msg_len)
        msg = "".join(msg_chars).replace("[20", "x20")
        year = random.randint(2020, 2023)
        month = f"{random.randint(1, 12):02d}"
        day = f"{random.randint(1, 28):02d}"
        hour = f"{random.randint(0, 23):02d}"
        minute = f"{random.randint(0, 59):02d}"
        second = f"{random.randint(0, 59):02d}"
        log_data += f"[{year}-{month}-{day} {hour}:{minute}:{second}] [{sev}] {msg}\n"

    gzipped_log = gzip.compress(log_data.encode('utf-8'))
    with open(filepath, 'wb') as f:
        header_hex = f"{len(metadata_bytes):08X}".encode('ascii')
        f.write(header_hex + b"\n")
        f.write(metadata_bytes)
        f.write(gzipped_log)

def test_unarchive_bug_fixed():
    """Verify that unarchive.sh is executable and actually decompresses gzip data."""
    assert os.path.exists(UNARCHIVE_SCRIPT), f"{UNARCHIVE_SCRIPT} is missing."
    assert os.access(UNARCHIVE_SCRIPT, os.X_OK), f"{UNARCHIVE_SCRIPT} must be executable."
    payload = b"unarchive functional check\nwith a second line\n"
    with tempfile.TemporaryDirectory() as tmpdir:
        gz_path = os.path.join(tmpdir, "sample.gz")
        with gzip.open(gz_path, "wb") as f:
            f.write(payload)
        proc = subprocess.run([UNARCHIVE_SCRIPT, gz_path], capture_output=True)
        assert proc.returncode == 0, f"unarchive.sh failed: {proc.stderr.decode(errors='replace')}"
        assert proc.stdout == payload, "unarchive.sh did not correctly decompress gzip input"

def test_fuzz_equivalence():
    """Fuzz test the agent's script against the isolated oracle."""
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable. Run chmod +x."

    random.seed(1337)
    severities = ["INFO", "WARN", "ERROR", "DEBUG"]
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(500):
            archive_path = os.path.join(tmpdir, f"archive_{i}.bin")
            generate_archive(archive_path)
            target_sev = random.choice(severities)
            oracle_proc = subprocess.run([ORACLE_PATH, archive_path, target_sev], capture_output=True)
            agent_proc = subprocess.run([AGENT_PATH, archive_path, target_sev], capture_output=True)
            if agent_proc.returncode != oracle_proc.returncode:
                pytest.fail(f"Return code mismatch on input {i} (Severity: {target_sev}).\n"
                            f"Oracle exited with {oracle_proc.returncode}, Agent exited with {agent_proc.returncode}.\n"
                            f"Agent stderr: {agent_proc.stderr.decode(errors='replace')}")
            if agent_proc.stdout != oracle_proc.stdout:
                pytest.fail(f"Output mismatch on input {i} (Severity: {target_sev}).\n"
                            f"Expected {len(oracle_proc.stdout)} bytes, got {len(agent_proc.stdout)} bytes.\n"
                            f"Agent stderr: {agent_proc.stderr.decode(errors='replace')}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
