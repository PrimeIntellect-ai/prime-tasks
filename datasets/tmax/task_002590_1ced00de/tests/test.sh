#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import math
import os
import random
import struct
import subprocess
import pytest


def load_strict_json(output, source):
    try:
        value = json.loads(
            output,
            parse_constant=lambda token: (_ for _ in ()).throw(
                ValueError(f"non-standard JSON constant {token}")
            ),
        )
    except (json.JSONDecodeError, ValueError) as exc:
        pytest.fail(f"{source} did not output valid strict JSON: {exc}")
    assert isinstance(value, dict), f"{source} output must be a JSON object."
    return value


def test_rust_binary_matches_legacy():
    rust_bin = "/home/user/sensor_aggregator/target/release/sensor_aggregator"
    assert os.path.exists(rust_bin), f"Rust binary not found at {rust_bin}. Did you run 'cargo build --release'?"
    assert os.path.isfile(rust_bin), f"Rust binary is not a regular file: {rust_bin}"
    assert os.access(rust_bin, os.X_OK), f"Rust binary is not executable: {rust_bin}"

    legacy_bin = "/app/legacy_calc"
    assert os.path.exists(legacy_bin), f"Legacy binary missing at {legacy_bin}"
    assert not filecmp.cmp(rust_bin, legacy_bin, shallow=False), "Submitted binary must not be byte-identical to the legacy binary."

    test_file = "/tmp/test_data.bin"

    # Generate unpredictable test data: 500,000 records to expose concurrency and precision issues.
    rng = random.SystemRandom()
    with open(test_file, "wb") as f:
        # Ensure every expected sensor is represented while keeping sums unpredictable.
        for sensor_id in range(1, 51):
            reading = rng.uniform(-10000.0, 10000.0)
            f.write(struct.pack("<Id", sensor_id, reading))
        for _ in range(500000 - 50):
            sensor_id = rng.randint(1, 50)
            reading = rng.uniform(-10000.0, 10000.0)
            f.write(struct.pack("<Id", sensor_id, reading))

    # Run legacy binary.
    try:
        with open(test_file, "rb") as f:
            legacy_proc = subprocess.run(
                [legacy_bin],
                stdin=f,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=True,
            )
        legacy_out = load_strict_json(legacy_proc.stdout, "Legacy binary")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Legacy binary failed to run: {e.stderr}")

    # Run submitted Rust binary.
    try:
        rust_proc = subprocess.run(
            [rust_bin, test_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        rust_out = load_strict_json(rust_proc.stdout, "Rust binary")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Rust binary failed to run: {e.stderr}")

    # Submitted values must be genuine finite JSON numbers; NaN/Infinity must not
    # be able to bypass the error calculation.
    for key, value in rust_out.items():
        assert isinstance(key, str), f"Output key {key!r} is not a string."
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"Output value for sensor {key!r} is not numeric."
        assert math.isfinite(float(value)), \
            f"Output value for sensor {key!r} is not finite."

    # Calculate MAE.
    mae = 0.0
    for k in legacy_out.keys():
        ref_val = legacy_out[k]
        hyp_val = rust_out.get(k, 0.0)
        mae = max(mae, abs(ref_val - hyp_val))

    # Also check if rust output has extra keys.
    for k in rust_out.keys():
        if k not in legacy_out:
            ref_val = 0.0
            hyp_val = rust_out[k]
            mae = max(mae, abs(ref_val - hyp_val))

    threshold = 1e-8
    assert mae < threshold, f"Maximum Absolute Error {mae} is >= {threshold}. The Rust implementation's output does not match the legacy binary closely enough."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
