#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import sqlite3
import subprocess
import tempfile

import cv2
import pytest


def read_metrics(path):
    with open(path, newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    assert header == ['frame_index', 'intensity']
    parsed = []
    for row in rows:
        assert len(row) == 2
        index = int(row[0])
        value = float(row[1])
        assert math.isfinite(value)
        parsed.append((index, value))
    return parsed


def expected_video_intensities():
    cap = cv2.VideoCapture('/app/data/dashboard.mp4')
    assert cap.isOpened(), 'Could not open dashboard.mp4'
    values = []
    try:
        for _ in range(30):
            ok, frame = cap.read()
            assert ok, 'dashboard.mp4 contains fewer than 30 frames'
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            values.append(float(gray.mean()))
    finally:
        cap.release()
    return values


def assert_rows_match(rows, expected, tolerance=1e-7):
    assert len(rows) == len(expected)
    for i, ((index, value), expected_value) in enumerate(zip(rows, expected)):
        assert index == i
        assert math.isclose(value, expected_value, rel_tol=0.0, abs_tol=tolerance), \
            f'Value mismatch at frame {i}: got {value}, expected {expected_value}'


def test_adversarial_corpus():
    script_path = '/home/user/validate.py'
    assert os.path.isfile(script_path), f'Validation script missing: {script_path}'

    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]

    clean_failures = []
    for cf in clean_files:
        result = subprocess.run(['python3', script_path, cf], capture_output=True, timeout=5)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        result = subprocess.run(['python3', script_path, ef], capture_output=True, timeout=5)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(ef))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")
    assert not error_msgs, ' | '.join(error_msgs)


def test_validator_generated_cases():
    script = '/home/user/validate.py'
    rng = random.SystemRandom()
    count = rng.randint(4, 11)
    valid_values = [0.0, 255.0] + [rng.uniform(0.001, 254.999) for _ in range(count - 2)]

    valid_cases = [
        'frame_index,intensity\n' + ''.join(f'{i},{v:.12g}\n' for i, v in enumerate(valid_values)),
        'frame_index,intensity\n0,1e-3\n1,2.5E+2\n2,255.0\n',
    ]
    invalid_cases = [
        'frame,intensity\n0,1\n',
        'frame_index,intensity,extra\n0,1,x\n',
        'frame_index,intensity\n0,1,extra\n',
        'frame_index,intensity\n0,1\n2,2\n',
        'frame_index,intensity\n0,1\n0,2\n',
        'frame_index,intensity\n1,1\n2,2\n',
        'frame_index,intensity\n0.0,1\n',
        'frame_index,intensity\n0,\n',
        'frame_index,intensity\n0,nan\n',
        'frame_index,intensity\n0,inf\n',
        'frame_index,intensity\n0,-0.0001\n',
        'frame_index,intensity\n0,255.0001\n',
        'frame_index,intensity\n0,abc\n',
        'frame_index,intensity\n0,1\n1\n',
    ]

    with tempfile.TemporaryDirectory() as td:
        for n, content in enumerate(valid_cases):
            path = os.path.join(td, f'generated_valid_{rng.getrandbits(64)}_{n}.csv')
            with open(path, 'w', newline='') as f:
                f.write(content)
            result = subprocess.run(['python3', script, path], capture_output=True, timeout=5)
            assert result.returncode == 0, f'Validator rejected generated valid case {n}'

        for n, content in enumerate(invalid_cases):
            path = os.path.join(td, f'generated_invalid_{rng.getrandbits(64)}_{n}.csv')
            with open(path, 'w', newline='') as f:
                f.write(content)
            result = subprocess.run(['python3', script, path], capture_output=True, timeout=5)
            assert result.returncode == 1, f'Validator did not return 1 for generated invalid case {n}'


def test_raw_metrics_csv():
    raw_path = '/home/user/raw_metrics.csv'
    assert os.path.isfile(raw_path), f'Raw metrics missing: {raw_path}'
    rows = read_metrics(raw_path)
    assert len(rows) == 30, 'raw_metrics.csv should have exactly 30 data rows'
    for i, (index, intensity) in enumerate(rows):
        assert index == i, f'Expected frame_index {i}, got {index}'
        assert 0.0 <= intensity <= 255.0
    assert_rows_match(rows, expected_video_intensities(), tolerance=1.0)


