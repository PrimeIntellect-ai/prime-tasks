#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_payload_exists_and_works():
    payload_path = "/home/user/payload.bin"
    broker_path = "/app/sec_broker"

    assert os.path.exists(payload_path), f"Payload file not found at {payload_path}"
    assert os.path.exists(broker_path), f"Broker binary not found at {broker_path}"

    try:
        result = subprocess.run([broker_path, payload_path], capture_output=True, text=True, timeout=2)
    except subprocess.TimeoutExpired:
        pytest.fail("Execution of broker with payload timed out.")
    except Exception as e:
        pytest.fail(f"Execution of broker with payload failed: {e}")

    assert "FLAG{RBAC_BYPASS_SUCCESS}" in result.stdout, "The payload did not successfully exploit the broker to print the flag."

    size = os.path.getsize(payload_path)
    assert size <= 48, f"Payload size is {size} bytes, which exceeds the threshold of 48 bytes."

def test_exploit_generator_exists():
    gen_path = "/home/user/exploit_gen.c"
    assert os.path.exists(gen_path), f"Exploit generator source not found at {gen_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
