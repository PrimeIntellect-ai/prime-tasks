#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import subprocess
import tempfile


def get_valid_rows(raw_path):
    valid_rows = []
    with open(raw_path, 'r') as f:
        for line in f:
            if line.count(',') == 4:
                parts = line.strip().split(',')
                try:
                    ts = int(parts[0])
                    temp = float(parts[2])
                    hum = float(parts[3])
                    valid_rows.append((ts, temp, hum))
                except ValueError:
                    pass
    return valid_rows


def get_expected_resampled(valid_rows):
    if not valid_rows:
        return []
    first_ts = valid_rows[0][0]
    last_ts = valid_rows[-1][0]
    resampled = []
    for target_ts in range(first_ts, last_ts + 1, 60):
        latest = None
        for row in valid_rows:
            if row[0] <= target_ts:
                latest = row
            else:
                break
        if latest:
            resampled.append((target_ts, latest[1], latest[2]))
    return resampled


def get_expected_stratified(resampled_rows):
    cold, mod, hot = [], [], []
    for row in resampled_rows:
        temp = row[1]
        if temp < 20.0 and len(cold) < 3:
            cold.append(row)
        elif 20.0 <= temp < 30.0 and len(mod) < 3:
            mod.append(row)
        elif temp >= 30.0 and len(hot) < 3:
            hot.append(row)
    return cold + mod + hot


def format_rows(rows):
    return [f"{ts},{temp:.1f},{hum:.1f}" for ts, temp, hum in rows]


def read_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def assert_original_outputs():
    valid_rows = get_valid_rows('/home/user/raw_data.csv')
    expected_resampled = get_expected_resampled(valid_rows)
    assert read_lines('/home/user/resampled.csv') == format_rows(expected_resampled)
    expected_stratified = get_expected_stratified(expected_resampled)
    assert read_lines('/home/user/stratified.csv') == format_rows(expected_stratified)


