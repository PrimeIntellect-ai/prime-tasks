#!/bin/bash
set -e
mkdir -p /logs/verifier

cat > /tmp/verify_task.py <<'PY'
import csv
import math
import os
import shutil
import stat
import subprocess
import sys
from fractions import Fraction
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'raw_sensors.csv'
RESULT = HOME / 'result.txt'
CASES = Path('/tmp/sensor_verifier_cases')
CASES.mkdir(exist_ok=True)


def value_for(t, s):
    return ((t * 7919 + s * 104729) % 1000003) + s


def make_small(path):
    timestamps = [3, 8, 14, 23, 37, 52, 70]
    missing = {(2, 2), (4, 5), (5, 1)}
    total = Fraction(0)
    with path.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'S1', 'S2', 'S3', 'S4', 'S5'])
        for row_index, t in enumerate(timestamps):
            row = [t]
            for s in range(1, 6):
                def val(ts):
                    return ts * ts * (s + 1) + 17 * s * ts + 31 * s
                if (row_index, s) in missing:
                    row.append('')
                    t0 = timestamps[row_index - 1]
                    t1 = timestamps[row_index + 1]
                    interpolated = Fraction(val(t0) * (t1 - t) + val(t1) * (t - t0), t1 - t0)
                    total += interpolated
                else:
                    v = val(t)
                    row.append(v)
                    total += v
    return round(float(total), 2)


def make_large(path):
    # Large enough that materializing all parsed rows exceeds the imposed memory
    # budget, while a row-streaming or bounded-chunk implementation fits easily.
    nrows = 800000
    doubled_total = 0
    with path.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'S1', 'S2', 'S3', 'S4', 'S5'])
        for t in range(1, nrows + 1):
            row = [t]
            for s in range(1, 6):
                missing = 1 < t < nrows and (t - s * 137) % 10007 == 0
                if missing:
                    row.append('')
                    doubled_total += value_for(t - 1, s) + value_for(t + 1, s)
                else:
                    v = value_for(t, s)
                    row.append(v)
                    doubled_total += 2 * v
            writer.writerow(row)
    return doubled_total / 2.0


def make_original(path):
    with path.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'S1', 'S2', 'S3', 'S4', 'S5'])
        for t in range(1, 501):
            row = [t]
            for s in range(1, 6):
                if (t, s) in {(10, 2), (45, 4), (100, 1), (350, 5)}:
                    row.append('')
                else:
                    row.append(t ** 2 + s)
            writer.writerow(row)


def read_result(expected):
    assert RESULT.exists(), f'The file {RESULT} does not exist.'
    assert RESULT.is_file(), f'The path {RESULT} is not a file.'
    content = RESULT.read_text().strip()
    assert content, 'The result.txt file is empty.'
    try:
        actual = float(content)
    except ValueError:
        raise AssertionError(f"The content of result.txt ({content!r}) is not a valid number.")
    assert math.isfinite(actual), 'The result must be a finite number.'
    assert abs(actual - expected) <= 1e-6, f'Expected the total sum to be {expected}, but got {actual}.'


def memory_limit():
    import resource
    limit = 256 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))


def run_script(script, source_csv, expected, limited=False, timeout=120):
    shutil.copyfile(source_csv, RAW)
    try:
        RESULT.unlink()
    except FileNotFoundError:
        pass
    completed = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(script.parent),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        preexec_fn=memory_limit if limited else None,
    )
    assert completed.returncode == 0, (
        f'{script} exited with status {completed.returncode}. '\
        f'stderr: {completed.stderr[-2000:]}'
    )
    read_result(expected)


small = CASES / 'small.csv'
large = CASES / 'large.csv'
original = CASES / 'original.csv'
small_expected = make_small(small)
large_expected = make_large(large)
make_original(original)

scripts = []
for path in HOME.rglob('*.py'):
    try:
        mode = path.lstat().st_mode
    except OSError:
        continue
    if stat.S_ISREG(mode):
        scripts.append(path)
assert scripts, 'No Python processing script was created under /home/user.'

failures = []
passed = None
for script in sorted(scripts):
    try:
        # Nonuniform timestamps ensure interpolation uses the surrounding
        # timestamps rather than merely averaging adjacent rows.
        run_script(script, small, small_expected, timeout=30)
        # Exercise the same artifact on a large, independently generated input
        # under a bounded-memory environment.
        run_script(script, large, large_expected, limited=True, timeout=120)
        # Preserve the original verifier's exact assertion on the supplied data.
        run_script(script, original, 208966254.0, timeout=30)
        passed = script
        break
    except Exception as exc:
        failures.append(f'{script}: {exc}')

assert passed is not None, 'No Python script correctly processed all test inputs:\n' + '\n'.join(failures)

# Explicitly retain the original final-state checks.
assert RESULT.exists(), f'The file {RESULT} does not exist.'
assert RESULT.is_file(), f'The path {RESULT} is not a file.'
content = RESULT.read_text().strip()
assert content, 'The result.txt file is empty.'
try:
    result_val = float(content)
except ValueError:
    raise AssertionError(f"The content of result.txt ({content!r}) is not a valid number.")
expected_val = 208966254.0
assert result_val == expected_val, f'Expected the total sum to be {expected_val}, but got {result_val}.'
PY

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
