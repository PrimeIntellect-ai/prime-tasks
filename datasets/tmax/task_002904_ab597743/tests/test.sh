#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import tempfile
import stat

def test_libxxhash_compiled():
    so_path = "/app/vendored/xxhash-0.8.2/libxxhash.so"
    assert os.path.isfile(so_path), f"Compiled library not found at {so_path}"

def test_clean_paths():
    raw_path = "/home/user/raw_file_paths.txt"
    clean_path = "/home/user/clean_paths.txt"

    assert os.path.isfile(raw_path), f"Raw file missing: {raw_path}"
    assert os.path.isfile(clean_path), f"Cleaned file missing: {clean_path}"

    with open(raw_path, 'r') as f:
        raw_lines = f.readlines()

    expected_clean = []
    for line in raw_lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith('#'):
            continue
        expected_clean.append(stripped)

    with open(clean_path, 'r') as f:
        actual_clean = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_clean == expected_clean, "The cleaned paths do not match the expected output based on the rules."

def test_indexer_fuzz_equivalence():
    oracle_path = "/tests/indexer_oracle"
    agent_path = "/home/user/indexer.py"

    assert os.path.isfile(oracle_path), f"Test oracle missing: {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script missing: {agent_path}"
    st = os.stat(agent_path)
    assert st.st_mode & stat.S_IXUSR, f"Agent script is not executable: {agent_path}"

    with open(agent_path, 'r') as f:
        first_line = f.readline().strip()
    assert first_line == "#!/usr/bin/env python3", "Agent script missing correct shebang."

    random.seed(1337)
    N = 50

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N):
            # Vary file sizes from 0 to 1MB to keep tests fast but comprehensive
            size = random.randint(0, 1024 * 1024)
            if i < 5:
                # Explicitly test small files for the padding logic
                size = i

            test_file = os.path.join(tmpdir, f"test_file_{i}.bin")
            with open(test_file, "wb") as f:
                f.write(os.urandom(size))

            oracle_proc = subprocess.run([oracle_path, test_file], capture_output=True, text=True)
            agent_proc = subprocess.run([agent_path, test_file], capture_output=True, text=True)

            assert oracle_proc.returncode == 0, f"Test oracle failed on file size {size}: {oracle_proc.stderr}"
            assert agent_proc.returncode == 0, f"Agent script failed on file size {size} with error: {agent_proc.stderr}"

            oracle_out = oracle_proc.stdout.strip()
            agent_out = agent_proc.stdout.strip()

            assert agent_out == oracle_out, (
                f"Output mismatch on file size {size}.\n"
                f"Expected (Oracle): {oracle_out}\n"
                f"Got (Agent): {agent_out}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