def test_files_exist():
    expected_files = [
        '/home/user/clean_resample.c',
        '/home/user/clean_resample',
        '/home/user/stratify.sh',
        '/home/user/resampled.csv',
        '/home/user/stratified.csv'
    ]
    for fpath in expected_files:
        assert os.path.exists(fpath), f"Required file missing: {fpath}"
        assert os.path.isfile(fpath), f"Expected a file but found something else: {fpath}"
    assert os.access('/home/user/clean_resample', os.X_OK), '/home/user/clean_resample is not executable.'
    assert os.access('/home/user/stratify.sh', os.X_OK), '/home/user/stratify.sh is not executable.'
    with open('/home/user/clean_resample', 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/clean_resample is not a compiled executable.'


def test_resampled_csv():
    raw_path = '/home/user/raw_data.csv'
    assert os.path.exists(raw_path), f"Missing {raw_path} to compute expected results."
    expected_lines = format_rows(get_expected_resampled(get_valid_rows(raw_path)))
    actual_lines = read_lines('/home/user/resampled.csv')
    assert actual_lines == expected_lines, (
        f"resampled.csv content is incorrect.\n"
        f"Expected {len(expected_lines)} lines, got {len(actual_lines)} lines.\n"
        f"Expected first line: {expected_lines[0] if expected_lines else 'None'}\n"
        f"Actual first line: {actual_lines[0] if actual_lines else 'None'}"
    )


def test_stratified_csv():
    valid_rows = get_valid_rows('/home/user/raw_data.csv')
    expected_lines = format_rows(get_expected_stratified(get_expected_resampled(valid_rows)))
    actual_lines = read_lines('/home/user/stratified.csv')
    assert actual_lines == expected_lines, (
        f"stratified.csv content is incorrect.\n"
        f"Expected exactly 9 lines (3 cold, 3 moderate, 3 hot), got {len(actual_lines)} lines.\n"
        f"Expected: {expected_lines}\nActual: {actual_lines}"
    )


def test_artifacts_execute_and_handle_unseen_inputs():
    raw_path = '/home/user/raw_data.csv'
    with open(raw_path, 'rb') as f:
        original_raw_hash = hashlib.sha256(f.read()).digest()

    rebuilt = '/tmp/clean_resample_rebuilt'
    subprocess.run(
        ['gcc', '/home/user/clean_resample.c', '-o', rebuilt],
        check=True, timeout=20, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    rng = random.SystemRandom()
    base = rng.randrange(200000, 900000)
    readings = [
        (0, rng.randrange(100, 190) / 10.0, rng.randrange(300, 500) / 10.0),
        (25, rng.randrange(190, 250) / 10.0, rng.randrange(400, 600) / 10.0),
        (55, rng.randrange(250, 310) / 10.0, rng.randrange(450, 650) / 10.0),
        (80, rng.randrange(120, 200) / 10.0, rng.randrange(350, 550) / 10.0),
        (145, rng.randrange(200, 300) / 10.0, rng.randrange(400, 700) / 10.0),
        (190, rng.randrange(300, 390) / 10.0, rng.randrange(450, 750) / 10.0),
        (260, rng.randrange(310, 410) / 10.0, rng.randrange(500, 800) / 10.0),
    ]

    with tempfile.TemporaryDirectory() as td:
        dynamic_raw = os.path.join(td, 'raw.csv')
        with open(dynamic_raw, 'w') as f:
            for index, (offset, temp, hum) in enumerate(readings):
                f.write(f"{base + offset},S{index},{temp:.1f},{hum:.1f},ok\n")
                if index == 2:
                    f.write('malformed,continuation\n')
            f.write('not,a,valid,row,with,too,many,commas\n')
        expected = format_rows(get_expected_resampled(get_valid_rows(dynamic_raw)))

        for index, executable in enumerate(('/home/user/clean_resample', rebuilt)):
            output = os.path.join(td, f'out{index}.csv')
            subprocess.run([executable, dynamic_raw, output], check=True, timeout=10)
            assert os.path.isfile(output), f"{executable} did not create its output file"
            assert read_lines(output) == expected, f"{executable} failed an unseen input"

    categories = ['cold', 'moderate', 'hot'] * 4
    dynamic_rows = []
    strat_base = rng.randrange(1000000, 2000000)
    for i, category in enumerate(categories):
        if category == 'cold':
            temp = rng.randrange(50, 199) / 10.0
        elif category == 'moderate':
            temp = rng.randrange(200, 299) / 10.0
        else:
            temp = rng.randrange(300, 450) / 10.0
        hum = rng.randrange(200, 900) / 10.0
        dynamic_rows.append((strat_base + i * 60, temp, hum))

    with open('/home/user/resampled.csv', 'w') as f:
        for line in format_rows(dynamic_rows):
            f.write(line + '\n')
    if os.path.exists('/home/user/stratified.csv'):
        os.unlink('/home/user/stratified.csv')
    subprocess.run(
        ['/home/user/stratify.sh', '/home/user/resampled.csv'],
        cwd='/home/user', check=True, timeout=10
    )
    expected_stratified = format_rows(get_expected_stratified(dynamic_rows))
    assert os.path.isfile('/home/user/stratified.csv'), 'stratify.sh did not create stratified.csv'
    assert read_lines('/home/user/stratified.csv') == expected_stratified, 'stratify.sh failed an unseen input'

    for path in ('/home/user/resampled.csv', '/home/user/stratified.csv'):
        if os.path.exists(path):
            os.unlink(path)
    subprocess.run(
        ['/home/user/clean_resample', raw_path, '/home/user/resampled.csv'],
        cwd='/home/user', check=True, timeout=10
    )
    subprocess.run(
        ['/home/user/stratify.sh', '/home/user/resampled.csv'],
        cwd='/home/user', check=True, timeout=10
    )
    assert_original_outputs()

    with open(raw_path, 'rb') as f:
        assert hashlib.sha256(f.read()).digest() == original_raw_hash, 'raw_data.csv was modified'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
