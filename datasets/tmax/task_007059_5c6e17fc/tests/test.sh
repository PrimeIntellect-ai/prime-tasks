#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/csv_to_json.c"
EXECUTABLE = "/home/user/csv_to_json"
PAGE = "/home/user/page.json"
CSV_PATH = "/home/user/query_results.csv"


def format_json(rows):
    lines = ["["]
    for i, (query_id, execution_time, table, rows_scanned) in enumerate(rows):
        comma = "," if i + 1 < len(rows) else ""
        lines.append(
            f'  {{"query": {{"id": {json.dumps(query_id)}}}, '
            f'"performance": {{"time_ms": {int(execution_time)}, '
            f'"scanned": {int(rows_scanned)}}}, '
            f'"table": {json.dumps(table)}}}{comma}'
        )
    lines.append("]")
    return ("\n".join(lines) + "\n").encode()


def processed_page():
    with open(CSV_PATH, newline="") as f:
        rows = [tuple(row) for row in csv.reader(f)]
    assert all(len(row) == 4 for row in rows)

    unique = []
    seen = set()
    for row in rows:
        if row not in seen:
            seen.add(row)
            unique.append(row)

    unique.sort(key=lambda row: int(row[1]), reverse=True)
    return unique[3:7]


def csv_bytes(rows):
    return ("".join(",".join(map(str, row)) + "\n" for row in rows)).encode()


def run_converter(path, rows):
    result = subprocess.run(
        [path],
        input=csv_bytes(rows),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"Converter {path} exited with {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    assert result.stdout == format_json(rows), (
        f"Converter {path} did not produce the required exact JSON formatting."
    )


def test_c_source_file_exists():
    assert os.path.exists(SOURCE), f"C source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."


def test_c_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Compiled executable {EXECUTABLE} is missing."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_page_json_content():
    assert os.path.exists(PAGE), f"Output file {PAGE} is missing."
    assert os.path.isfile(PAGE), f"{PAGE} is not a file."

    with open(PAGE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {PAGE} as JSON: {e}")

    expected_data = [
        {"query": {"id": "Q_107"}, "performance": {"time_ms": 670, "scanned": 32000}, "table": "inventory"},
        {"query": {"id": "Q_101"}, "performance": {"time_ms": 450, "scanned": 15000}, "table": "users"},
        {"query": {"id": "Q_110"}, "performance": {"time_ms": 410, "scanned": 18000}, "table": "events"},
        {"query": {"id": "Q_104"}, "performance": {"time_ms": 330, "scanned": 8000}, "table": "products"},
    ]
    assert data == expected_data, (
        f"JSON content in {PAGE} does not match the expected paginated results."
    )

    with open(PAGE, "rb") as f:
        actual = f.read()
    assert actual == format_json(processed_page()), (
        f"{PAGE} does not have the required exact structure and whitespace."
    )


def test_converter_behavior():
    real_rows = processed_page()

    token = secrets.token_hex(8)
    synthetic_rows = [
        (f"Q_{token}_A", "731", f"table_{token}_a", "91001"),
        (f"Q_{token}_B", "509", f"table_{token}_b", "82002"),
        (f"Q_{token}_C", "287", f"table_{token}_c", "73003"),
        (f"Q_{token}_D", "64", f"table_{token}_d", "64004"),
    ]

    # Execute the artifact the instruction required.
    run_converter(EXECUTABLE, real_rows)
    run_converter(EXECUTABLE, synthetic_rows)

    # Also ensure the submitted C source genuinely builds and behaves correctly.
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "csv_to_json")
        result = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, (
            "The submitted C source does not compile: "
            + result.stderr.decode(errors="replace")
        )
        run_converter(rebuilt, real_rows)
        run_converter(rebuilt, synthetic_rows)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
