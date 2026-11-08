#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import secrets
import subprocess
from datetime import datetime, timedelta, timezone

import pytest

SCRIPT_PATH = '/home/user/process_traffic.py'
INPUT_PATH = '/home/user/sensor_data.csv'
OUTPUT_PATH = '/home/user/processed_traffic.csv'


def parse_timestamp(ts_str):
    ts_str = ts_str.strip()
    if ts_str.endswith('Z'):
        ts_str = ts_str[:-1] + '+00:00'
    try:
        dt = datetime.fromisoformat(ts_str)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            dt = dt.astimezone(timezone.utc)
        return dt
    except ValueError:
        pytest.fail(f"Invalid timestamp format: {ts_str}")


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Processing script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not generated."


def assert_parallel_api_used(source):
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"Processing script is not valid Python: {exc}")

    imported_modules = set()
    imported_parallel_names = set()
    parallel_constructors = {
        'Pool', 'Process', 'ProcessPoolExecutor', 'ThreadPoolExecutor'
    }

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing' or alias.name.startswith('multiprocessing.') or alias.name == 'concurrent.futures':
                    imported_modules.add(alias.asname or alias.name.split('.')[0])
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ''
            if module == 'multiprocessing' or module.startswith('multiprocessing.') or module == 'concurrent.futures' or module == 'concurrent':
                for alias in node.names:
                    local_name = alias.asname or alias.name
                    if alias.name in parallel_constructors:
                        imported_parallel_names.add(local_name)
                    else:
                        imported_modules.add(local_name)

    def attribute_root(node):
        while isinstance(node, ast.Attribute):
            node = node.value
        return node.id if isinstance(node, ast.Name) else None

    used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in imported_parallel_names:
            used = True
            break
        if isinstance(node.func, ast.Attribute):
            root = attribute_root(node.func)
            if node.func.attr in parallel_constructors and root in imported_modules:
                used = True
                break

    assert used, (
        "The script must construct and use a multiprocessing or concurrent.futures "
        "parallel worker API (for example Pool or ProcessPoolExecutor)."
    )


