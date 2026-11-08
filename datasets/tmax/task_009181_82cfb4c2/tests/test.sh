#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import string
import subprocess
from pathlib import Path

import pytest


def test_clean_data_csv():
    csv_path = '/home/user/clean_data.csv'
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."

    expected_rows = [
        ['date', 'unit', 'temperature_c', 'pressure_kpa'],
        ['2023-10-01', 'Unit-Alpha', '40.0', '100.0'],
        ['2023-10-02', 'Unit-Beta', '40.0', '100.0'],
        ['2023-10-03', 'Unit-Gamma', '35.3', '104.8'],
        ['2023-10-04', 'Unit-Delta', '22.0', '101.3'],
        ['2022-12-31', 'Unit-Epsilon', '0.0', '101.4'],
        ['2023-01-01', 'Unit-Zeta', '0.0', '0.0']
    ]

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, f"{csv_path} is empty."
    assert actual_rows[0] == expected_rows[0], f"CSV header is incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}"
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch. Expected {expected}, got {actual}"


def test_pipeline_json():
    json_path = '/home/user/pipeline.json'
    assert os.path.isfile(json_path), f"Output file {json_path} is missing."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not a valid JSON file.")

    expected_data = {
        "total_lines_processed": 8,
        "successful_parses": 6,
        "failed_parses": 2
    }

    assert isinstance(data, dict), "JSON root must be an object/dict."

    for key, expected_value in expected_data.items():
        assert key in data, f"Key '{key}' missing from {json_path}."
        assert data[key] == expected_value, f"Value for '{key}' is incorrect. Expected {expected_value}, got {data[key]}."

    assert set(data) == set(expected_data), f"JSON must contain exactly these keys: {sorted(expected_data)}"
    for key in expected_data:
        assert type(data[key]) is int, f"Value for '{key}' must be an integer."


def test_cleaner_executes_on_unseen_input():
    script = Path('/home/user/cleaner.py')
    assert script.exists(), f"Required script {script} is missing."
    assert not script.is_symlink(), f"{script} must be a regular Python script, not a symlink."
    assert stat.S_ISREG(script.lstat().st_mode), f"{script} is not a regular file."
    assert script.stat().st_size > 0, f"{script} is empty."

    raw_path = Path('/home/user/raw_sensors.log')
    csv_path = Path('/home/user/clean_data.csv')
    json_path = Path('/home/user/pipeline.json')
    paths = [raw_path, csv_path, json_path]
    saved = {path: path.read_bytes() if path.exists() else None for path in paths}

    letters = string.ascii_letters
    units = ['Unit-' + ''.join(secrets.choice(letters) for _ in range(12)) for _ in range(8)]
    f1 = secrets.randbelow(81) + 70.2
    psi1 = secrets.randbelow(26) + 5.37
    c2 = secrets.randbelow(51) + 0.26
    kpa2 = secrets.randbelow(81) + 70.41
    f3 = secrets.randbelow(91) + 40
    kpa3 = secrets.randbelow(121) + 1
    c4 = secrets.randbelow(61) + 0.34
    psi4 = secrets.randbelow(31) + 1.29

    lines = [
        f"noise [2024/02/03] {units[0]} reported Temp: {f1:.2f}F and Pressure: {psi1:.2f}psi end",
        f"[11-07-2021] {units[1]} press is {kpa2:.2f}kPa while temp is {c2:.2f}C.",
        f"Pressure {kpa3:.0f}kPa; {units[2]} has {f3:.0f}F on [2019/12/31]",
        f"{units[3]} prefix {psi4:.2f}psi [01-09-2020] suffix temperature {c4:.2f}C",
        "ordinary system heartbeat without a reading",
        f"[2022/03/04] {units[4]} temperature 20C but pressure is absent",
        f"{units[5]} temperature 21C pressure 90kPa but no date",
        f"[2022/05/06] temperature 22C pressure 91kPa but no unit"
    ]

    expected_rows = [
        ['date', 'unit', 'temperature_c', 'pressure_kpa'],
        ['2024-02-03', units[0], f"{(f1 - 32) * 5 / 9:.1f}", f"{psi1 * 6.89476:.1f}"],
        ['2021-11-07', units[1], f"{c2:.1f}", f"{kpa2:.1f}"],
        ['2019-12-31', units[2], f"{(f3 - 32) * 5 / 9:.1f}", f"{kpa3:.1f}"],
        ['2020-01-09', units[3], f"{c4:.1f}", f"{psi4 * 6.89476:.1f}"]
    ]
    expected_log = {
        'total_lines_processed': len(lines),
        'successful_parses': 4,
        'failed_parses': len(lines) - 4
    }

    try:
        raw_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        csv_path.unlink(missing_ok=True)
        json_path.unlink(missing_ok=True)

        proc = subprocess.run(
            ['python3', str(script)],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20
        )
        assert proc.returncode == 0, f"cleaner.py failed with exit code {proc.returncode}:\n{proc.stderr}"
        assert csv_path.is_file(), "cleaner.py did not create clean_data.csv."
        assert json_path.is_file(), "cleaner.py did not create pipeline.json."

        with csv_path.open('r', newline='', encoding='utf-8') as f:
            actual_rows = list(csv.reader(f))
        assert actual_rows == expected_rows, f"cleaner.py produced incorrect CSV for unseen input. Expected {expected_rows}, got {actual_rows}"

        try:
            with json_path.open('r', encoding='utf-8') as f:
                actual_log = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"cleaner.py produced invalid pipeline JSON: {exc}")

        assert isinstance(actual_log, dict), "Pipeline JSON root must be an object/dict."
        assert actual_log == expected_log, f"Incorrect pipeline log for unseen input. Expected {expected_log}, got {actual_log}"
        assert set(actual_log) == set(expected_log), "Pipeline JSON contains missing or extra keys."
        for key in expected_log:
            assert type(actual_log[key]) is int, f"Value for '{key}' must be an integer."
    finally:
        for path, content in saved.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
