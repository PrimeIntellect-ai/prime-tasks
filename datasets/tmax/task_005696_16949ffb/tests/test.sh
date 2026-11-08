#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_01_processed_data_content():
    processed_data_path = "/home/user/processed_data.csv"
    assert os.path.exists(processed_data_path), f"File missing: {processed_data_path}"

    expected_rows = [
        "1599999940,1,25.0",
        "1599999940,2,25.5",
        "1600000000,1,25.4",
        "1600000240,1,24.0",
        "1600000240,2,24.1",
        "1600000000,2,26.1",
        "1600000060,1,25.5",
        "1600000120,2,26.3",
        "1600000180,1,25.8",
        "1600000180,2,26.5"
    ]

    with open(processed_data_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_rows, (
        f"Output mismatch in {processed_data_path}.\n"
        f"Expected {len(expected_rows)} rows: {expected_rows}\n"
        f"Actual {len(actual_lines)} rows: {actual_lines}"
    )


def test_02_etl_executable_exists():
    source_path = "/home/user/etl.c"
    executable_path = "/home/user/etl"

    assert os.path.exists(source_path), f"Source file {source_path} is missing."
    assert os.path.exists(executable_path), f"Executable {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"{executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled executable."


def derive_expected(initial_rows, raw_rows):
    result = list(initial_rows)
    existing = set()
    for row in initial_rows:
        timestamp, sensor_id, _ = row.split(',')
        existing.add((int(timestamp), int(sensor_id)))

    for row in raw_rows:
        timestamp_text, sensor_1_text, sensor_2_text = row.split(',')
        timestamp = int(timestamp_text)
        for sensor_id, value_text in ((1, sensor_1_text), (2, sensor_2_text)):
            value = float(value_text)
            key = (timestamp, sensor_id)
            if -40.0 <= value <= 85.0 and key not in existing:
                result.append(f"{timestamp},{sensor_id},{value:.1f}")
                existing.add(key)
    return result


def run_case(executable, base):
    t1 = secrets.randbelow(700) / 10.0 - 20.0
    t2 = secrets.randbelow(700) / 10.0 - 20.0
    t3 = secrets.randbelow(700) / 10.0 - 20.0
    t4 = secrets.randbelow(700) / 10.0 - 20.0

    initial_rows = [
        f"{base - 60},1,12.3",
        f"{base - 60},2,45.6",
        f"{base + 60},1,7.7",
        f"{base + 240},1,8.8",
    ]
    raw_rows = [
        f"{base},-40.0,85.0",
        f"{base + 60},{t1:.1f},{t2:.1f}",
        f"{base + 120},-40.1,85.1",
        f"{base + 180},{t3:.1f},{t4:.1f}",
        f"{base + 180},{t3:.1f},{t4:.1f}",
        f"{base + 240},21.2,22.3",
    ]
    expected = derive_expected(initial_rows, raw_rows)

    with open('/home/user/raw_data.csv', 'w') as f:
        f.write('\n'.join(raw_rows) + '\n')
    with open('/home/user/processed_data.csv', 'w') as f:
        f.write('\n'.join(initial_rows) + '\n')

    subprocess.run([executable], cwd='/home/user', timeout=10)
    with open('/home/user/processed_data.csv') as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"ETL output mismatch. Expected {expected}, got {actual}"

    subprocess.run([executable], cwd='/home/user', timeout=10)
    with open('/home/user/processed_data.csv') as f:
        second_run = [line.strip() for line in f if line.strip()]
    assert second_run == expected, "Running the ETL twice appended duplicate records"


def test_03_executable_and_source_implement_etl():
    compiled = '/tmp/etl_from_source'
    build = subprocess.run(
        ['gcc', '-O2', '-o', compiled, '/home/user/etl.c'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"etl.c does not compile with the required command:\n{build.stderr}"

    base = 1700000000 + secrets.randbelow(50000000)
    run_case('/home/user/etl', base)
    run_case(compiled, base + 100000000)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
