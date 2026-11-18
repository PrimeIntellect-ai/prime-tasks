#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import stat
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_lb_gen"
AGENT_PATH = "/home/user/lb_gen"


def generate_random_ipv4():
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"


def generate_random_input():
    num_elements = random.randint(1, 20)
    elements = []
    for _ in range(num_elements):
        ip = generate_random_ipv4()
        port = random.randint(1, 65535)
        weight = random.randint(1, 100)
        elements.append(f"{ip}:{port}:{weight}")
    return ",".join(elements)


def test_agent_executable_exists():
    assert os.path.exists(AGENT_PATH), f"Agent program not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"
    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "Agent program must not be the legacy binary"
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), "Agent program must not be a copy of the legacy binary"


def test_fuzz_equivalence_without_oracle_available():
    random.seed(42)
    inputs = [generate_random_input() for _ in range(200)]

    expected_outputs = []
    for inp in inputs:
        try:
            oracle_res = subprocess.run([ORACLE_PATH, inp], capture_output=True, text=True, check=True)
            expected_outputs.append(oracle_res.stdout)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input '{inp}'. Stderr: {e.stderr}")

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    oracle_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)

    os.unlink(ORACLE_PATH)
    try:
        for i, (inp, oracle_output) in enumerate(zip(inputs, expected_outputs)):
            try:
                agent_res = subprocess.run([AGENT_PATH, inp], capture_output=True, text=True, check=True)
                agent_output = agent_res.stdout
            except subprocess.CalledProcessError as e:
                pytest.fail(f"Agent program failed on input '{inp}'. Stderr: {e.stderr}")

            assert agent_output == oracle_output, (
                f"Output mismatch on input {i+1}/200.\n"
                f"Input: {inp}\n\n"
                f"Expected (Oracle):\n{oracle_output}\n\n"
                f"Got (Agent):\n{agent_output}"
            )
    finally:
        fd, restore_path = tempfile.mkstemp(prefix="legacy_lb_gen.restore.", dir="/app")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(oracle_bytes)
            os.chmod(restore_path, oracle_mode)
            os.replace(restore_path, ORACLE_PATH)
        finally:
            if os.path.exists(restore_path):
                os.unlink(restore_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
