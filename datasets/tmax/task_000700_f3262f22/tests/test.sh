#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import subprocess
import pytest

def test_recovered_password():
    path = "/home/user/recovered_password.txt"
    assert os.path.isfile(path), f"Missing recovered password file at {path}"
    with open(path, "r") as f:
        password = f.read().strip()
    assert password == "KiloTangowxyz", f"Incorrect recovered password. Expected 'KiloTangowxyz', got '{password}'"

def test_rotation_success_log():
    path = "/home/user/rotation_success.log"
    assert os.path.isfile(path), f"Missing rotation success log at {path}"
    with open(path, "r") as f:
        log_content = f.read()
    assert "Success" in log_content, f"Rotation success log does not contain 'Success'. Content: {log_content}"

def test_cracker_performance():
    cracker_path = "/home/user/cracker"
    assert os.path.isfile(cracker_path), f"Missing compiled cracker binary at {cracker_path}"
    assert os.access(cracker_path, os.X_OK), f"Cracker binary at {cracker_path} is not executable"

    start = time.time()
    try:
        subprocess.run([cracker_path], check=True, capture_output=True, timeout=5.0)
    except subprocess.TimeoutExpired:
        pytest.fail("Cracker execution timed out after 5 seconds. It must run in under 1.5 seconds.")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Cracker execution failed with return code {e.returncode}. Stderr: {e.stderr.decode()}")

    elapsed = time.time() - start
    threshold = 1.5
    assert elapsed <= threshold, f"Cracker execution time {elapsed:.3f}s exceeded threshold of {threshold}s"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
