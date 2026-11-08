#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

ORACLE_PATH = "/app/bin/wal_tracker"
AGENT_PATH = "/home/user/my_tracker"
NUM_TESTS = 200


def generate_fuzz_input(seed):
    random.seed(seed)
    length = random.randint(0, 1024)

    # 10% chance of having a non-multiple of 8 trailing bytes
    if random.random() >= 0.1:
        length = (length // 8) * 8

    data = bytearray()
    for i in range(length):
        if i % 8 == 0:
            # 80% chance of op_type being 0x01, 0x02, or 0x03
            if random.random() < 0.8:
                data.append(random.choice([0x01, 0x02, 0x03]))
            else:
                data.append(random.randint(0, 255))
        else:
            data.append(random.randint(0, 255))

    return bytes(data)


def derive_expected(data):
    volumes = [0] * 256
    output = bytearray()

    for offset in range(0, len(data) - 7, 8):
        record = data[offset:offset + 8]
        op_type = record[0]
        vol_id = record[1]
        blocks = int.from_bytes(record[4:8], "little")

        if op_type == 1:
            volumes[vol_id] = (volumes[vol_id] + blocks) & 0xffffffff
        elif op_type == 2:
            if volumes[vol_id] < blocks:
                volumes[vol_id] = 0
            else:
                volumes[vol_id] -= blocks
        elif op_type == 3:
            volumes[vol_id] = blocks
        else:
            output.extend(f"ERR: Unknown OP {op_type:02x}\n".encode())
            return 1, bytes(output)

        output.extend(f"VOL {vol_id}: {volumes[vol_id]}\n".encode())

    return 0, bytes(output)


@pytest.fixture(scope="session")
def fuzz_cases():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.isfile(ORACLE_PATH), f"{ORACLE_PATH} is not a file"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} is not executable"

    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable"

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent submission is byte-identical to the oracle"

    cases = []
    for i in range(NUM_TESTS):
        input_data = generate_fuzz_input(seed=42 + i)
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            capture_output=True
        )

        derived_code, derived_stdout = derive_expected(input_data)
        assert oracle_proc.returncode == derived_code
        assert oracle_proc.stdout == derived_stdout
        cases.append((i, input_data, oracle_proc.returncode, oracle_proc.stdout))

    # The oracle was intentionally available for reverse engineering, but must not
    # remain callable by a submission while the submission is under test.
    os.remove(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH)
    return cases


def test_agent_binary_exists(fuzz_cases):
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable"


def test_fuzz_equivalence(fuzz_cases):
    assert not os.path.exists(ORACLE_PATH), "Oracle must be unavailable while testing the agent"

    for i, input_data, oracle_returncode, oracle_stdout in fuzz_cases:
        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            capture_output=True
        )

        assert agent_proc.returncode == oracle_returncode, (
            f"Exit code mismatch on test {i} (seed {42+i}).\n"
            f"Input length: {len(input_data)} bytes\n"
            f"Oracle exit code: {oracle_returncode}\n"
            f"Agent exit code: {agent_proc.returncode}\n"
            f"Oracle stdout: {oracle_stdout!r}\n"
            f"Agent stdout: {agent_proc.stdout!r}\n"
        )

        assert agent_proc.stdout == oracle_stdout, (
            f"Stdout mismatch on test {i} (seed {42+i}).\n"
            f"Input length: {len(input_data)} bytes\n"
            f"Oracle stdout: {oracle_stdout!r}\n"
            f"Agent stdout: {agent_proc.stdout!r}\n"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
