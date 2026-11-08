#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import struct
import subprocess


def test_bad_commit_txt():
    """Verify that bad_commit.txt contains the correct commit hash."""
    repo_path = '/home/user/sensor_aggregator'
    bad_commit_file = '/home/user/bad_commit.txt'

    assert os.path.isfile(bad_commit_file), f"{bad_commit_file} is missing."

    result = subprocess.run(
        ['git', '-C', repo_path, 'log', '--grep=Add normalization based on variance', '--format=%H'],
        capture_output=True,
        text=True,
        check=True
    )
    expected_hash = result.stdout.strip()
    assert expected_hash, "Could not find the expected bad commit in the git repository."

    with open(bad_commit_file, 'r') as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"Expected commit hash {expected_hash}, but found {actual_hash} in {bad_commit_file}."


def test_poison_payload_txt():
    """Verify that poison_payload.txt contains the correct hex-encoded payload."""
    poison_file = '/home/user/poison_payload.txt'

    assert os.path.isfile(poison_file), f"{poison_file} is missing."

    expected_payload_bytes = struct.pack('<Iff', 2, 15.5, 15.5)
    expected_hex = expected_payload_bytes.hex()

    with open(poison_file, 'r') as f:
        actual_hex = f.read().strip().lower()

    assert actual_hex == expected_hex, f"Expected poison payload {expected_hex}, but found {actual_hex} in {poison_file}."


def run_fixed(fixed_script, payload):
    result = subprocess.run(
        ['python3', fixed_script, payload.hex()],
        capture_output=True,
        text=True,
        timeout=5
    )
    assert result.returncode == 0, (
        f"fixed_aggregate.py crashed for payload {payload.hex()}. Error: {result.stderr}"
    )
    output = result.stdout.strip()
    try:
        return float(output)
    except ValueError:
        assert False, f"fixed_aggregate.py produced invalid float output for payload {payload.hex()}: {output}"


def test_fixed_aggregate_py():
    """Verify the patch on captured and verifier-generated telemetry."""
    fixed_script = '/home/user/fixed_aggregate.py'
    assert os.path.isfile(fixed_script), f"{fixed_script} is missing."

    # Preserve the original captured poison-payload assertion.
    poison_payload = struct.pack('<Iff', 2, 15.5, 15.5)
    val_poison = run_fixed(fixed_script, poison_payload)
    assert math.isclose(val_poison, 0.0), (
        f"fixed_aggregate.py should output 0.0 for poison payload, got {val_poison}"
    )

    # Preserve the original captured normal-payload assertion.
    normal_payload = struct.pack('<Iff', 1, 10.0, 20.0)
    val_normal = run_fixed(fixed_script, normal_payload)
    assert math.isclose(val_normal, 3.0), (
        f"fixed_aggregate.py produced incorrect output for normal payload: {val_normal}"
    )

    # Exercise unpredictable zero-variance packets so a fixed lookup table cannot pass.
    for _ in range(16):
        sensor_id = secrets.randbits(32)
        value = secrets.randbelow(2000001) - 1000000
        payload = struct.pack('<Iff', sensor_id, float(value), float(value))
        actual = run_fixed(fixed_script, payload)
        assert math.isclose(actual, 0.0, abs_tol=0.0), (
            f"Expected 0.0 for zero-variance payload {payload.hex()}, got {actual}"
        )

    # Exercise unpredictable nonzero-variance packets and derive each answer independently.
    for _ in range(16):
        sensor_id = secrets.randbits(32)
        v1 = secrets.randbelow(20001) - 10000
        v2 = secrets.randbelow(20001) - 10000
        while v2 == v1:
            v2 = secrets.randbelow(20001) - 10000
        payload = struct.pack('<Iff', sensor_id, float(v1), float(v2))
        _, unpacked_v1, unpacked_v2 = struct.unpack('<Iff', payload)
        mean = (unpacked_v1 + unpacked_v2) / 2.0
        variance = ((unpacked_v1 - mean) ** 2 + (unpacked_v2 - mean) ** 2) / 2.0
        expected = mean / math.sqrt(variance)
        actual = run_fixed(fixed_script, payload)
        assert math.isclose(actual, expected, rel_tol=1e-7, abs_tol=1e-9), (
            f"Expected {expected} for payload {payload.hex()}, got {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
