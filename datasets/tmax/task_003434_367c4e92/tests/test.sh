#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import stat
import hashlib
import re
import math
import random
import secrets
import subprocess
from collections import Counter, defaultdict
from datetime import date, timedelta

import pytest

PIPELINE = '/home/user/pipeline.py'
RUNNER = '/home/user/run_pipeline.sh'
RAW = '/home/user/raw_telemetry.csv'
OUTPUT = '/home/user/audit_sample.csv'

@pytest.fixture(scope='session', autouse=True)
def execute_original_pipeline():
    subprocess.run([RUNNER], cwd='/home/user', check=True, timeout=30)

def test_pipeline_script_exists():
    assert os.path.isfile(PIPELINE), "pipeline.py is missing"

def test_run_pipeline_sh():
    sh_path = RUNNER
    assert os.path.isfile(sh_path), "run_pipeline.sh is missing"
    st = os.stat(sh_path)
    assert bool(st.st_mode & stat.S_IXUSR), "run_pipeline.sh is not executable"

def test_cron_txt():
    cron_path = '/home/user/cron.txt'
    assert os.path.isfile(cron_path), "cron.txt is missing"
    with open(cron_path, 'r') as f:
        content = f.read().strip()

    match = re.search(r'^15\s+0?3\s+\*\s+\*\s+\*\s+/home/user/run_pipeline\.sh$', content)
    assert match is not None, f"cron.txt does not contain the correct cron schedule. Found: {content}"

def test_audit_sample_csv():
    csv_path = OUTPUT
    assert os.path.isfile(csv_path), "audit_sample.csv is missing"

    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert reader.fieldnames is not None, "audit_sample.csv has no header"
    expected_columns = ['PatientID', 'PatientName', 'Condition', 'HeartRate', 'RollingHR']
    for col in expected_columns:
        assert col in reader.fieldnames, f"Column {col} missing in audit_sample.csv"

    assert len(rows) == 2, f"Expected 2 rows in audit_sample.csv, got {len(rows)}"

    pids = [row['PatientID'] for row in rows]
    assert pids == sorted(pids), "audit_sample.csv is not sorted by PatientID in ascending order"

    expected_data = {
        'P01': {'Condition': 'Cardiac', 'HeartRate': 70.0, 'RollingHR': 72.66666666666667, 'Name': 'Alice Smith'},
        'P02': {'Condition': 'Cardiac', 'HeartRate': 81.0, 'RollingHR': 81.0, 'Name': 'Bob Jones'},
        'P03': {'Condition': 'Resp', 'HeartRate': 88.0, 'RollingHR': 89.33333333333333, 'Name': 'Carol White'},
        'P04': {'Condition': 'Resp', 'HeartRate': 86.0, 'RollingHR': 85.5, 'Name': 'David Brown'},
        'P05': {'Condition': 'Resp', 'HeartRate': 92.0, 'RollingHR': 94.0, 'Name': 'Eve Davis'},
    }

    conditions_seen = set()
    for row in rows:
        pid = row['PatientID']
        assert pid in expected_data, f"Unexpected PatientID {pid} in audit_sample.csv"
        expected = expected_data[pid]
        assert row['Condition'] == expected['Condition'], f"Incorrect Condition for {pid}"
        conditions_seen.add(row['Condition'])
        expected_hash = hashlib.sha256(expected['Name'].encode('utf-8')).hexdigest()[:8].lower()
        assert row['PatientName'] == expected_hash, f"Incorrect PatientName hash for {pid}. Expected {expected_hash}, got {row['PatientName']}"
        hr = float(row['HeartRate'])
        assert abs(hr - expected['HeartRate']) < 1e-5, f"Incorrect HeartRate for {pid}. Expected {expected['HeartRate']}, got {hr}"
        rhr = float(row['RollingHR'])
        assert abs(rhr - expected['RollingHR']) < 1e-5, f"Incorrect RollingHR for {pid}. Expected {expected['RollingHR']}, got {rhr}"

    assert 'Cardiac' in conditions_seen, "Missing Cardiac sample"
    assert 'Resp' in conditions_seen, "Missing Resp sample"

