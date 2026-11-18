#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

def test_systemd_service_configured():
    service_path = Path("/home/user/.config/systemd/user/storage-sync.service")
    assert service_path.exists(), f"Service file missing: {service_path}"

    content = service_path.read_text()
    assert "After=ssh-tunnel.service" in content, "storage-sync.service is missing After=ssh-tunnel.service"
    assert "Requires=ssh-tunnel.service" in content, "storage-sync.service is missing Requires=ssh-tunnel.service"

def test_systemd_service_enabled_and_active():
    try:
        subprocess.run(
            ["systemctl", "--user", "is-enabled", "storage-sync.service"],
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"storage-sync.service is not enabled. Output: {e.stdout} {e.stderr}")

    try:
        subprocess.run(
            ["systemctl", "--user", "is-active", "storage-sync.service"],
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"storage-sync.service is not active. Output: {e.stdout} {e.stderr}")

def run_binary(binary_path: str, input_bytes: bytes) -> bytes:
    proc = subprocess.run(
        [binary_path],
        input=input_bytes,
        capture_output=True
    )
    return proc.stdout

def test_fuzz_equivalence():
    oracle_path = "/tests/path_sanitizer"
    agent_path = "/home/user/bin/path_sanitizer"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle not executable at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent binary missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary not executable at {agent_path}"

    char_set = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_/.!@#$%^&*()\n\t"
    random.seed(42)

    N = 10000
    inputs = []
    for _ in range(N):
        length = random.randint(0, 1024)
        input_str = "".join(random.choices(char_set, k=length))
        inputs.append(input_str.encode('utf-8'))

    for i, input_bytes in enumerate(inputs):
        oracle_out = run_binary(oracle_path, input_bytes)
        agent_out = run_binary(agent_path, input_bytes)

        if oracle_out != agent_out:
            input_repr = repr(input_bytes.decode('utf-8'))
            pytest.fail(
                f"Mismatch on input {input_repr}\n"
                f"Oracle output: {oracle_out!r}\n"
                f"Agent output:  {agent_out!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
