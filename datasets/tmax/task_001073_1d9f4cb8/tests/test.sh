#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import ast
import pytest


def test_script_exists_and_uses_parallelism():
    """Verify the script exists and uses a parallel processing library."""
    script_path = "/home/user/process_configs.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    try:
        tree = ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"Script contains syntax errors: {e}")

    uses_parallel = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name.startswith("multiprocessing") or alias.name.startswith("concurrent.futures"):
                    uses_parallel = True
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module.startswith("multiprocessing") or node.module.startswith("concurrent.futures")):
                uses_parallel = True

    assert uses_parallel, "Script does not import 'multiprocessing' or 'concurrent.futures' for parallel processing."

    parallel_constructors = {"Pool", "Process", "ProcessPoolExecutor"}
    invokes_parallelism = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id in parallel_constructors:
                invokes_parallelism = True
            elif isinstance(node.func, ast.Attribute) and node.func.attr in parallel_constructors:
                invokes_parallelism = True
    assert invokes_parallelism, "Script imports a parallel library but never constructs a worker pool, process, or ProcessPoolExecutor."


def test_output_csv_correct():
    """Verify the generated CSV matches the expected normalized and aggregated format."""
    csv_path = "/home/user/normalized_configs.csv"
    assert os.path.isfile(csv_path), f"Output file {csv_path} does not exist."

    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Output CSV is empty."

    header = rows[0]
    expected_header = ["aligned_hour", "server_name", "param_name", "param_value"]
    assert header == expected_header, f"Expected header {expected_header}, got {header}."

    data = rows[1:]

    expected_data = [
        ("2023-05-10 08:00:00", "db01", "timeout", 60.0),
        ("2023-05-10 08:00:00", "db01", "workers", 8.0),
        ("2023-05-10 08:00:00", "web01", "timeout", 30.0),
        ("2023-05-10 08:00:00", "web01", "workers", 5.0),
        ("2023-05-10 09:00:00", "db01", "workers", 8.0),
        ("2023-05-10 09:00:00", "web01", "timeout", 45.0),
        ("2023-05-10 09:00:00", "web01", "workers", 5.0),
        ("2023-05-11 14:00:00", "db01", "timeout", 120.0),
        ("2023-05-11 14:00:00", "db01", "workers", 16.0),
        ("2023-05-11 14:00:00", "web01", "timeout", 60.0),
        ("2023-05-11 14:00:00", "web01", "workers", 8.0),
        ("2023-05-11 15:00:00", "db01", "timeout", 120.0),
        ("2023-05-11 15:00:00", "db01", "workers", 32.0),
        ("2023-05-11 15:00:00", "web01", "timeout", 60.0),
        ("2023-05-11 15:00:00", "web01", "workers", 8.0)
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(data)}."

    for i, (row, exp) in enumerate(zip(data, expected_data)):
        assert len(row) == 4, f"Row {i+1} does not have exactly 4 columns: {row}"
        assert row[0] == exp[0], f"Row {i+1} aligned_hour mismatch: expected '{exp[0]}', got '{row[0]}'"
        assert row[1] == exp[1], f"Row {i+1} server_name mismatch: expected '{exp[1]}', got '{row[1]}'"
        assert row[2] == exp[2], f"Row {i+1} param_name mismatch: expected '{exp[2]}', got '{row[2]}'"

        try:
            val = float(row[3])
        except ValueError:
            pytest.fail(f"Row {i+1} param_value is not a valid number: '{row[3]}'")

        assert val == exp[3], f"Row {i+1} param_value mismatch: expected {exp[3]}, got {val}"
TEST_EOF

rm -f /home/user/normalized_configs.csv
(cd /home/user && timeout 30s python3 process_configs.py) || status=1
if [ "$status" -eq 0 ]; then
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || status=1
fi

if [ "$status" -eq 0 ]; then
    rm -rf /home/user/raw_configs
    mkdir -p /home/user/raw_configs

    python3 << 'FIXTURE_EOF' || status=1
import csv
import os
import random

rng = random.SystemRandom()
values = [rng.randint(101, 9999) for _ in range(15)]
header = ["Raw_Time", "edge7_timeout", "edge7_workers", "db9_timeout"]
rows_a = [
    ["2031-07-04 12:59:59", values[0], "", values[1]],
    ["07/04/2031 12:01:02", values[2], values[3], values[4]],
    ["2031-07-04 13:00:00", values[5], values[6], ""],
]
rows_b = [
    ["07/03/2031 23:58:01", values[7], values[8], values[9]],
    ["2031-07-04 12:40:00", values[10], values[11], values[12]],
    ["07/04/2031 13:47:13", "", values[13], values[14]],
]
os.makedirs("/home/user/raw_configs", exist_ok=True)
for name, rows in [("changed_a.csv", rows_a), ("changed_b.csv", rows_b)]:
    with open(os.path.join("/home/user/raw_configs", name), "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
FIXTURE_EOF
fi

if [ "$status" -eq 0 ]; then
    rm -f /home/user/normalized_configs.csv
    (cd /home/user && timeout 30s python3 process_configs.py) || status=1
fi

if [ "$status" -eq 0 ]; then
    python3 << 'DYNAMIC_TEST_EOF' || status=1
import csv
import glob
import math
import os
from datetime import datetime

output_path = "/home/user/normalized_configs.csv"
assert os.path.isfile(output_path), "Script did not create normalized_configs.csv for altered inputs"

expected = {}
for path in glob.glob("/home/user/raw_configs/*.csv"):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames and reader.fieldnames[0] == "Raw_Time"
        for row in reader:
            raw_time = row["Raw_Time"]
            parsed = None
            for fmt in ("%Y-%m-%d %H:%M:%S", "%m/%d/%Y %H:%M:%S"):
                try:
                    parsed = datetime.strptime(raw_time, fmt)
                    break
                except ValueError:
                    pass
            assert parsed is not None
            aligned = parsed.replace(minute=0, second=0, microsecond=0).strftime("%Y-%m-%d %H:00:00")
            for column, raw_value in row.items():
                if column == "Raw_Time" or raw_value is None or raw_value.strip() == "":
                    continue
                server, parameter = column.split("_", 1)
                value = float(raw_value)
                key = (aligned, server, parameter)
                expected[key] = max(expected.get(key, value), value)

expected_rows = [(a, s, p, v) for (a, s, p), v in sorted(expected.items())]

with open(output_path, newline="") as f:
    rows = list(csv.reader(f))

header = ["aligned_hour", "server_name", "param_name", "param_value"]
assert rows, "Output CSV is empty for altered inputs"
assert rows[0] == header, f"Expected header {header}, got {rows[0]}"
assert len(rows) - 1 == len(expected_rows), f"Expected {len(expected_rows)} altered-input rows, got {len(rows)-1}"

for index, (actual, expected_row) in enumerate(zip(rows[1:], expected_rows), 1):
    assert len(actual) == 4, f"Altered-input row {index} does not have four columns: {actual}"
    assert actual[:3] == list(expected_row[:3]), f"Altered-input row {index} key/order mismatch: expected {expected_row[:3]}, got {actual[:3]}"
    try:
        actual_value = float(actual[3])
    except ValueError:
        raise AssertionError(f"Altered-input row {index} has non-numeric value {actual[3]!r}")
    assert math.isclose(actual_value, expected_row[3], rel_tol=0, abs_tol=1e-9), (
        f"Altered-input row {index} value mismatch: expected {expected_row[3]}, got {actual_value}"
    )
DYNAMIC_TEST_EOF
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
