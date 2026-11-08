#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

CLEANED_CSV_PATH = "/home/user/output/cleaned.csv"
SIMILAR_TXT_PATH = "/home/user/output/similar.txt"
SOURCE_PATH = "/home/user/workspace/process.go"
DATA_PATH = "/home/user/data/servers.csv"


def test_cleaned_csv_exists():
    assert os.path.isfile(CLEANED_CSV_PATH), f"Expected output file {CLEANED_CSV_PATH} does not exist."


def test_similar_txt_exists():
    assert os.path.isfile(SIMILAR_TXT_PATH), f"Expected output file {SIMILAR_TXT_PATH} does not exist."


def test_cleaned_csv_contents():
    assert os.path.isfile(CLEANED_CSV_PATH), f"Cannot test content, {CLEANED_CSV_PATH} is missing."

    with open(CLEANED_CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) >= 1, "The cleaned.csv file is empty or missing a header."
    header = rows[0]
    expected_header = ["ServerID", "CPU", "Mem", "NetTotal"]
    assert header == expected_header, f"Header in cleaned.csv is incorrect. Expected {expected_header}, got {header}."

    expected_data = {
        "S-01": {"CPU": "45.00", "Mem": "60.00", "NetTotal": "15.00"},
        "S-02": {"CPU": "63.60", "Mem": "70.00", "NetTotal": "21.00"},
        "S-04": {"CPU": "40.00", "Mem": "55.00", "NetTotal": "17.00"},
        "S-05": {"CPU": "42.00", "Mem": "64.60", "NetTotal": "13.00"},
        "S-10": {"CPU": "41.00", "Mem": "58.00", "NetTotal": "15.00"}
    }

    actual_data = {}
    for row in rows[1:]:
        assert len(row) == 4, f"Row {row} does not have exactly 4 columns."
        actual_data[row[0]] = {"CPU": row[1], "Mem": row[2], "NetTotal": row[3]}

    assert "S-03" not in actual_data, "Row S-03 should have been filtered out (CPU > 100.0)."
    assert set(actual_data.keys()) == set(expected_data.keys()), \
        f"ServerIDs in cleaned.csv do not match expected. Expected {list(expected_data.keys())}, got {list(actual_data.keys())}."

    for sid, expected_vals in expected_data.items():
        actual_vals = actual_data[sid]
        for col in ["CPU", "Mem", "NetTotal"]:
            assert actual_vals[col] == expected_vals[col], \
                f"For {sid}, expected {col} to be {expected_vals[col]}, but got {actual_vals[col]}."


