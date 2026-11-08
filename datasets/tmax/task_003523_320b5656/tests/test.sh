#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
from collections import Counter
from decimal import Decimal, InvalidOperation

import pytest

VIDEO_CSV = '/home/user/video_ts.csv'
FILTER_SRC = '/home/user/ts_filter.c'
FILTER_BIN = '/home/user/ts_filter'
PIPELINE = '/home/user/pipeline.sh'


def ffprobe_frames():
    proc = subprocess.run([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'frame=pkt_pts_time,pkt_size',
        '-of', 'json', '/app/conveyor.mp4'
    ], capture_output=True, text=True)
    assert proc.returncode == 0, f'ffprobe failed: {proc.stderr}'
    frames = json.loads(proc.stdout).get('frames', [])
    result = []
    for frame in frames:
        assert 'pkt_pts_time' in frame and 'pkt_size' in frame, \
            'ffprobe did not return pkt_pts_time and pkt_size for every frame'
        result.append((Decimal(frame['pkt_pts_time']), int(frame['pkt_size'])))
    return result


def read_video_csv():
    assert os.path.isfile(VIDEO_CSV), f"Video telemetry CSV '{VIDEO_CSV}' is missing."
    with open(VIDEO_CSV, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 150, f'Expected exactly 150 rows in {VIDEO_CSV}, but found {len(lines)}.'
    parsed = []
    raw = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Expected format 'timestamp,size', but got: '{line}'"
        try:
            timestamp = Decimal(parts[0])
            size = int(parts[1])
        except (InvalidOperation, ValueError):
            pytest.fail(f"Invalid data types in row: '{line}'. Expected float,int.")
        assert timestamp.is_finite(), f"Non-finite timestamp in row: '{line}'"
        parsed.append((timestamp, size))
        raw.append((parts[0], parts[1]))
    return parsed, raw


def run_filter(executable, path, expected):
    proc = subprocess.run([executable, path], capture_output=True, text=True, timeout=10)
    assert proc.returncode == 0, f'{executable} exited with {proc.returncode}: {proc.stderr}'
    assert proc.stdout == expected, \
        f'{executable} produced incorrect output for {os.path.basename(path)}'


def test_video_ts_csv_matches_ffprobe():
    actual, _ = read_video_csv()
    expected = ffprobe_frames()
    assert len(expected) == 150, f'Expected the fixture to contain 150 frames, found {len(expected)}.'
    assert actual == expected, 'video_ts.csv does not contain the ffprobe telemetry for /app/conveyor.mp4'


def test_ts_filter_source_and_corpus():
    assert os.path.isfile(FILTER_SRC), f"C source '{FILTER_SRC}' is missing."
    assert os.path.isfile(FILTER_BIN), f"Target executable '{FILTER_BIN}' is missing."
    assert os.access(FILTER_BIN, os.X_OK), f"Target executable '{FILTER_BIN}' is not executable."
    with open(FILTER_BIN, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'ts_filter must be a compiled native executable'

    build_dir = tempfile.mkdtemp(prefix='filter-build-')
    rebuilt = os.path.join(build_dir, 'ts_filter')
    build = subprocess.run(
        ['gcc', '-std=c11', '-O2', FILTER_SRC, '-o', rebuilt, '-lm'],
        capture_output=True, text=True
    )
    assert build.returncode == 0, f'ts_filter.c does not compile: {build.stderr}'

    executables = [FILTER_BIN, rebuilt]

    clean_dir = '/app/corpora/clean'
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.csv')]
    assert clean_files, 'Clean corpus is empty.'
    for fname in clean_files:
        path = os.path.join(clean_dir, fname)
        with open(path, 'r') as f:
            expected = f.read()
        for executable in executables:
            run_filter(executable, path, expected)

    evil_path = '/app/corpora/evil/sensor_02.csv'
    evil_expected = (
        '0.000000,sensB,20.1\n'
        '0.033333,sensB,20.5\n'
        '0.066667,sensB,21.0\n'
    )
    for executable in executables:
        run_filter(executable, evil_path, evil_expected)

    token = secrets.token_hex(8)
    t1 = f'101.{secrets.randbelow(900000) + 100000}'
    t2 = f'202.{secrets.randbelow(900000) + 100000}'
    t3 = f'303.{secrets.randbelow(900000) + 100000}'
    clean_text = (
        f'{t1},alpha_{token},-17.25\n'
        f'{t2},beta_{token},0.0004\n'
        f'{t3},gamma_{token},6.02e3\n'
    )
    evil_text = (
        f'{t1},alpha_{token},-17.25\n'
        f'not-a-float,bad_{token},1.0\n'
        f'{t2},beta_{token},0.0004\n'
        f'{t1},duplicate_{token},999\n'
        f'{t3},bad-value_{token},not-a-float\n'
        f'{t3},gamma_{token},6.02e3\n'
        f'{t2},too,many,fields\n'
        f'{t3},duplicate_{token},7\n'
        'missing,fields\n'
    )
    expected_evil = (
        f'{t1},alpha_{token},-17.25\n'
        f'{t2},beta_{token},0.0004\n'
        f'{t3},gamma_{token},6.02e3\n'
    )

    with tempfile.TemporaryDirectory(prefix='hidden sensor ') as td:
        clean_path = os.path.join(td, 'unseen clean.csv')
        evil_random_path = os.path.join(td, 'unseen malformed.csv')
        with open(clean_path, 'w') as f:
            f.write(clean_text)
        with open(evil_random_path, 'w') as f:
            f.write(evil_text)
        for executable in executables:
            run_filter(executable, clean_path, clean_text)
            run_filter(executable, evil_random_path, expected_evil)


def test_pipeline_script_joins_supplied_sensor_data():
    assert os.path.isfile(PIPELINE), f"Pipeline script '{PIPELINE}' is missing."
    assert os.access(PIPELINE, os.X_OK), f"Pipeline script '{PIPELINE}' is not executable."

    _, video_rows = read_video_csv()
    unique_rows = []
    seen = set()
    for timestamp, size in video_rows:
        if timestamp not in seen:
            seen.add(timestamp)
            unique_rows.append((timestamp, size))
    assert len(unique_rows) >= 8

    chosen = unique_rows[7:15]
    token = secrets.token_hex(8)
    input_lines = []
    expected = []
    for i, (timestamp, size) in enumerate(chosen):
        sensor_id = f'sensor_{token}_{i}'
        value = f'{i + 0.125}'
        input_lines.append(f'{timestamp},{sensor_id},{value}\n')
        expected.append((timestamp, sensor_id, value, size))
        if i % 2 == 0:
            input_lines.append(f'{timestamp},duplicate_{token}_{i},9999\n')

    input_lines.insert(2, f'INVALID,bad_{token},12.0\n')
    input_lines.insert(5, f'{chosen[3][0]},bad_{token},not-a-number\n')
    input_lines.append(f'999999.123456,unmatched_{token},42.0\n')

    with tempfile.TemporaryDirectory(prefix='pipeline-input-') as td:
        sensor_path = os.path.join(td, 'supplied sensor.csv')
        with open(sensor_path, 'w') as f:
            f.writelines(input_lines)
        proc = subprocess.run([PIPELINE, sensor_path], capture_output=True, text=True, timeout=10)

    assert proc.returncode == 0, f'Pipeline script failed with exit code {proc.returncode}: {proc.stderr}'
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    assert len(lines) > 0, 'Pipeline script produced no output.'

    actual = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 4, \
            f"Expected joined format 'timestamp,sensor_id,value,size', but got: '{line}'"
        try:
            float(parts[0])
            float(parts[2])
            int(parts[3])
        except ValueError:
            pytest.fail(f"Invalid data types in joined pipeline output row: '{line}'")
        actual.append(tuple(parts))

    assert Counter(actual) == Counter(expected), \
        'pipeline output was not the exact join of the supplied sanitized sensor rows and video telemetry'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
