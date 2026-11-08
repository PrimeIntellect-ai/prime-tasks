#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess
import uuid
import pytest

ORACLE_PATH = "/app/bin/sensor_oracle"
AGENT_PATH = "/home/user/solution.sh"


def test_solution_exists():
    assert os.path.exists(AGENT_PATH), f"Solution script missing at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"


def generate_random_float32_hex(count=1000):
    inputs = []
    for _ in range(count):
        # Generate positive normalized float32 values, as in the original test.
        exp = secrets.randbelow(254) + 1
        mantissa = secrets.randbelow(0x800000)
        val = (exp << 23) | mantissa
        inputs.append(f"{val:08X}")
    return inputs


def find_reference_copies(reference):
    with open(reference, "rb") as f:
        reference_data = f.read()
    reference_hash = hashlib.sha256(reference_data).digest()
    matches = []

    # These are the locations writable by the task user where a copied oracle
    # could be stored and invoked after the original is hidden.
    for root in ("/home/user", "/tmp", "/var/tmp", "/dev/shm"):
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            for name in filenames:
                path = os.path.join(dirpath, name)
                try:
                    if not os.path.isfile(path) or os.path.islink(path):
                        continue
                    size = os.path.getsize(path)
                    if size < len(reference_data):
                        continue
                    with open(path, "rb") as f:
                        prefix = f.read(len(reference_data))
                    # Reject an exact copy and a copy with harmless trailing data.
                    if prefix == reference_data:
                        matches.append(path)
                    elif size == len(reference_data) and hashlib.sha256(prefix).digest() == reference_hash:
                        matches.append(path)
                except (OSError, PermissionError):
                    continue
    return matches


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"

    copied_oracles = find_reference_copies(ORACLE_PATH)
    assert not copied_oracles, "Submission contains a copied oracle binary: " + ", ".join(copied_oracles)

    inputs = generate_random_float32_hex(1000)
    input_data = "\n".join(inputs) + "\n"

    try:
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_output = oracle_proc.stdout.strip().split("\n")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Oracle failed to run: {e.stderr}")

    assert len(oracle_output) == len(inputs), (
        f"Oracle output length mismatch: expected {len(inputs)}, got {len(oracle_output)}"
    )

    # Make the legacy executable unavailable while the submitted replacement is
    # running. The randomized root-only name is not visible to the task user.
    hidden_oracle = f"/root/.sensor_oracle.verifier.{uuid.uuid4().hex}"
    os.replace(ORACLE_PATH, hidden_oracle)
    try:
        try:
            agent_proc = subprocess.run(
                ["/usr/sbin/runuser", "-u", "user", "--", "/bin/bash", AGENT_PATH],
                input=input_data,
                text=True,
                capture_output=True,
                check=True
            )
            agent_output = agent_proc.stdout.strip().split("\n")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed to run: {e.stderr}")
    finally:
        os.replace(hidden_oracle, ORACLE_PATH)

    assert len(agent_output) == len(inputs), (
        f"Agent output length mismatch: expected {len(inputs)}, got {len(agent_output)}"
    )

    for i in range(len(inputs)):
        assert oracle_output[i] == agent_output[i], (
            f"Mismatch on input {inputs[i]}:\n"
            f"Oracle output: {oracle_output[i]}\n"
            f"Agent output:  {agent_output[i]}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