def test_similar_txt_contents():
    assert os.path.isfile(SIMILAR_TXT_PATH), f"Cannot test content, {SIMILAR_TXT_PATH} is missing."

    with open(SIMILAR_TXT_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["S-04", "S-01"]
    assert lines == expected_lines, \
        f"Contents of similar.txt do not match expected. Expected {expected_lines}, got {lines}."


def derive_expected(rows):
    numeric = ["CPU", "Mem", "Disk", "NetIn", "NetOut"]
    means = {}
    for col in numeric:
        values = [float(row[col]) for row in rows if row[col] != ""]
        assert values, f"Generated test data unexpectedly has no values for {col}"
        means[col] = sum(values) / len(values)

    cleaned = []
    for row in rows:
        values = {col: (float(row[col]) if row[col] != "" else means[col]) for col in numeric}
        if values["CPU"] > 100.0 or values["Mem"] > 100.0:
            continue
        cleaned.append({
            "ServerID": row["ServerID"],
            "CPU": values["CPU"],
            "Mem": values["Mem"],
            "NetTotal": values["NetIn"] + values["NetOut"],
        })

    target = next(row for row in cleaned if row["ServerID"] == "S-10")
    ranked = []
    for row in cleaned:
        if row["ServerID"] == "S-10":
            continue
        distance = math.sqrt(
            (row["CPU"] - target["CPU"]) ** 2
            + (row["Mem"] - target["Mem"]) ** 2
            + (row["NetTotal"] - target["NetTotal"]) ** 2
        )
        ranked.append((distance, row["ServerID"]))
    ranked.sort(key=lambda item: (item[0], item[1]))
    return cleaned, [sid for _, sid in ranked[:2]]


def write_input(rows):
    Path(DATA_PATH).parent.mkdir(parents=True, exist_ok=True)
    with open(DATA_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["ServerID", "CPU", "Mem", "Disk", "NetIn", "NetOut"])
        writer.writeheader()
        writer.writerows(rows)


def check_generated_outputs(expected_rows, expected_similar):
    assert os.path.isfile(CLEANED_CSV_PATH), "Program did not create cleaned.csv"
    assert os.path.isfile(SIMILAR_TXT_PATH), "Program did not create similar.txt"

    with open(CLEANED_CSV_PATH, newline="", encoding="utf-8") as f:
        actual_rows = list(csv.reader(f))
    assert actual_rows, "Generated cleaned.csv is empty"
    assert actual_rows[0] == ["ServerID", "CPU", "Mem", "NetTotal"]
    assert len(actual_rows) == len(expected_rows) + 1, "cleaned.csv has the wrong number of rows"

    actual = {}
    two_decimals = re.compile(r"^-?\d+\.\d{2}$")
    for row in actual_rows[1:]:
        assert len(row) == 4, f"Row {row} does not have exactly four columns"
        assert row[0] not in actual, f"Duplicate ServerID {row[0]} in cleaned.csv"
        for value in row[1:]:
            assert two_decimals.fullmatch(value), f"Value {value!r} is not formatted to exactly two decimals"
        actual[row[0]] = [float(value) for value in row[1:]]

    expected = {
        row["ServerID"]: [row["CPU"], row["Mem"], row["NetTotal"]]
        for row in expected_rows
    }
    assert set(actual) == set(expected), "cleaned.csv contains the wrong ServerIDs"
    for sid, expected_values in expected.items():
        for got, wanted in zip(actual[sid], expected_values):
            assert abs(got - wanted) <= 0.00501, f"Incorrect cleaned value for {sid}: got {got}, expected {wanted}"

    with open(SIMILAR_TXT_PATH, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert lines == expected_similar, f"Incorrect similarity result: got {lines}, expected {expected_similar}"


def test_go_program_executes_and_processes_unseen_inputs():
    assert os.path.exists(SOURCE_PATH), f"Expected Go source file {SOURCE_PATH} does not exist"
    mode = os.stat(SOURCE_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SOURCE_PATH} is not a regular file"
    assert os.path.getsize(SOURCE_PATH) > 0, f"{SOURCE_PATH} is empty"

    token = secrets.token_hex(4)
    base_cpu = 30 + secrets.randbelow(25)
    base_mem = 40 + secrets.randbelow(25)
    base_in = 5 + secrets.randbelow(12)
    base_out = 3 + secrets.randbelow(9)

    cases = [
        [
            {"ServerID": "S-10", "CPU": str(base_cpu), "Mem": str(base_mem), "Disk": "401", "NetIn": str(base_in), "NetOut": str(base_out)},
            {"ServerID": "near-" + token, "CPU": str(base_cpu + 1), "Mem": str(base_mem), "Disk": "999", "NetIn": str(base_in), "NetOut": str(base_out)},
            {"ServerID": "second-" + token, "CPU": str(base_cpu - 2), "Mem": str(base_mem + 1), "Disk": "10", "NetIn": str(base_in), "NetOut": str(base_out)},
            {"ServerID": "missing-" + token, "CPU": "", "Mem": str(base_mem + 18), "Disk": "", "NetIn": "", "NetOut": str(base_out + 5)},
            {"ServerID": "far-" + token, "CPU": str(base_cpu + 35), "Mem": str(base_mem + 25), "Disk": "700", "NetIn": str(base_in + 20), "NetOut": ""},
            {"ServerID": "cpu-out-" + token, "CPU": "145", "Mem": str(base_mem), "Disk": "80", "NetIn": "2", "NetOut": "3"},
            {"ServerID": "mem-out-" + token, "CPU": str(base_cpu), "Mem": "130", "Disk": "90", "NetIn": "4", "NetOut": "5"},
        ],
        [
            {"ServerID": "S-10", "CPU": str(base_cpu), "Mem": str(base_mem), "Disk": "1", "NetIn": str(base_in), "NetOut": str(base_out)},
            {"ServerID": "A-" + token, "CPU": str(base_cpu - 1), "Mem": str(base_mem), "Disk": "5000", "NetIn": str(base_in), "NetOut": str(base_out)},
            {"ServerID": "B-" + token, "CPU": str(base_cpu + 1), "Mem": str(base_mem), "Disk": "2", "NetIn": str(base_in), "NetOut": str(base_out)},
            {"ServerID": "Z-" + token, "CPU": str(base_cpu + 20), "Mem": str(base_mem + 20), "Disk": "3", "NetIn": str(base_in + 10), "NetOut": str(base_out + 10)},
        ],
    ]

    paths = [DATA_PATH, CLEANED_CSV_PATH, SIMILAR_TXT_PATH]
    backups = {path: (Path(path).read_bytes() if os.path.isfile(path) else None) for path in paths}
    try:
        for rows in cases:
            expected_rows, expected_similar = derive_expected(rows)
            write_input(rows)
            for output in [CLEANED_CSV_PATH, SIMILAR_TXT_PATH]:
                try:
                    os.remove(output)
                except FileNotFoundError:
                    pass

            result = subprocess.run(
                ["go", "run", SOURCE_PATH],
                cwd="/home/user/workspace",
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=45,
            )
            assert result.returncode == 0, f"Go program failed to compile or run:\n{result.stdout}"
            check_generated_outputs(expected_rows, expected_similar)
    finally:
        for path, content in backups.items():
            if content is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                Path(path).parent.mkdir(parents=True, exist_ok=True)
                Path(path).write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