def make_case(case_number):
    token = secrets.token_hex(5)
    start = date(2025, 1, 6) + timedelta(days=case_number * 20)
    group_sizes = [('Cardiac', 2), ('Resp', 3), ('Neuro', 4)]
    rows = []
    metadata = {}
    readings = defaultdict(lambda: defaultdict(list))
    patient_index = 0

    def add(pid, name, condition, day_offset, hour, value, note):
        day = start + timedelta(days=day_offset)
        rows.append([
            f'{day.isoformat()} {hour:02d}:00:00', pid, name, condition,
            str(value), note
        ])
        readings[pid][day].append(float(value))

    for condition, size in group_sizes:
        for local_index in range(size):
            pid = f'{token}-{condition[0]}-{local_index}'
            name = f'Patient {token} {condition} {local_index}'
            metadata[pid] = (name, condition)
            base = 55 + secrets.randbelow(50) + patient_index * 3
            pattern = patient_index % 4
            add(pid, name, condition, 0, 8, base, f'quoted, note "{token}"\ncontinued line')
            if pattern == 0:
                add(pid, name, condition, 2, 9, base + 4, 'middle reading')
            elif pattern == 1:
                add(pid, name, condition, 1, 9, base + 7, 'one day later')
            elif pattern == 3:
                add(pid, name, condition, 2, 9, base - 3, 'late middle reading')
            add(pid, name, condition, 4, 10, base + 10, 'latest first')
            add(pid, name, condition, 4, 18, base + 14, 'latest second\nembedded newline')
            patient_index += 1

    random.SystemRandom().shuffle(rows)
    expected = {}
    latest = start + timedelta(days=4)
    for pid, daily_readings in readings.items():
        daily_means = {d: sum(values) / len(values) for d, values in daily_readings.items()}
        values = []
        previous = math.nan
        missing_run = 0
        for offset in range(5):
            day = start + timedelta(days=offset)
            if day in daily_means:
                value = daily_means[day]
                previous = value
                missing_run = 0
            else:
                missing_run += 1
                value = previous if missing_run <= 1 and not math.isnan(previous) else math.nan
            values.append(value)
        window = [v for v in values[-3:] if not math.isnan(v)]
        name, condition = metadata[pid]
        expected[pid] = {
            'Condition': condition,
            'PatientName': hashlib.sha256(name.encode('utf-8')).hexdigest()[:8],
            'HeartRate': daily_means[latest],
            'RollingHR': sum(window) / len(window),
        }
    return rows, expected, {condition: size // 2 for condition, size in group_sizes}

def write_case(rows):
    with open(RAW, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Timestamp', 'PatientID', 'PatientName', 'Condition', 'HeartRate', 'Notes'])
        writer.writerows(rows)

def validate_dynamic_output(expected, expected_counts):
    assert os.path.isfile(OUTPUT), 'pipeline execution did not create audit_sample.csv'
    with open(OUTPUT, newline='') as f:
        reader = csv.DictReader(f)
        output_rows = list(reader)
        fields = reader.fieldnames

    required = ['PatientID', 'PatientName', 'Condition', 'HeartRate', 'RollingHR']
    assert fields is not None
    for column in required:
        assert column in fields, f'missing output column {column}'
    assert 'Notes' not in fields, 'Notes column was not dropped'
    assert len(output_rows) == sum(expected_counts.values())
    assert [r['PatientID'] for r in output_rows] == sorted(r['PatientID'] for r in output_rows)
    assert Counter(r['Condition'] for r in output_rows) == Counter(expected_counts)

    seen = set()
    for row in output_rows:
        pid = row['PatientID']
        assert pid in expected, f'unexpected dynamically generated PatientID: {pid}'
        assert pid not in seen, f'duplicate PatientID: {pid}'
        seen.add(pid)
        want = expected[pid]
        assert row['Condition'] == want['Condition']
        assert row['PatientName'] == want['PatientName'], f'incorrect SHA256 masking for {pid}'
        assert math.isclose(float(row['HeartRate']), want['HeartRate'], rel_tol=0, abs_tol=1e-7)
        assert math.isclose(float(row['RollingHR']), want['RollingHR'], rel_tol=0, abs_tol=1e-7), f'incorrect rolling mean for {pid}'

def test_pipeline_on_unseen_inputs_via_runner_and_python():
    with open(RAW, 'rb') as f:
        original_raw = f.read()
    try:
        rows, expected, counts = make_case(1)
        write_case(rows)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        subprocess.run([RUNNER], cwd='/home/user', check=True, timeout=30)
        validate_dynamic_output(expected, counts)
        with open(OUTPUT, 'rb') as f:
            first_result = f.read()

        os.remove(OUTPUT)
        subprocess.run([RUNNER], cwd='/home/user', check=True, timeout=30)
        validate_dynamic_output(expected, counts)
        with open(OUTPUT, 'rb') as f:
            assert f.read() == first_result, 'repeated execution was not deterministic'

        rows, expected, counts = make_case(2)
        write_case(rows)
        os.remove(OUTPUT)
        subprocess.run(['python3', PIPELINE], cwd='/home/user', check=True, timeout=30)
        validate_dynamic_output(expected, counts)
    finally:
        with open(RAW, 'wb') as f:
            f.write(original_raw)

def test_runner_really_invokes_pipeline_script():
    with open(PIPELINE, 'rb') as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(PIPELINE).st_mode)
    marker = f'/tmp/pipeline-invoked-{secrets.token_hex(8)}'
    probe = f"#!/usr/bin/env python3\nfrom pathlib import Path\nPath({marker!r}).write_text('called')\n"
    try:
        with open(PIPELINE, 'w') as f:
            f.write(probe)
        os.chmod(PIPELINE, original_mode | stat.S_IXUSR)
        subprocess.run([RUNNER], cwd='/home/user', check=True, timeout=30)
        assert os.path.isfile(marker), 'run_pipeline.sh does not execute /home/user/pipeline.py'
    finally:
        with open(PIPELINE, 'wb') as f:
            f.write(original)
        os.chmod(PIPELINE, original_mode)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