def read_output():
    with open(OUTPUT_PATH, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers is not None, "CSV file is empty."
        if headers[0] == '' and len(headers) == 5:
            headers = headers[1:]
            has_index = True
        else:
            has_index = False
        expected_headers = ['sensor_id', 'timestamp', 'vehicle_count', 'rolling_avg_2h']
        assert headers == expected_headers, f"Expected headers {expected_headers}, got {headers}"
        rows = list(reader)
    if has_index:
        rows = [row[1:] for row in rows]
    return rows


def test_00_script_exists_runs_and_uses_parallel_api():
    assert os.path.isfile(SCRIPT_PATH), f"Processing script {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    assert source.strip(), "Processing script is empty."
    assert_parallel_api_used(source)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_script()


def test_processed_traffic_csv():
    file_path = OUTPUT_PATH
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    expected_data = [
        ('A', '2023-10-01T10:00:00+00:00', 10, 10.0),
        ('A', '2023-10-01T11:00:00+00:00', 15, 12.5),
        ('A', '2023-10-01T12:00:00+00:00', 20, 17.5),
        ('A', '2023-10-01T13:00:00+00:00', 30, 25.0),
        ('B', '2023-10-01T10:00:00+00:00', 50, 50.0),
        ('B', '2023-10-01T11:00:00+00:00', 60, 55.0),
        ('B', '2023-10-01T12:00:00+00:00', 70, 65.0),
        ('C', '2023-10-01T15:00:00+00:00', 100, 100.0),
        ('C', '2023-10-01T15:30:00+00:00', 120, 110.0),
    ]

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers is not None, "CSV file is empty."

        if headers[0] == '' and len(headers) == 5:
            headers = headers[1:]
            has_index = True
        else:
            has_index = False

        expected_headers = ['sensor_id', 'timestamp', 'vehicle_count', 'rolling_avg_2h']
        assert headers == expected_headers, f"Expected headers {expected_headers}, got {headers}"
        rows = list(reader)

    assert len(rows) == len(expected_data), f"Expected {len(expected_data)} rows, found {len(rows)}."

    for i, (row, expected) in enumerate(zip(rows, expected_data)):
        if has_index:
            row = row[1:]

        sensor_id, ts_str, v_count_str, roll_avg_str = row
        exp_sensor, exp_ts_str, exp_v_count, exp_roll_avg = expected

        assert sensor_id == exp_sensor, f"Row {i+1}: expected sensor_id {exp_sensor}, got {sensor_id}"
        dt = parse_timestamp(ts_str)
        exp_dt = parse_timestamp(exp_ts_str)
        assert dt == exp_dt, f"Row {i+1}: expected timestamp {exp_dt}, got {dt}"

        try:
            v_count = int(v_count_str)
        except ValueError:
            pytest.fail(f"Row {i+1}: invalid vehicle_count {v_count_str}")
        assert v_count == exp_v_count, f"Row {i+1}: expected vehicle_count {exp_v_count}, got {v_count}"

        try:
            roll_avg = float(roll_avg_str)
        except ValueError:
            pytest.fail(f"Row {i+1}: invalid rolling_avg_2h {roll_avg_str}")
        assert abs(roll_avg - exp_roll_avg) < 1e-5, f"Row {i+1}: expected rolling_avg_2h {exp_roll_avg}, got {roll_avg}"


def reference_result(input_rows):
    cleaned = []
    seen = set()
    for sensor_id, timestamp_text, count_text in input_rows:
        count = int(count_text)
        if count < 0:
            continue
        dt = parse_timestamp(timestamp_text)
        key = (sensor_id, dt)
        if key in seen:
            continue
        seen.add(key)
        cleaned.append((sensor_id, dt, count))

    expected = []
    for sensor_id in sorted({row[0] for row in cleaned}):
        group = sorted((row for row in cleaned if row[0] == sensor_id), key=lambda row: row[1])
        for _, current_time, count in group:
            lower = current_time - timedelta(hours=2)
            values = [r[2] for r in group if lower < r[1] <= current_time]
            expected.append((sensor_id, current_time, count, round(sum(values) / len(values), 2)))
    return expected


def test_script_processes_unseen_input_not_a_hardcoded_output():
    with open(INPUT_PATH, 'rb') as f:
        original_input = f.read()

    token = secrets.token_hex(4)
    sensor_a = 'X_' + token
    sensor_b = 'Y_' + token
    base = datetime(2024, 2, 3, 10, 0, tzinfo=timezone.utc)
    a = [secrets.randbelow(80) + 10 for _ in range(4)]
    b = [secrets.randbelow(80) + 10 for _ in range(3)]

    input_rows = [
        (sensor_b, (base + timedelta(minutes=30, hours=2)).isoformat(), str(b[0])),
        (sensor_a, base.strftime('%Y-%m-%dT%H:%M:%SZ'), str(a[0])),
        (sensor_a, (base + timedelta(hours=1) - timedelta(hours=4)).isoformat(), str(a[1])),
        (sensor_a, (base + timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'), str(a[2])),
        (sensor_a, (base + timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ'), '999'),
        (sensor_b, (base + timedelta(hours=2)).isoformat(), str(b[1])),
        (sensor_a, (base + timedelta(hours=2, minutes=30)).isoformat(), str(a[3])),
        (sensor_b, (base + timedelta(hours=2, minutes=30)).strftime('%Y-%m-%dT%H:%M:%SZ'), str(b[2])),
        (sensor_b, (base + timedelta(hours=1)).isoformat(), '-7'),
    ]
    expected = reference_result(input_rows)

    try:
        with open(INPUT_PATH, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['sensor_id', 'timestamp', 'vehicle_count'])
            writer.writerows(input_rows)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_script()
        rows = read_output()
        assert len(rows) == len(expected), f"Expected {len(expected)} rows, found {len(rows)}."

        for i, (row, exp) in enumerate(zip(rows, expected), start=1):
            assert len(row) == 4, f"Row {i} has {len(row)} columns instead of 4."
            sensor, ts_text, count_text, avg_text = row
            exp_sensor, exp_dt, exp_count, exp_avg = exp
            assert sensor == exp_sensor, f"Row {i}: expected sensor_id {exp_sensor}, got {sensor}"

            raw_ts = ts_text.strip()
            normalized = raw_ts[:-1] + '+00:00' if raw_ts.endswith('Z') else raw_ts
            try:
                parsed_raw = datetime.fromisoformat(normalized)
            except ValueError:
                pytest.fail(f"Row {i}: invalid timestamp {ts_text}")
            assert parsed_raw.tzinfo is not None, f"Row {i}: timestamp must be timezone-aware."
            assert parsed_raw.utcoffset() == timedelta(0), f"Row {i}: timestamp is not expressed in UTC."
            assert parsed_raw.astimezone(timezone.utc) == exp_dt, f"Row {i}: incorrect timestamp."

            try:
                actual_count = int(count_text)
                actual_avg = float(avg_text)
            except ValueError:
                pytest.fail(f"Row {i}: invalid numeric value in {row}")
            assert actual_count == exp_count, f"Row {i}: expected vehicle_count {exp_count}, got {actual_count}"
            assert abs(actual_avg - exp_avg) < 1e-5, f"Row {i}: expected rolling average {exp_avg}, got {actual_avg}"
    finally:
        with open(INPUT_PATH, 'wb') as f:
            f.write(original_input)
        subprocess.run(['python3', SCRIPT_PATH], cwd='/home/user', stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
