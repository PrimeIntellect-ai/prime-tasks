#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/ml_prep')
REF_PATH = Path('/home/user/data/reference.csv')
RAW_PATH = Path('/home/user/data/raw.csv')
CLEANED_PATH = Path('/home/user/data/cleaned.csv')
REPORT_PATH = Path('/home/user/report.md')


def compute_expected_values():
    if not REF_PATH.exists() or not RAW_PATH.exists():
        return None

    ref_signals = []
    with REF_PATH.open('r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ref_signals.append(float(row['signal']))

    raw_data = []
    with RAW_PATH.open('r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_data.append((float(row['time']), float(row['signal'])))

    ref_sorted = sorted(ref_signals)
    raw_sorted = sorted(sig for _, sig in raw_data)
    wasserstein = sum(abs(r - w) for r, w in zip(ref_sorted, raw_sorted)) / len(ref_sorted)

    n = len(raw_data)
    mean_x = sum(t for t, _ in raw_data) / n
    mean_y = sum(sig for _, sig in raw_data) / n
    cov = sum((t - mean_x) * (sig - mean_y) for t, sig in raw_data)
    var = sum((t - mean_x) ** 2 for t, _ in raw_data)
    m = cov / var
    c = mean_y - m * mean_x

    cleaned_rows = []
    for t, sig in raw_data:
        pred = m * t + c
        residual = sig - pred
        if abs(residual) <= 2.0:
            cleaned_rows.append((t, sig))

    return {
        'wasserstein': wasserstein,
        'm': m,
        'c': c,
        'cleaned_count': len(cleaned_rows),
        'cleaned_rows': cleaned_rows,
    }


def write_challenge(case_number):
    token = secrets.randbelow(10000)
    start = 0.5 + (token % 13) / 10.0 + case_number * 0.17
    step = 0.75 + ((token // 13) % 7) / 20.0
    slope = 0.85 + ((token // 91) % 17) / 20.0
    intercept = -1.3 + ((token // 1547) % 11) / 10.0
    outlier_index = 3 if case_number == 0 else 4
    outlier_size = 6.2 + (token % 9) / 10.0
    ref_jitter = [0.12, -0.08, 0.05, -0.11, 0.09, -0.04, 0.07, -0.03]
    raw_jitter = [-0.16, 0.11, -0.07, 0.04, -0.10, 0.14, -0.05, 0.08]

    ref_rows = []
    raw_rows = []
    for i in range(8):
        t = start + i * step
        base = intercept + slope * t
        ref_rows.append((t, base + ref_jitter[i]))
        raw_signal = base + raw_jitter[i]
        if i == outlier_index:
            raw_signal += outlier_size
        raw_rows.append((t, raw_signal))

    REF_PATH.parent.mkdir(parents=True, exist_ok=True)
    with REF_PATH.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['time', 'signal'])
        writer.writerows((f'{t:.6f}', f'{s:.6f}') for t, s in ref_rows)
    with RAW_PATH.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['time', 'signal'])
        writer.writerows((f'{t:.6f}', f'{s:.6f}') for t, s in raw_rows)


def assert_outputs(expected):
    assert REPORT_PATH.is_file(), f'Report file missing at {REPORT_PATH}'
    with REPORT_PATH.open('r') as f:
        content = f.read()

    expected_w_str = f"{expected['wasserstein']:.2f}"
    expected_m_str = f"{expected['m']:.2f}"
    expected_c_str = f"{expected['c']:.2f}"
    expected_count_str = str(expected['cleaned_count'])

    assert re.search(r'- 1D Wasserstein Distance:\s*' + re.escape(expected_w_str), content), \
        f'Report missing or incorrect 1D Wasserstein Distance. Expected: {expected_w_str}'
    assert re.search(r'- Regression Slope \(m\):\s*' + re.escape(expected_m_str), content), \
        f'Report missing or incorrect Regression Slope (m). Expected: {expected_m_str}'
    assert re.search(r'- Regression Intercept \(c\):\s*' + re.escape(expected_c_str), content), \
        f'Report missing or incorrect Regression Intercept (c). Expected: {expected_c_str}'
    assert re.search(r'- Cleaned Rows Retained:\s*' + re.escape(expected_count_str), content), \
        f'Report missing or incorrect Cleaned Rows Retained. Expected: {expected_count_str}'

    expected_lines = [
        '# Data Preparation Report',
        f'- 1D Wasserstein Distance: {expected_w_str}',
        f'- Regression Slope (m): {expected_m_str}',
        f'- Regression Intercept (c): {expected_c_str}',
        f'- Cleaned Rows Retained: {expected_count_str}',
    ]
    assert content.splitlines() == expected_lines, \
        'report.md must contain exactly the five specified lines'

    assert CLEANED_PATH.is_file(), f'Cleaned CSV file missing at {CLEANED_PATH}'
    actual_rows = []
    with CLEANED_PATH.open('r', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None
        assert 'time' in reader.fieldnames and 'signal' in reader.fieldnames, \
            "Cleaned CSV header must contain 'time' and 'signal'"
        assert reader.fieldnames == ['time', 'signal'], \
            "Cleaned CSV header must be exactly 'time,signal'"
        for row in reader:
            actual_rows.append((float(row['time']), float(row['signal'])))

    assert len(actual_rows) == expected['cleaned_count'], \
        f"Cleaned CSV should have {expected['cleaned_count']} rows, found {len(actual_rows)}"
    for expected_row, actual_row in zip(expected['cleaned_rows'], actual_rows):
        assert abs(expected_row[0] - actual_row[0]) < 1e-6, \
            f'Time value mismatch in cleaned.csv: expected {expected_row[0]}, got {actual_row[0]}'
        assert abs(expected_row[1] - actual_row[1]) < 1e-6, \
            f'Signal value mismatch in cleaned.csv: expected {expected_row[1]}, got {actual_row[1]}'


def test_rust_project_builds_runs_and_produces_outputs():
    assert PROJECT.is_dir(), f'Rust project missing at {PROJECT}'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing'
    assert (PROJECT / 'src').is_dir(), 'Rust src directory is missing'
    assert any((PROJECT / 'src').rglob('*.rs')), 'No Rust source files found under src/'

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['CARGO_HOME'] = '/home/user/.cargo'

    build = subprocess.run(
        ['cargo', 'build', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert build.returncode == 0, f'Cargo project failed to compile:\n{build.stdout}'

    for case_number in range(2):
        write_challenge(case_number)
        expected = compute_expected_values()
        assert expected is not None, 'Verifier challenge data could not be read'

        REPORT_PATH.unlink(missing_ok=True)
        CLEANED_PATH.unlink(missing_ok=True)

        run = subprocess.run(
            ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
            cwd=PROJECT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=90,
        )
        assert run.returncode == 0, f'Rust pipeline failed to execute:\n{run.stdout}'
        assert_outputs(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