def test_filled_metrics_csv():
    filled_path = '/home/user/filled_metrics.csv'
    assert os.path.isfile(filled_path), f'Filled metrics missing: {filled_path}'

    with open(filled_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['frame_index', 'intensity'], 'Incorrect header in filled_metrics.csv'
        rows = list(reader)
        assert len(rows) == 30, 'filled_metrics.csv should have exactly 30 data rows'
        parsed = []
        for i, row in enumerate(rows):
            assert len(row) == 2
            assert int(row[0]) == i, f'Expected frame_index {i}, got {row[0]}'
            intensity = float(row[1])
            assert math.isfinite(intensity)
            assert 0.0 <= intensity <= 255.0, f'Intensity out of bounds: {intensity}'
            parsed.append((i, intensity))

    assert_rows_match(parsed, expected_video_intensities(), tolerance=1.0)


def test_summary_csv():
    summary_path = '/home/user/summary.csv'
    assert os.path.isfile(summary_path), f'Summary CSV missing: {summary_path}'

    filled = read_metrics('/home/user/filled_metrics.csv')
    expected_averages = [sum(v for _, v in filled[start:start + 10]) / 10.0 for start in (0, 10, 20)]

    with open(summary_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['window_start', 'avg_intensity'], 'Incorrect header in summary.csv'
        rows = list(reader)
        assert len(rows) == 3, 'summary.csv should have exactly 3 data rows'
        expected_starts = [0, 10, 20]
        for i, row in enumerate(rows):
            assert len(row) == 2
            assert int(row[0]) == expected_starts[i], f'Expected window_start {expected_starts[i]}, got {row[0]}'
            actual = float(row[1])
            assert math.isfinite(actual)
            assert math.isclose(actual, expected_averages[i], rel_tol=0.0, abs_tol=1e-6)


def test_metrics_database_matches_filled():
    db_path = '/home/user/metrics.db'
    assert os.path.isfile(db_path), f'Metrics database missing: {db_path}'
    expected = read_metrics('/home/user/filled_metrics.csv')
    con = sqlite3.connect(db_path)
    try:
        columns = [row[1] for row in con.execute('PRAGMA table_info(logs)')]
        assert columns == ['frame_index', 'intensity'], 'logs table has incorrect columns'
        rows = con.execute('SELECT frame_index, intensity FROM logs ORDER BY CAST(frame_index AS INTEGER)').fetchall()
    finally:
        con.close()
    parsed = [(int(index), float(value)) for index, value in rows]
    assert_rows_match(parsed, [value for _, value in expected], tolerance=1e-6)


def test_aggregate_script_executes_on_unseen_data():
    script = '/home/user/aggregate.sh'
    assert os.path.isfile(script), f'Aggregation script missing: {script}'
    rng = random.SystemRandom()
    values = [rng.uniform(1.0, 254.0) + i / 10000.0 for i in range(30)]

    with open('/home/user/filled_metrics.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['frame_index', 'intensity'])
        for i, value in enumerate(values):
            writer.writerow([i, format(value, '.15g')])

    for path in ('/home/user/metrics.db', '/home/user/summary.csv'):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(['bash', script], cwd='/home/user', capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f'aggregate.sh failed: {result.stderr}'
    assert os.path.isfile('/home/user/metrics.db')
    assert os.path.isfile('/home/user/summary.csv')

    con = sqlite3.connect('/home/user/metrics.db')
    try:
        columns = [row[1] for row in con.execute('PRAGMA table_info(logs)')]
        assert columns == ['frame_index', 'intensity']
        db_rows = con.execute('SELECT frame_index, intensity FROM logs ORDER BY CAST(frame_index AS INTEGER)').fetchall()
    finally:
        con.close()
    parsed = [(int(i), float(v)) for i, v in db_rows]
    assert_rows_match(parsed, values, tolerance=1e-9)

    with open('/home/user/summary.csv', newline='') as f:
        rows = list(csv.reader(f))
    assert rows[0] == ['window_start', 'avg_intensity']
    assert len(rows) == 4
    for window, start in enumerate((0, 10, 20)):
        assert len(rows[window + 1]) == 2
        assert int(rows[window + 1][0]) == start
        expected_average = sum(values[start:start + 10]) / 10.0
        assert math.isclose(float(rows[window + 1][1]), expected_average, rel_tol=0.0, abs_tol=1e-8)


def test_cron_schedule():
    cron_path = '/home/user/cron_schedule.txt'
    assert os.path.isfile(cron_path), f'Cron schedule file missing: {cron_path}'
    with open(cron_path, 'r') as f:
        content = f.read().strip()
    assert '0 * * * *' in content, 'Cron expression should run every hour on the hour (0 * * * *)'
    assert '/home/user/aggregate.sh' in content, 'Cron expression should execute /home/user/aggregate.sh'
    assert re.fullmatch(r'0 \* \* \* \* /home/user/aggregate\.sh', content), 'cron_schedule.txt must contain only the requested cron entry'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
