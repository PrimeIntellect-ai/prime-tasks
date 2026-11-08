#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import pytest

PIPELINE = "/home/user/pipeline.sh"
ORACLE = "/app/bin/oracle_cleaner"


def generate_fuzz_data(num_records):
    rng = secrets.SystemRandom()
    records = [
        "0,0,0",
        "0,0,",
        "0007,0008,0009",
        "999999,1000,",
        "1,2,3,4",
        "-1,2,3",
        "+1,2,3",
        "1, 2,3",
        "1,2",
        "1,2,A",
        "",
    ]
    for _ in range(num_records):
        choice = rng.random()
        if choice < 0.35:
            records.append(f"{rng.randrange(0, 1000001)},{rng.randrange(0, 1001)},{rng.randrange(0, 1001)}")
        elif choice < 0.65:
            records.append(f"{rng.randrange(0, 1000001)},{rng.randrange(0, 1001)},")
        elif choice < 0.73:
            records.append(f"{rng.randrange(0, 101)},{rng.randrange(0, 101)}A,{rng.randrange(0, 101)}")
        elif choice < 0.80:
            records.append(f"{rng.randrange(0, 101)}{rng.randrange(0, 101)}")
        elif choice < 0.87:
            records.append(f"{rng.randrange(0, 101)},{rng.randrange(0, 101)},{rng.randrange(0, 101)},{rng.randrange(0, 101)}")
        elif choice < 0.94:
            records.append(f"{rng.randrange(0, 101)},\n{rng.randrange(0, 101)},\r{rng.randrange(0, 101)}")
        else:
            records.append(f"{rng.randrange(0, 101)}, {rng.randrange(0, 101)},{rng.randrange(0, 101)}")
    return "\n".join(records) + "\n"


def expected_output(input_data):
    valid = re.compile(r"^([0-9]+),([0-9]+),([0-9]*)$")
    output = []
    for row in input_data.split("\n"):
        match = valid.fullmatch(row)
        if not match:
            continue
        sensor_id = int(match.group(1))
        temp_a = int(match.group(2))
        temp_b = int(match.group(3)) if match.group(3) else temp_a * 3 + 7
        new_id = (sensor_id * 137) % 1000
        output.append(f"[{new_id}] => {{{temp_a}, {temp_b}}}\n")
    return "".join(output)


def test_pipeline_exists_and_executable():
    assert os.path.isfile(PIPELINE), f"Pipeline script not found at {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"Pipeline script at {PIPELINE} is not executable"
    with open(PIPELINE, "rb") as f:
        first_line = f.readline(256)
    assert first_line.startswith(b"#!/bin/bash") or first_line.startswith(b"#!/usr/bin/env bash"), \
        "pipeline.sh must be an executable Bash script"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f"Oracle binary not found at {ORACLE}"

    with open(ORACLE, "rb") as f:
        oracle_bytes = f.read()
    with open(PIPELINE, "rb") as f:
        pipeline_bytes = f.read()
    assert pipeline_bytes != oracle_bytes, "pipeline.sh must not be a byte-identical copy of the reference"

    input_data = generate_fuzz_data(10000)
    expected = expected_output(input_data)

    try:
        oracle_process = subprocess.run(
            [ORACLE], input=input_data, text=True, capture_output=True,
            check=True, timeout=10
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Oracle binary failed with exit code {e.returncode}. Stderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Oracle binary timed out.")

    assert oracle_process.stdout == expected, "Reference output disagrees with independently derived expected output"

    oracle_mode = stat.S_IMODE(os.stat(ORACLE).st_mode)
    os.unlink(ORACLE)
    try:
        try:
            pipeline_process = subprocess.run(
                [PIPELINE], input=input_data, text=True, capture_output=True,
                check=False, timeout=10
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Pipeline script timed out.")

        assert pipeline_process.returncode == 0, \
            f"Pipeline script failed with exit code {pipeline_process.returncode}. Stderr: {pipeline_process.stderr}"
        assert pipeline_process.stdout == oracle_process.stdout, "Pipeline output does not match the reference output"
        assert pipeline_process.stdout == expected, "Pipeline output does not match independently derived expected output"
    finally:
        if os.path.lexists(ORACLE):
            if os.path.isdir(ORACLE) and not os.path.islink(ORACLE):
                shutil.rmtree(ORACLE)
            else:
                os.unlink(ORACLE)
        with open(ORACLE, "wb") as f:
            f.write(oracle_bytes)
        os.chmod(ORACLE, oracle_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
