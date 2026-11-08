#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import struct
import subprocess

PROJECT = "/home/user/wal_processor"
WAL_PATH = "/home/user/wal.dat"
RESULT_PATH = "/home/user/result.txt"
BINARY_PATH = os.path.join(PROJECT, "target", "debug", "wal_processor")


def expected_from_wal(data):
    values = []
    for offset in range(0, len(data), 12):
        chunk = data[offset:offset + 12]
        if len(chunk) < 12:
            break
        _, value = struct.unpack("<Id", chunk)
        values.append(value)

    assert values, "No valid records found in WAL."
    mean = sum(values) / len(values)
    variance = sum((x - mean) ** 2 for x in values) / len(values)
    return f"{variance:.6f}"


def test_result_variance():
    wal_path = "/home/user/wal.dat"
    assert os.path.exists(wal_path), f"{wal_path} is missing."

    # Derive the expected truth dynamically from the WAL file
    with open(wal_path, "rb") as f:
        wal_data = f.read()
    expected_output = expected_from_wal(wal_data)

    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"{result_path} is missing. The service may not have run or failed to write output."

    with open(result_path, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, f"Variance mismatch. Expected {expected_output}, but got '{actual_output}'."


def test_cargo_toml_fixed():
    cargo_toml_path = "/home/user/wal_processor/Cargo.toml"
    assert os.path.exists(cargo_toml_path), f"{cargo_toml_path} is missing."
    with open(cargo_toml_path, "r") as f:
        content = f.read()
    assert "=1.0.9999" not in content, "Cargo.toml still contains the invalid 'anyhow' dependency version."


def test_cargo_config_fixed():
    config_path = "/home/user/wal_processor/.cargo/config.toml"
    if os.path.exists(config_path):
        with open(config_path, "r") as f:
            content = f.read()
        assert "--invalid-flag-that-breaks-build" not in content, "The .cargo/config.toml file still contains the invalid rustflag."


def run_service(wal_data):
    with open(WAL_PATH, "wb") as f:
        f.write(wal_data)
    if os.path.exists(RESULT_PATH):
        os.unlink(RESULT_PATH)

    completed = subprocess.run(
        [BINARY_PATH],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        "Built service failed while processing a WAL:\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(RESULT_PATH), "The executed service did not create /home/user/result.txt."
    with open(RESULT_PATH, "r") as f:
        actual = f.read().strip()
    expected = expected_from_wal(wal_data)
    assert actual == expected, f"Executed service produced '{actual}', expected '{expected}'."


def test_build_and_execute_service_on_stable_and_truncated_inputs():
    with open(WAL_PATH, "rb") as f:
        original_wal = f.read()
    original_result = None
    if os.path.exists(RESULT_PATH):
        with open(RESULT_PATH, "rb") as f:
            original_result = f.read()

    try:
        built = subprocess.run(
            ["cargo", "build"],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert built.returncode == 0, (
            "cargo build failed:\n"
            f"stdout:\n{built.stdout}\nstderr:\n{built.stderr}"
        )
        assert os.path.isfile(BINARY_PATH), "cargo build did not produce the wal_processor executable."
        mode = os.stat(BINARY_PATH).st_mode
        assert mode & stat.S_IXUSR, "The built wal_processor artifact is not executable."
        with open(BINARY_PATH, "rb") as f:
            assert f.read(4) == b"\x7fELF", "The built wal_processor artifact is not a native executable."

        # Re-run the actual artifact on the supplied WAL, so a fabricated result cannot pass.
        run_service(original_wal)

        # Exercise both stable variance computation and several incomplete trailing-record shapes.
        rng = secrets.SystemRandom()
        for suffix_length in (1, 4, 11):
            baseline = rng.randrange(90_000_000, 110_000_000)
            a, b = rng.sample(range(2, 24), 2)
            offsets = [-a, -b, 0, b, a]
            rng.shuffle(offsets)
            values = [baseline + offset / 8.0 for offset in offsets]

            records = bytearray()
            for index, value in enumerate(values, 1):
                records.extend(struct.pack("<Id", rng.randrange(1, 2**32), value))
            records.extend(os.urandom(suffix_length))
            run_service(bytes(records))
    finally:
        with open(WAL_PATH, "wb") as f:
            f.write(original_wal)
        if original_result is None:
            if os.path.exists(RESULT_PATH):
                os.unlink(RESULT_PATH)
        else:
            with open(RESULT_PATH, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
