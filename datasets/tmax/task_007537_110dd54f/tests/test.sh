#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import stat
import string
import subprocess
from pathlib import Path

import pytest

BASE = Path('/home/user/config_tracker')
INPUT = BASE / 'changes.csv'
OUTPUT = BASE / 'processed_anomalies.csv'


def test_processed_anomalies_exists():
    """Check if processed_anomalies.csv exists."""
    assert OUTPUT.is_file(), f"File {OUTPUT} does not exist. The pipeline did not produce the expected output file."


def test_processed_anomalies_contents():
    """Keep the original exact check for the supplied fixture."""
    if not OUTPUT.is_file():
        pytest.fail(f"Cannot check contents because {OUTPUT} does not exist.")

    expected_content = """timestamp,server_id,normalized_config_key,size_bytes,rolling_avg,is_anomaly
2023-10-01T10:00:00Z,srv-01,db_port,10,10,NO
2023-10-01T10:05:00Z,srv-01,max_connections,50,30,NO
2023-10-01T10:10:00Z,srv-02,cache_size,20,20,NO
2023-10-01T10:15:00Z,srv-01,timeout_policy,60,40,NO
2023-10-01T10:20:00Z,srv-01,ssl_cert,200,103,NO
2023-10-01T10:25:00Z,srv-02,workers,20,20,NO
2023-10-01T10:30:00Z,srv-02,features,100,46,YES"""

    with OUTPUT.open('r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} rows (including header), but got {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def find_pipeline_scripts():
    candidates = []
    for path in Path('/home/user').rglob('*'):
        try:
            mode = path.stat().st_mode
            if not path.is_file() or not (mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)):
                continue
            data = path.read_bytes()
        except (OSError, UnicodeError):
            continue
        first_line = data.splitlines()[0].decode('utf-8', errors='ignore') if data else ''
        if not first_line.startswith('#!') or not any(shell in first_line for shell in ('bash', '/sh', 'dash')):
            continue
        text = data.decode('utf-8', errors='ignore')
        if 'changes.csv' in text and 'processed_anomalies.csv' in text:
            candidates.append(path)
    return candidates


def make_fixture():
    rng = random.SystemRandom()
    token = ''.join(rng.choice(string.ascii_uppercase) for _ in range(10))
    q = rng.randint(7, 19)
    month = rng.randint(1, 9)
    day = rng.randint(10, 27)
    prefix = f"2025-{month:02d}-{day:02d}T12:"
    a, b, c = f"node-a-{token.lower()}", f"node-b-{token.lower()}", f"node-c-{token.lower()}"

    records = [
        [prefix + '00:00Z', a, f'BASE {token} Size', 'plain', q],
        [prefix + '01:00Z', b, f'Worker {token} COUNT', '{\n  "workers": 2,\n  "enabled": true\n}', 2*q],
        [prefix + '02:00Z', a, f'MAX {token} Connections', 'first line\nsecond line, with comma', q+2],
        [prefix + '03:00Z', c, f'Cache {token} Mode', '"quoted" text\ncontinued', 5],
        [prefix + '04:00Z', a, f'Burst {token} LIMIT', '{\n  "burst": "large"\n}', 10*q+7],
        [prefix + '04:00Z', b, f'Retry {token} Delay', '500ms', 2*q+3],
        [prefix + '05:00Z', a, f'After {token} Burst', 'normal', q+1],
        [prefix + '06:00Z', b, f'Payload {token} Size', 'alpha\nbeta\ngamma', 14*q+9],
        [prefix + '07:00Z', c, f'Cache {token} Limit', 'small', 5],
        [prefix + '08:00Z', c, f'Cache {token} Spike', 'multi\nline, "value"', 40],
    ]
    rng.shuffle(records)
    return records


def encode_fixture(records):
    buf = io.StringIO(newline='')
    writer = csv.writer(buf, lineterminator='\n')
    writer.writerow(['timestamp', 'server_id', 'config_key', 'config_value', 'size_bytes'])
    writer.writerows(records)
    return buf.getvalue().encode('utf-8')


def expected_output(records):
    histories = {}
    lines = ['timestamp,server_id,normalized_config_key,size_bytes,rolling_avg,is_anomaly']
    for timestamp, server, key, _value, size in sorted(records, key=lambda r: (r[0], r[1])):
        size = int(size)
        history = histories.setdefault(server, [])
        window = (history + [size])[-3:]
        avg = sum(window) // len(window)
        history.append(size)
        normalized = key.lower().replace(' ', '_')
        anomaly = 'YES' if size > 2 * avg else 'NO'
        lines.append(f'{timestamp},{server},{normalized},{size},{avg},{anomaly}')
    return lines


def run_candidate(candidate, records):
    INPUT.write_bytes(encode_fixture(records))
    try:
        OUTPUT.unlink()
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ['runuser', '-u', 'user', '--', str(candidate)],
        cwd=str(BASE),
        env={**os.environ, 'HOME': '/home/user', 'USER': 'user', 'LOGNAME': 'user'},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    if result.returncode != 0 or not OUTPUT.is_file():
        return False

    with OUTPUT.open('r', encoding='utf-8') as f:
        actual = [line.strip() for line in f if line.strip()]
    return actual == expected_output(records)


def test_executable_pipeline_on_changed_inputs():
    candidates = find_pipeline_scripts()
    assert candidates, 'No executable shell pipeline that reads changes.csv and writes processed_anomalies.csv was found under /home/user.'

    input_bytes = INPUT.read_bytes()
    input_mode = stat.S_IMODE(INPUT.stat().st_mode)
    output_existed = OUTPUT.exists()
    output_bytes = OUTPUT.read_bytes() if output_existed else None
    output_mode = stat.S_IMODE(OUTPUT.stat().st_mode) if output_existed else None

    fixtures = [make_fixture(), make_fixture()]
    passing = []
    try:
        for candidate in candidates:
            try:
                if all(run_candidate(candidate, fixture) for fixture in fixtures):
                    passing.append(candidate)
            except (OSError, subprocess.SubprocessError, UnicodeError):
                continue
    finally:
        INPUT.write_bytes(input_bytes)
        os.chmod(INPUT, input_mode)
        if output_existed:
            OUTPUT.write_bytes(output_bytes)
            os.chmod(OUTPUT, output_mode)
        else:
            try:
                OUTPUT.unlink()
            except FileNotFoundError:
                pass

    assert passing, 'No executable pipeline correctly handled randomized CSVs with embedded newlines, sorting, normalization, rolling averages, and anomaly detection.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
