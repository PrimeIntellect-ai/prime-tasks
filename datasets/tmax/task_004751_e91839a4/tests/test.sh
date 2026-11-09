#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from decimal import Decimal

import pytest

WORKDIR = "/home/user/dataset_work"
PARSER = os.path.join(WORKDIR, "parser.go")
VALID_METADATA = os.path.join(WORKDIR, "extracted", "valid_metadata.txt")
RESULT = os.path.join(WORKDIR, "result.json")
BINARY = "/tmp/submitted_parser"


@pytest.fixture(scope="session", autouse=True)
def compile_parser():
    assert os.path.isfile(PARSER), f"Go program {PARSER} does not exist."
    subprocess.run(
        ["go", "build", "-o", BINARY, PARSER],
        cwd=WORKDIR,
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def run_parser():
    subprocess.run(
        [BINARY],
        cwd=WORKDIR,
        check=True,
        timeout=10,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_extracted_metadata_exists():
    path = "/home/user/dataset_work/extracted/metadata.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The archive was not extracted correctly."


def test_valid_metadata_txt():
    path = "/home/user/dataset_work/extracted/valid_metadata.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 valid lines, but found {len(lines)}."

    for line in lines:
        parts = line.split(",")
        assert len(parts) >= 2, f"Line does not appear to be CSV: {line}"
        assert parts[1] == "VALID", f"Expected Status to be 'VALID', got '{parts[1]}' in line: {line}"


def test_go_parser_exists():
    path = "/home/user/dataset_work/parser.go"
    assert os.path.isfile(path), f"Go program {path} does not exist."


def test_result_json():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    run_parser()

    path = "/home/user/dataset_work/result.json"
    assert os.path.isfile(path), f"Result file {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert "average_temperature" in data, "JSON does not contain 'average_temperature' key."
    assert data["average_temperature"] == 24.2, f"Expected average_temperature to be 24.2, got {data['average_temperature']}"


def test_parser_computes_average_from_input():
    original_metadata = open(VALID_METADATA, "rb").read()
    original_result = open(RESULT, "rb").read() if os.path.exists(RESULT) else None
    rng = secrets.SystemRandom()

    try:
        for case_number in range(2):
            while True:
                count = rng.randint(2, 7)
                temperatures = [rng.randint(-200, 500) for _ in range(count)]
                temperatures[-1] -= sum(temperatures) % count
                expected = float(Decimal(sum(temperatures)) / Decimal(count * 10))
                if expected != 24.2:
                    break

            with open(VALID_METADATA, "w") as f:
                for index, tenths in enumerate(temperatures, 1):
                    temperature = format(Decimal(tenths) / Decimal(10), ".1f")
                    f.write(f"{case_number * 100 + index},VALID,{temperature},data/{index}.dat\n")

            if os.path.exists(RESULT):
                os.remove(RESULT)
            run_parser()
            assert os.path.isfile(RESULT), "The Go program did not produce result.json."

            with open(RESULT, "r") as f:
                try:
                    data = json.load(f)
                except json.JSONDecodeError:
                    pytest.fail("The Go program produced invalid JSON for a generated input.")

            assert "average_temperature" in data, "JSON does not contain 'average_temperature' key."
            assert data["average_temperature"] == expected, (
                f"Expected average_temperature to be {expected}, got {data['average_temperature']}"
            )
    finally:
        with open(VALID_METADATA, "wb") as f:
            f.write(original_metadata)
        if original_result is None:
            if os.path.exists(RESULT):
                os.remove(RESULT)
        else:
            with open(RESULT, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
