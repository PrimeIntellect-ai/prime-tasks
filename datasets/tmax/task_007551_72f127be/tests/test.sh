#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import secrets
from collections import defaultdict

import pandas as pd
import pytest

SCRIPT = '/home/user/etl_pipeline.py'
WRAPPER = '/home/user/run_etl.sh'
RAW_DIR = '/home/user/data/raw'
PARQUET = '/home/user/data/processed/master.parquet'
REQUIRED_COLUMNS = {'request_id', 'user_id', 'timestamp', 'response_time', 'rolling_avg_time'}


def run_etl():
    result = subprocess.run([WRAPPER], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"run_etl.sh failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def read_master():
    assert os.path.isfile(PARQUET), f"{PARQUET} was not created."
    try:
        df = pd.read_parquet(PARQUET)
    except Exception as exc:
        pytest.fail(f"Failed to read {PARQUET}: {exc}")
    assert REQUIRED_COLUMNS.issubset(df.columns), (
        f"master.parquet is missing required columns: {REQUIRED_COLUMNS - set(df.columns)}"
    )
    return df


def assert_output(df, expected):
    assert len(df) == len(expected), (
        f"Expected exactly {len(expected)} records, but found {len(df)}."
    )
    assert not df['request_id'].duplicated().any(), 'Duplicate request_id values found.'
    assert set(df['request_id'].astype(str)) == set(expected), (
        'Output request_id values do not match the input logs.'
    )

    indexed = df.copy()
    indexed['request_id'] = indexed['request_id'].astype(str)
    indexed = indexed.set_index('request_id', drop=False)

    for request_id, wanted in expected.items():
        row = indexed.loc[request_id]
        assert not isinstance(row, pd.DataFrame), f"Duplicate row for {request_id}."
        assert str(row['user_id']) == wanted['user_id']
        try:
            response_time = float(row['response_time'])
            rolling_avg = float(row['rolling_avg_time'])
        except (TypeError, ValueError) as exc:
            pytest.fail(f"Invalid metric types for {request_id}: {exc}")
        assert response_time == pytest.approx(float(wanted['response_time']))
        assert rolling_avg == pytest.approx(float(wanted['rolling_avg_time']))
        try:
            actual_timestamp = pd.to_datetime(row['timestamp'])
        except Exception as exc:
            pytest.fail(f"Invalid timestamp for {request_id}: {exc}")
        assert actual_timestamp == pd.Timestamp(wanted['timestamp'])


def calculate_expected(rows):
    history = defaultdict(list)
    expected = {}
    for timestamp, request_id, user_id, response_time in sorted(rows, key=lambda row: row[0]):
        history[user_id].append(response_time)
        window = history[user_id][-3:]
        expected[request_id] = {
            'user_id': user_id,
            'timestamp': timestamp,
            'response_time': response_time,
            'rolling_avg_time': sum(window) / len(window),
        }
    return expected


def write_log(path, rows):
    with open(path, 'w', encoding='utf-8') as handle:
        for timestamp, request_id, user_id, response_time in rows:
            handle.write(
                f"[{timestamp}] REQ:{request_id} USER:{user_id} TIME:{response_time}ms\n"
            )


def test_etl_scripts_exist():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is missing."
    assert os.path.isfile(WRAPPER), f"{WRAPPER} is missing."
    st = os.stat(WRAPPER)
    assert bool(st.st_mode & stat.S_IXUSR), f"{WRAPPER} is not executable."


def test_cron_job_scheduled():
    result = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
    assert result.returncode == 0, 'Failed to read crontab. Is cron configured for the user?'

    found = False
    for line in result.stdout.splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            parts = line.split()
            if len(parts) >= 6:
                schedule = ' '.join(parts[:5])
                command = ' '.join(parts[5:])
                if schedule == '*/5 * * * *' and WRAPPER in command:
                    found = True
                    break
    assert found, (
        'Cron job for run_etl.sh running every 5 minutes '
        '(*/5 * * * *) is not scheduled correctly.'
    )


def test_original_data_and_idempotency():
    run_etl()
    run_etl()
    df = read_master()

    expected_rows = [
        ('2023-10-25 14:30:00', 'r001', 'u1', 100),
        ('2023-10-25 14:31:00', 'r002', 'u1', 150),
        ('2023-10-25 14:32:00', 'r003', 'u2', 50),
        ('2023-10-25 14:33:00', 'r004', 'u1', 200),
        ('2023-10-25 14:34:00', 'r005', 'u1', 100),
    ]
    expected = calculate_expected(expected_rows)
    assert len(df) == 5, (
        f"Expected exactly 5 records in master.parquet after retries, but found {len(df)}."
    )
    assert_output(df, expected)

    r005 = df[df['request_id'].astype(str) == 'r005']
    assert len(r005) == 1, "Record 'r005' not found uniquely in master.parquet."
    row = r005.iloc[0]
    assert str(row['user_id']) == 'u1'
    assert float(row['response_time']) == 100.0
    assert float(row['rolling_avg_time']) == 150.0


def test_dynamic_parsing_rolling_and_general_upsert():
    if os.path.exists(PARQUET):
        os.remove(PARQUET)
    for name in os.listdir(RAW_DIR):
        path = os.path.join(RAW_DIR, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)

    token = secrets.token_hex(6)
    user_a = f'userA_{token}'
    user_b = f'userB_{token}'
    user_c = f'userC_{token}'
    values = [40 + secrets.randbelow(260) for _ in range(10)]

    rows = [
        ('2041-07-03 09:00:00', f'req_{token}_0', user_a, values[0]),
        ('2041-07-03 09:01:00', f'req_{token}_1', user_b, values[1]),
        ('2041-07-03 09:02:00', f'req_{token}_2', user_a, values[2]),
        ('2041-07-03 09:03:00', f'req_{token}_3', user_a, values[3]),
        ('2041-07-03 09:04:00', f'req_{token}_4', user_b, values[4]),
        ('2041-07-03 09:05:00', f'req_{token}_5', user_a, values[5]),
        ('2041-07-03 09:06:00', f'req_{token}_6', user_b, values[6]),
        ('2041-07-03 09:07:00', f'req_{token}_7', user_a, values[7]),
    ]

    # Deliberately distribute records non-chronologically across files.
    write_log(os.path.join(RAW_DIR, 'dynamic_a.txt'), list(reversed(rows[::2])))
    write_log(os.path.join(RAW_DIR, 'dynamic_b.txt'), list(reversed(rows[1::2])))

    expected = calculate_expected(rows)
    run_etl()
    assert_output(read_master(), expected)
    run_etl()
    assert_output(read_master(), expected)

    added_rows = [
        ('2041-07-03 09:08:00', f'req_{token}_8', user_b, values[8]),
        ('2041-07-03 09:09:00', f'req_{token}_9', user_c, values[9]),
    ]
    write_log(os.path.join(RAW_DIR, 'dynamic_new.txt'), added_rows)
    all_rows = rows + added_rows
    expanded_expected = calculate_expected(all_rows)

    run_etl()
    assert_output(read_master(), expanded_expected)
    run_etl()
    assert_output(read_master(), expanded_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
