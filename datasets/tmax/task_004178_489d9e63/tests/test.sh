#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_indexer"
AGENT_PATH = "/home/user/my_indexer"
PROJECT_DIR = "/home/user/legacy_project"
MANIFEST_PATH = "/home/user/project_manifest.txt"

def test_my_indexer_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Missing required executable: {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Expected a file at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"File {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    random.seed(42)

    for i in range(1000):
        length = random.randint(0, 512)
        content = bytearray(random.getrandbits(8) for _ in range(length))

        # 50% chance to start with magic bytes
        if length >= 4 and random.random() < 0.5:
            content[0:4] = b"LGCY"

        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp.write(content)
            tmp_path = tmp.name

        try:
            oracle = subprocess.run([ORACLE_PATH, tmp_path], capture_output=True)
            agent = subprocess.run([AGENT_PATH, tmp_path], capture_output=True)

            error_msg = (
                f"Mismatch on random input of length {length}.\n"
                f"Input Hex: {content.hex()[:100]}...\n"
                f"Oracle exit: {oracle.returncode}, Agent exit: {agent.returncode}\n"
                f"Oracle stdout: {oracle.stdout!r}\nAgent stdout: {agent.stdout!r}\n"
                f"Oracle stderr: {oracle.stderr!r}\nAgent stderr: {agent.stderr!r}"
            )

            assert oracle.returncode == agent.returncode, f"Exit code mismatch. {error_msg}"
            assert oracle.stdout == agent.stdout, f"STDOUT mismatch. {error_msg}"
            assert oracle.stderr == agent.stderr, f"STDERR mismatch. {error_msg}"
        finally:
            os.remove(tmp_path)

def test_manifest_contents():
    assert os.path.exists(MANIFEST_PATH), f"Missing manifest file: {MANIFEST_PATH}"

    expected_lines = set()
    for root, _, files in os.walk(PROJECT_DIR):
        for f in files:
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, PROJECT_DIR)
            rel_path_prefixed = f"./{rel_path}"

            oracle = subprocess.run([ORACLE_PATH, full_path], capture_output=True, text=True)
            if oracle.returncode == 0:
                expected_lines.add(f"{rel_path_prefixed}: {oracle.stdout.strip()}")

    with open(MANIFEST_PATH, "r") as f:
        actual_lines = set(line.strip() for line in f if line.strip())

    missing = expected_lines - actual_lines
    extra = actual_lines - expected_lines

    assert not missing, f"Manifest is missing expected lines: {list(missing)[:5]}"
    assert not extra, f"Manifest contains unexpected lines: {list(extra)[:5]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
