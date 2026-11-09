#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import subprocess
from collections import defaultdict

HOME = '/home/user'
RAW = os.path.join(HOME, 'raw_events.csv')
REPORT = os.path.join(HOME, 'anomalies_report.csv')
PIPELINE = os.path.join(HOME, 'pipeline.sh')
SOURCE = os.path.join(HOME, 'analyzer.c')


def expected_lines(raw_text):
    records = []
    for row in csv.reader(raw_text.splitlines()):
        if not row or len(row) < 5:
            continue
        records.append({
            'timestamp': int(row[0]),
            'translation_id': row[1],
            'quality_score': float(row[4]),
        })

    last_occurrences = {}
    for rec in records:
        last_occurrences[rec['translation_id']] = rec
    deduped = sorted(last_occurrences.values(), key=lambda x: x['timestamp'])

    buckets = defaultdict(list)
    for rec in deduped:
        buckets[rec['timestamp'] // 3600].append(rec['quality_score'])

    result = []
    hourly_averages = []
    for bucket_id in sorted(buckets):
        scores = buckets[bucket_id]
        hourly_avg = sum(scores) / len(scores)
        hourly_averages.append(hourly_avg)
        window = hourly_averages[-3:]
        rolling_avg = sum(window) / len(window)
        anomaly = 1 if hourly_avg < rolling_avg - 5.0 else 0
        result.append(f'{bucket_id},{hourly_avg:.2f},{rolling_avg:.2f},{anomaly}')
    return result


def read_report():
    assert os.path.isfile(REPORT), f'{REPORT} was not generated.'
    with open(REPORT) as f:
        lines = [line.strip() for line in f if line.strip()]
    for line in lines:
        assert re.fullmatch(r'-?\d+,-?\d+\.\d{2},-?\d+\.\d{2},[01]', line), \
            f'Invalid report format: {line!r}'
    return lines


def assert_output(actual, expected):
    assert len(actual) == len(expected), \
        f'Expected {len(expected)} lines in report, but found {len(actual)}.'
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got == want, f"Mismatch at line {i + 1}: expected '{want}', got '{got}'."


def run_pipeline(raw_text):
    with open(RAW, 'w') as f:
        f.write(raw_text)
    if os.path.exists(REPORT):
        os.remove(REPORT)
    proc = subprocess.run(
        ['./pipeline.sh'], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert proc.returncode == 0, \
        f'pipeline.sh failed with code {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    assert_output(read_report(), expected_lines(raw_text))


def test_pipeline_and_analyzer_exist():
    assert os.path.isfile(PIPELINE), '/home/user/pipeline.sh is missing.'
    assert os.access(PIPELINE, os.X_OK), '/home/user/pipeline.sh is not executable.'
    assert os.path.isfile(SOURCE), '/home/user/analyzer.c is missing.'


def test_anomalies_report_on_original_input():
    assert os.path.isfile(RAW), f'{RAW} is missing.'
    with open(RAW) as f:
        original = f.read()
    run_pipeline(original)


def test_pipeline_on_unseen_input():
    rng = random.SystemRandom()
    base = rng.randrange(300000, 900000)
    high = rng.randrange(84, 96)
    middle = high - rng.randrange(1, 4)
    later = high - rng.randrange(9, 14)
    low = later - rng.randrange(7, 12)

    rows = [
        (3600 * (base + 5) + 31, 'DUP_A', 'es', 11, low),
        (3600 * base + 220, 'B0_A', 'fr', 12, high),
        (3600 * (base + 1) + 70, 'B1', 'de', 13, middle),
        (3600 * (base + 3) + 500, 'DUP_B', 'it', 14, high),
        (3600 * base + 40, 'DUP_A', 'es', 15, high),
        (3600 * (base + 3) + 90, 'B3', 'fr', 16, later),
        (3600 * (base + 8) + 10, 'B8', 'de', 17, low),
        (3600 * (base + 2) + 120, 'DUP_B', 'it', 18, middle),
    ]
    raw = ''.join(','.join(map(str, row)) + '\n' for row in rows)
    run_pipeline(raw)


def test_compiled_c_analyzer_on_unseen_deduplicated_stream():
    rng = random.SystemRandom()
    base = rng.randrange(900000, 1200000)
    high = rng.randrange(86, 97)
    values = [high, high - 2, high - 14, high - 5, high - 20]
    bucket_offsets = [0, 1, 4, 5, 11]

    rows = []
    for i, (offset, value) in enumerate(zip(bucket_offsets, values)):
        rows.append((3600 * (base + offset) + 10, f'C{i}A', 'es', 20 + i, value))
        if i % 2 == 0:
            rows.append((3600 * (base + offset) + 100, f'C{i}B', 'fr', 30 + i, value))
    analyzer_input = ''.join(','.join(map(str, row)) + '\n' for row in rows)

    binary = '/tmp/submitted_analyzer'
    compile_proc = subprocess.run(
        ['gcc', '-std=c11', '-Wall', '-Wextra', '-O2', SOURCE, '-o', binary],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_proc.returncode == 0, \
        f'analyzer.c did not compile\nstdout:\n{compile_proc.stdout}\nstderr:\n{compile_proc.stderr}'

    run_proc = subprocess.run(
        [binary], input=analyzer_input, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert run_proc.returncode == 0, \
        f'compiled analyzer failed\nstdout:\n{run_proc.stdout}\nstderr:\n{run_proc.stderr}'
    actual = [line.strip() for line in run_proc.stdout.splitlines() if line.strip()]
    assert_output(actual, expected_lines(analyzer_input))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
