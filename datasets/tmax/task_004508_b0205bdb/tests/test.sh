#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
from decimal import Decimal

import pytest

BASE_DIR = "/home/user/log_processor"
EXECUTABLE = os.path.join(BASE_DIR, "processor")
CANONICAL_INPUT = "/home/user/requests.csv"
CANONICAL_OUTPUT = "/home/user/processed.csv"


@pytest.fixture(scope="session", autouse=True)
def build_and_run_canonical():
    clean = subprocess.run(
        ["make", "clean"], cwd=BASE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}"

    build = subprocess.run(
        ["make"], cwd=BASE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert build.returncode == 0, f"Project failed to build with make:\n{build.stdout}"
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found after make."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "processor is not a compiled ELF executable."

    run = subprocess.run(
        [EXECUTABLE, CANONICAL_INPUT, CANONICAL_OUTPUT],
        cwd=BASE_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert run.returncode == 0, f"processor failed on requests.csv:\n{run.stdout}"


def test_circular_dependency_fixed():
    """Verify that the circular inclusion dependency has been resolved."""
    parser_h = os.path.join(BASE_DIR, "parser.h")
    validator_h = os.path.join(BASE_DIR, "validator.h")

    assert os.path.isfile(parser_h), f"Missing {parser_h}"
    assert os.path.isfile(validator_h), f"Missing {validator_h}"

    with open(parser_h, "r") as f:
        p_content = f.read()
    with open(validator_h, "r") as f:
        v_content = f.read()

    p_includes_v = '#include "validator.h"' in p_content
    v_includes_p = '#include "parser.h"' in v_content

    assert not (p_includes_v and v_includes_p), (
        "Circular dependency still exists: parser.h and validator.h mutually include each other. "
        "Use forward declarations to break the cycle."
    )


def test_executable_exists():
    """Verify that the project was successfully compiled."""
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found. Did you run 'make'?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_processed_csv_output():
    """Verify the required run produced the complete canonical output."""
    assert os.path.isfile(CANONICAL_OUTPUT), (
        f"Output file {CANONICAL_OUTPUT} not found. Did you run the processor?"
    )

    expected_statuses = [
        "OK",
        "OK",
        "OK",
        "RATE_LIMITED",
        "RATE_LIMITED",
        "OK",
        "INVALID_CHECKSUM",
        "RATE_LIMITED",
    ]

    with open(CANONICAL_INPUT, newline="") as f:
        input_rows = list(csv.reader(f))
    with open(CANONICAL_OUTPUT, newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) == len(expected_statuses), (
        f"Expected {len(expected_statuses)} rows in output, but found {len(rows)}."
    )

    for i, (row, source, expected_status) in enumerate(
        zip(rows, input_rows, expected_statuses)
    ):
        assert len(row) >= 5, f"Row {i+1} does not have the expected 5 columns."
        assert len(row) == 5, f"Row {i+1} must contain exactly 5 columns."
        assert Decimal(row[0]) == Decimal(source[0]), f"Row {i+1} timestamp was changed."
        assert row[1:4] == source[1:4], f"Row {i+1} input fields were changed."
        actual_status = row[4].strip()
        assert actual_status == expected_status, (
            f"Row {i+1}: expected status '{expected_status}', but got '{actual_status}'."
        )


def xor_checksum(payload):
    value = 0
    for i in range(0, len(payload), 2):
        value ^= int(payload[i:i+2], 16)
    return value


def expected_rows(input_rows):
    history = {}
    result = []
    for row in input_rows:
        timestamp_us = int(Decimal(row[0]) * 1000000)
        user = row[1]
        payload = row[2]
        supplied = int(row[3], 16)
        previous = history.setdefault(user, [])
        count = sum(
            1 for old_us in previous
            if timestamp_us - 1000000 < old_us <= timestamp_us
        )
        if xor_checksum(payload) != supplied:
            status = "INVALID_CHECKSUM"
        elif count >= 3:
            status = "RATE_LIMITED"
        else:
            status = "OK"
        previous.append(timestamp_us)
        result.append((row, status))
    return result


def test_processor_on_fresh_unpredictable_input(tmp_path):
    """Execute the submitted processor and independently derive every output field."""
    rng = random.Random(secrets.randbits(128))
    base_us = rng.randint(100, 100000) * 1000000
    token = secrets.token_hex(8)
    burst_user = "burst_" + token
    boundary_user = "boundary_" + token

    def make_row(offset_us, user, payload, valid=True):
        checksum = xor_checksum(payload)
        if not valid:
            checksum ^= rng.randint(1, 255)
        timestamp = Decimal(base_us + offset_us) / Decimal(1000000)
        payload_text = payload.upper() if rng.choice([True, False]) else payload.lower()
        checksum_text = f"{checksum:02X}" if rng.choice([True, False]) else f"{checksum:02x}"
        return [f"{timestamp:.6f}", user, payload_text, checksum_text]

    rows = [
        make_row(0, burst_user, "010203", False),
        make_row(100000, burst_user, "a1b2c3", True),
        make_row(200000, burst_user, "ff01", False),
        make_row(300000, burst_user, "1020", True),
        make_row(400000, burst_user, "11223344", True),
        make_row(500000, burst_user, "abcdef", False),
        make_row(0, boundary_user, "01", True),
        make_row(200000, boundary_user, "02", True),
        make_row(400000, boundary_user, "04", True),
        make_row(1000000, boundary_user, "08", True),
    ]

    random_users = ["random_" + token + "_" + str(i) for i in range(4)]
    current_us = 2000000
    for _ in range(80):
        current_us += rng.randint(0, 650000)
        user = rng.choice(random_users)
        payload = bytes(rng.randrange(256) for _ in range(rng.randint(1, 10))).hex()
        rows.append(make_row(current_us, user, payload, rng.random() < 0.7))

    rows.sort(key=lambda row: Decimal(row[0]))
    oracle = expected_rows(rows)
    statuses = [status for _, status in oracle]
    assert "OK" in statuses
    assert "INVALID_CHECKSUM" in statuses
    assert "RATE_LIMITED" in statuses

    boundary_time = Decimal(base_us + 1000000) / Decimal(1000000)
    boundary_matches = [
        status for row, status in oracle
        if row[1] == boundary_user and Decimal(row[0]) == boundary_time
    ]
    assert boundary_matches == ["OK"], "Internal boundary test construction failed."

    input_path = tmp_path / "generated.csv"
    output_path = tmp_path / "generated-output.csv"
    with open(input_path, "w", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)
    output_path.write_text("stale,fabricated,output,must,disappear\n")

    run = subprocess.run(
        [EXECUTABLE, str(input_path), str(output_path)],
        cwd=BASE_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert run.returncode == 0, f"processor failed on generated input:\n{run.stdout}"
    assert output_path.is_file(), "processor did not create its requested output file."

    with open(output_path, newline="") as f:
        actual = list(csv.reader(f))
    assert len(actual) == len(oracle), (
        f"Generated run expected {len(oracle)} rows, got {len(actual)}."
    )

    for index, (out_row, (source, status)) in enumerate(zip(actual, oracle), 1):
        assert len(out_row) == 5, f"Generated output row {index} must have exactly 5 columns."
        assert Decimal(out_row[0]) == Decimal(source[0]), (
            f"Generated output row {index} has the wrong timestamp."
        )
        assert out_row[1:4] == source[1:4], (
            f"Generated output row {index} did not preserve the input fields."
        )
        assert out_row[4] == status, (
            f"Generated output row {index}: expected {status}, got {out_row[4]}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
