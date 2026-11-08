#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from collections import Counter

import pytest

GO_FILE = "/home/user/processor.go"
INPUT_FILE = "/home/user/input.dat"
SCRIPT_PATH = "/home/user/e2e_test.py"
REPORT_PATH = "/home/user/test_report.json"


def run_go(timeout=5):
    try:
        return subprocess.run(
            ["go", "run", GO_FILE],
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Go program timed out after {timeout} seconds. The deadlock is likely not fixed.")


def assert_output_contains_exact_records(output, records):
    assert len(output) == sum(len(record) + 1 for record in records), (
        "Go output length does not match the input records"
    )
    assert output.count(b"\n") == len(records), "Go output has the wrong number of newlines"
    for record, expected_count in Counter(records).items():
        assert output.count(record) == expected_count, (
            f"Go output did not contain record {record!r} exactly {expected_count} time(s)"
        )


def test_go_program_fixed():
    """Verify that the Go program runs, processes input.dat, and does not deadlock."""
    assert os.path.isfile(GO_FILE), f"{GO_FILE} does not exist."

    result = run_go()
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}.\n"
        f"Stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )

    with open(INPUT_FILE, "rb") as f:
        records = f.read().splitlines()
    assert_output_contains_exact_records(result.stdout, records)


def test_e2e_script_exists_and_runs():
    """Verify that the Python E2E script exists and runs successfully."""
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            capture_output=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("e2e_test.py timed out after 10 seconds.")

    assert result.returncode == 0, (
        f"e2e_test.py failed with exit code {result.returncode}.\n"
        f"Stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(REPORT_PATH), f"e2e_test.py did not create {REPORT_PATH}."


def test_report_json_content():
    """Verify that test_report.json contains the correct counts for the supplied data."""
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not a valid JSON file.")

    assert "utf8_count" in data, "Key 'utf8_count' missing from test_report.json"
    assert "shiftjis_count" in data, "Key 'shiftjis_count' missing from test_report.json"
    assert data["utf8_count"] == 10, f"Expected utf8_count to be 10, got {data['utf8_count']}"
    assert data["shiftjis_count"] == 15, f"Expected shiftjis_count to be 15, got {data['shiftjis_count']}"


def test_go_program_processes_derived_input():
    """Reject programs that merely exit or emit output hard-coded for the original fixture."""
    with open(INPUT_FILE, "rb") as f:
        original_input = f.read()

    token = secrets.token_hex(8)
    utf8_count = 3 + secrets.randbelow(4)
    sjis_count = 4 + secrets.randbelow(4)
    records = [
        f"動的UTF8-{token}-{i}".encode("utf-8") for i in range(utf8_count)
    ] + [
        f"動的SJIS-{token}-{i}".encode("shift_jis") for i in range(sjis_count)
    ]

    try:
        with open(INPUT_FILE, "wb") as f:
            for record in records:
                f.write(record + b"\n")

        result = run_go()
        assert result.returncode == 0, (
            f"Go program failed on derived input with exit code {result.returncode}.\n"
            f"Stderr: {result.stderr.decode('utf-8', errors='replace')}"
        )
        assert_output_contains_exact_records(result.stdout, records)
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)


def test_e2e_executes_go_and_decodes_derived_output():
    """Exercise the orchestrator against a temporary Go producer with derived counts."""
    with open(GO_FILE, "rb") as f:
        original_go = f.read()

    marker = f"/tmp/e2e_go_marker_{secrets.token_hex(12)}"
    utf8_count = 2 + secrets.randbelow(5)
    sjis_count = 3 + secrets.randbelow(6)
    utf8_lines = [f"検証UTF8-{secrets.token_hex(6)}-{i}".encode("utf-8") for i in range(utf8_count)]
    sjis_lines = [f"検証SJIS-{secrets.token_hex(6)}-{i}".encode("shift_jis") for i in range(sjis_count)]

    # Ensure every fallback fixture genuinely fails strict UTF-8 decoding.
    for line in sjis_lines:
        with pytest.raises(UnicodeDecodeError):
            line.decode("utf-8", errors="strict")
        line.decode("shift_jis", errors="strict")

    all_lines = utf8_lines + sjis_lines
    byte_literals = []
    for line in all_lines:
        payload = line + b"\n"
        byte_literals.append("[]byte{" + ",".join(str(value) for value in payload) + "}")

    generated_go = f'''package main
import "os"
func main() {{
    if err := os.WriteFile({json.dumps(marker)}, []byte("ran"), 0600); err != nil {{ panic(err) }}
    lines := [][]byte{{{','.join(byte_literals)}}}
    for _, line := range lines {{
        if _, err := os.Stdout.Write(line); err != nil {{ panic(err) }}
    }}
}}
'''.encode("utf-8")

    try:
        with open(GO_FILE, "wb") as f:
            f.write(generated_go)
        if os.path.exists(marker):
            os.remove(marker)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)

        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH],
                capture_output=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("e2e_test.py timed out while processing derived Go output.")

        assert result.returncode == 0, (
            f"e2e_test.py failed on derived output with exit code {result.returncode}.\n"
            f"Stderr: {result.stderr.decode('utf-8', errors='replace')}"
        )
        assert os.path.isfile(marker), "e2e_test.py did not execute the Go program"
        assert os.path.isfile(REPORT_PATH), f"e2e_test.py did not create {REPORT_PATH}."

        with open(REPORT_PATH, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"{REPORT_PATH} is not valid JSON for derived output.")

        assert data.get("utf8_count") == utf8_count, (
            f"Expected derived utf8_count {utf8_count}, got {data.get('utf8_count')}"
        )
        assert data.get("shiftjis_count") == sjis_count, (
            f"Expected derived shiftjis_count {sjis_count}, got {data.get('shiftjis_count')}"
        )
        assert isinstance(data.get("utf8_count"), int)
        assert isinstance(data.get("shiftjis_count"), int)
    finally:
        with open(GO_FILE, "wb") as f:
            f.write(original_go)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
