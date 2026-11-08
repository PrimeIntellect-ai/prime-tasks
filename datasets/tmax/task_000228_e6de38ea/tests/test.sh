#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import secrets
import stat
import subprocess

import pytest

CLEAN_DIR = "/home/user/corpora/clean"
EVIL_DIR = "/home/user/corpora/evil"
SANITIZER = "/home/user/sanitizer"
SOURCE = "/home/user/sanitizer.cpp"
ORACLE = "/app/interp_oracle"
HEADER = b"Timestamp,SensorID,SensorDescription,Value,IsInterpolated"
ID_RE = re.compile(rb"^[A-Z]{3}-[0-9]{4}-[A-F0-9]{4}$")


def normalized_lines(data):
    return [line.strip() for line in data.split(b'\n') if line.strip()]


def run_sanitizer(input_data):
    return subprocess.run(
        [SANITIZER], input=input_data, capture_output=True, timeout=5
    )


def parse_row(line):
    fields = line.split(b',')
    if len(fields) != 5:
        return None

    ts_b, sensor_id, description, value_b, interpolated_b = fields
    try:
        timestamp = int(ts_b.decode('ascii'))
        value = float(value_b.decode('ascii'))
        interpolated = int(interpolated_b.decode('ascii'))
        description.decode('utf-8', errors='strict')
    except (UnicodeDecodeError, ValueError, OverflowError):
        return None

    if not math.isfinite(value) or interpolated not in (0, 1):
        return None

    return {
        'line': line,
        'timestamp': timestamp,
        'sensor_id': sensor_id,
        'value': value,
        'interpolated': interpolated,
        'id_valid': ID_RE.fullmatch(sensor_id) is not None,
    }


def oracle_value(prior, following, target_timestamp):
    result = subprocess.run(
        [ORACLE, str(prior['timestamp']), repr(prior['value']),
         str(following['timestamp']), repr(following['value']),
         str(target_timestamp)],
        capture_output=True, text=True, timeout=3
    )
    assert result.returncode == 0, f"Interpolation oracle failed: {result.stderr}"
    return float(result.stdout.strip())


def expected_output(input_data):
    lines = normalized_lines(input_data)
    if not lines:
        return []
    assert lines[0] == HEADER, "Verifier-generated/input corpus header is malformed"

    parsed = [parse_row(line) for line in lines[1:]]
    expected = [lines[0]]

    for index, row in enumerate(parsed):
        if row is None or not row['id_valid']:
            continue

        if row['interpolated'] == 0:
            expected.append(row['line'])
            continue

        prior = None
        following = None
        for candidate in reversed(parsed[:index]):
            if (candidate is not None and candidate['interpolated'] == 0
                    and candidate['sensor_id'] == row['sensor_id']):
                prior = candidate
                break
        for candidate in parsed[index + 1:]:
            if (candidate is not None and candidate['interpolated'] == 0
                    and candidate['sensor_id'] == row['sensor_id']):
                following = candidate
                break

        if prior is None or following is None:
            continue

        wanted = oracle_value(prior, following, row['timestamp'])
        if abs(row['value'] - wanted) <= 0.0001:
            expected.append(row['line'])

    return expected


def assert_correct(input_data, label):
    result = run_sanitizer(input_data)
    assert result.returncode == 0, f"{label}: sanitizer crashed with code {result.returncode}"
    actual = normalized_lines(result.stdout)
    expected = expected_output(input_data)
    assert actual == expected, (
        f"{label}: incorrect sanitized output\n"
        f"expected={expected!r}\nactual={actual!r}\nstderr={result.stderr!r}"
    )


