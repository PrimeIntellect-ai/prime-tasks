#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import string
import subprocess
import urllib.request
import urllib.error
import pytest

def test_service_integration():
    """Test that Nginx routes to Flask and Flask connects to Redis."""
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/api/health")
        with urllib.request.urlopen(req, timeout=5) as response:
            data = response.read().decode('utf-8').strip()
            try:
                parsed = json.loads(data)
                assert parsed == {"status": "ok", "redis": "connected"}, f"Unexpected JSON response: {parsed}"
            except json.JSONDecodeError:
                pytest.fail(f"Response was not valid JSON: {data}")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx/Flask API: {e}")

def create_fuzz_dir(base_path, seed):
    """Generate a random directory structure with files and symlinks."""
    random.seed(seed)
    os.makedirs(base_path, exist_ok=True)

    dirs = [base_path]
    # Create directories (depth up to 5 implied by random parent selection)
    for _ in range(random.randint(5, 15)):
        parent = random.choice(dirs)
        new_dir = os.path.join(parent, ''.join(random.choices(string.ascii_lowercase, k=5)))
        os.makedirs(new_dir, exist_ok=True)
        dirs.append(new_dir)

    # Create files
    exts = ['.conf', '.yaml', '.txt', '.log', '.bak']
    for d in dirs:
        for _ in range(random.randint(0, 10)):
            ext = random.choice(exts)
            fname = ''.join(random.choices(string.ascii_lowercase, k=8)) + ext
            fpath = os.path.join(d, fname)
            with open(fpath, 'wb') as f:
                # Random bytes to ensure zlib compression has varying results
                f.write(os.urandom(random.randint(0, 10240)))

    # Create symlinks (1 to 5), some potentially cyclic
    for _ in range(random.randint(1, 5)):
        src = random.choice(dirs)
        dst_dir = random.choice(dirs)
        link_name = os.path.join(dst_dir, 'symlink_' + ''.join(random.choices(string.ascii_lowercase, k=5)))
        if not os.path.exists(link_name):
            os.symlink(src, link_name)

def test_archiver_fuzz_equivalence():
    """Fuzz test the agent's archiver against the reference oracle."""
    agent_script = "/home/user/archiver.py"
    oracle_bin = "/tests/reference_archiver"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"

    fuzz_base = "/tmp/fuzz_dirs"
    os.makedirs(fuzz_base, exist_ok=True)

    for i in range(50):
        test_dir = os.path.join(fuzz_base, f"test_case_{i}")
        create_fuzz_dir(test_dir, seed=i)

        oracle_proc = subprocess.run(["python3", oracle_bin, test_dir], capture_output=True)
        agent_proc = subprocess.run(["python3", agent_script, test_dir], capture_output=True)

        if oracle_proc.returncode != 0:
            # If oracle fails, skip or fail depending on expectations, but oracle should handle it.
            pass

        assert agent_proc.returncode == 0, (
            f"Agent script failed on {test_dir}.\n"
            f"Stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
        )

        if agent_proc.stdout != oracle_proc.stdout:
            pytest.fail(
                f"Output mismatch on directory {test_dir} (seed {i}).\n"
                f"Oracle output length: {len(oracle_proc.stdout)} bytes\n"
                f"Agent output length: {len(agent_proc.stdout)} bytes"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