def test_sanitizer_exists():
    assert os.path.exists(SANITIZER), f"Sanitizer executable not found at {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer at {SANITIZER} is not executable"
    assert stat.S_ISREG(os.stat(SANITIZER).st_mode), "Sanitizer must be a regular executable file"
    with open(SANITIZER, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Sanitizer must be a compiled ELF executable"
    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}"


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))
    assert clean_files, f"No CSV files found in {CLEAN_DIR}"

    modified_files = []
    for file in clean_files:
        with open(file, 'rb') as f:
            input_data = f.read()
        result = run_sanitizer(input_data)
        if result.returncode != 0:
            modified_files.append(os.path.basename(file) + " (crashed)")
            continue
        if normalized_lines(input_data) != normalized_lines(result.stdout):
            modified_files.append(os.path.basename(file))

    assert not modified_files, (
        f"{len(modified_files)} of {len(clean_files)} clean modified: "
        + ', '.join(modified_files)
    )


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.csv"))
    assert evil_files, f"No CSV files found in {EVIL_DIR}"

    incorrect_files = []
    for file in evil_files:
        with open(file, 'rb') as f:
            input_data = f.read()
        result = run_sanitizer(input_data)
        if result.returncode != 0:
            incorrect_files.append(os.path.basename(file) + " (crashed)")
            continue
        if normalized_lines(result.stdout) != expected_output(input_data):
            incorrect_files.append(os.path.basename(file))

    assert not incorrect_files, (
        f"{len(incorrect_files)} of {len(evil_files)} evil corpora sanitized incorrectly: "
        + ', '.join(incorrect_files)
    )


def random_sensor_id():
    letters = ''.join(secrets.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZ') for _ in range(3))
    digits = ''.join(secrets.choice('0123456789') for _ in range(4))
    suffix = ''.join(secrets.choice('ABCDEF0123456789') for _ in range(4))
    return f"{letters}-{digits}-{suffix}"


def make_dynamic_case():
    sensor_a = random_sensor_id()
    sensor_b = random_sensor_id()
    while sensor_b == sensor_a:
        sensor_b = random_sensor_id()

    base = 1700000000 + secrets.randbelow(50000000)
    v0 = float(secrets.randbelow(10000)) / 100.0 - 30.0
    v1 = v0 + float(100 + secrets.randbelow(5000)) / 100.0
    b0 = float(secrets.randbelow(5000)) / 100.0

    prior = {'timestamp': base, 'value': v0}
    following = {'timestamp': base + 20, 'value': v1}
    good_ts = base + 6
    bad_ts = base + 13
    good_value = oracle_value(prior, following, good_ts)
    bad_value = oracle_value(prior, following, bad_ts) + 0.25

    lines = [
        HEADER,
        f"{base},{sensor_a},Raw start α,{v0:.6f},0".encode('utf-8'),
        f"{base + 1},{sensor_a.lower()},Bad identifier,{v0:.6f},0".encode(),
        f"{base + 2},{sensor_b},Other sensor,{b0:.6f},0".encode(),
        f"{good_ts},{sensor_a},Valid gap fill ✓,{good_value:.4f},1".encode('utf-8'),
        f"{base + 8},{sensor_b},Invalid byte ".encode() + b'\xff' + f",{b0:.6f},0".encode(),
        f"{bad_ts},{sensor_a},Wrong interpolation,{bad_value:.4f},1".encode(),
        f"{base + 15},{sensor_b},Malformed flag,{b0:.6f},2".encode(),
        f"{base + 20},{sensor_a},Raw finish Ω,{v1:.6f},0".encode('utf-8'),
        f"{base + 22},{sensor_b},Other raw finish,{b0 + 1.0:.6f},0".encode(),
    ]

    middle = lines[1:]
    random.SystemRandom().shuffle(middle)

    # Preserve the temporal/stream ordering needed for A's nearest anchors while
    # randomizing unrelated rows around the generated case.
    a_start = lines[1]
    a_good = lines[4]
    a_bad = lines[6]
    a_finish = lines[8]
    unrelated = [line for line in middle if line not in (a_start, a_good, a_bad, a_finish)]
    split1 = secrets.randbelow(len(unrelated) + 1)
    split2 = split1 + secrets.randbelow(len(unrelated) - split1 + 1)
    ordered = (unrelated[:split1] + [a_start] + unrelated[split1:split2]
               + [a_good, a_bad, a_finish] + unrelated[split2:])
    return b'\n'.join([HEADER] + ordered) + b'\n'


def test_generated_unexposed_cases():
    for index in range(10):
        assert_correct(make_dynamic_case(), f"generated case {index}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
