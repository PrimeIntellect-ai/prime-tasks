#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import shutil
import subprocess
import tempfile
from pathlib import Path

import cv2
import pytest

PIPELINE = Path('/home/user/pipeline')
RAW = PIPELINE / 'raw_trajectory.csv'
CLEAN = PIPELINE / 'clean_trajectory.csv'
DETECTOR = Path('/home/user/bin/detector')


def run(cmd, **kwargs):
    return subprocess.run(cmd, timeout=120, capture_output=True, text=True, **kwargs)


def read_csv(path):
    with open(path, newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        return header, list(reader)


def as_float(value, context):
    try:
        result = float(value)
    except Exception as exc:
        raise AssertionError(f'{context} is not numeric: {value!r}') from exc
    assert math.isfinite(result), f'{context} is not finite: {value!r}'
    return result


def expected_video_rows():
    timestamps = {}
    with open('/app/dataset/sensor_time.csv', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['frame_id', 'timestamp_ms']
        for row in reader:
            timestamps[int(row['frame_id'])] = int(row['timestamp_ms'])

    cap = cv2.VideoCapture('/app/dataset/pendulum.mp4')
    assert cap.isOpened(), 'Verifier could not open the supplied video'
    result = []
    frame_id = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if len(frame.shape) == 3 else frame
        ys, xs = (gray > 200).nonzero()
        assert len(xs) > 0, f'No bright pixels in supplied frame {frame_id}'
        result.append((frame_id, timestamps[frame_id], float(xs.mean())))
        frame_id += 1
    cap.release()
    assert len(result) == len(timestamps) == 60
    return result


def expected_clean(xs):
    smoothed = []
    normalized = []
    running_min = None
    running_max = None
    for i in range(len(xs)):
        avg = sum(xs[max(0, i - 4):i + 1]) / len(xs[max(0, i - 4):i + 1])
        smoothed.append(avg)
        running_min = avg if running_min is None else min(running_min, avg)
        running_max = avg if running_max is None else max(running_max, avg)
        if running_max == running_min:
            normalized.append(0.0)
        else:
            normalized.append((avg - running_min) / (running_max - running_min))
    return normalized


def test_raw_trajectory_exists_and_valid():
    assert RAW.is_file(), f'File missing: {RAW}'
    header, rows = read_csv(RAW)
    assert header is not None, 'raw_trajectory.csv is empty'
    assert len(header) >= 3, 'raw_trajectory.csv should have at least 3 columns (frame_id, timestamp_ms, x_centroid)'
    assert len(rows) > 0, 'raw_trajectory.csv has no data rows'


def test_clean_trajectory_exists_and_valid():
    assert CLEAN.is_file(), f'File missing: {CLEAN}'
    header, rows = read_csv(CLEAN)
    assert header is not None, 'clean_trajectory.csv is empty'
    assert 'x_smoothed_normalized' in header, "clean_trajectory.csv missing 'x_smoothed_normalized' column"
    assert len(rows) > 0, 'clean_trajectory.csv has no data rows'


def test_detector_binary_exists():
    assert DETECTOR.is_file(), f'Detector binary missing: {DETECTOR}'
    assert os.access(DETECTOR, os.X_OK), f'Detector binary is not executable: {DETECTOR}'


def test_extract_and_clean_programs_execute_and_are_mathematical():
    extract_src = PIPELINE / 'extract.go'
    clean_src = PIPELINE / 'clean.go'
    assert extract_src.is_file(), f'Missing required Go source: {extract_src}'
    assert clean_src.is_file(), f'Missing required Go source: {clean_src}'
    extract_text = extract_src.read_text(errors='replace').lower()
    assert 'ffmpeg' in extract_text, 'extract.go does not invoke or reference ffmpeg'

    RAW.unlink(missing_ok=True)
    CLEAN.unlink(missing_ok=True)
    result = run(['/usr/bin/go', 'run', str(extract_src)], cwd=str(PIPELINE))
    assert result.returncode == 0, f'extract.go failed:\n{result.stdout}\n{result.stderr}'
    assert RAW.is_file(), 'extract.go did not create raw_trajectory.csv'

    expected = expected_video_rows()
    header, rows = read_csv(RAW)
    assert header == ['frame_id', 'timestamp_ms', 'x_centroid'], f'Unexpected raw header: {header}'
    assert len(rows) == len(expected), f'Expected {len(expected)} raw rows, got {len(rows)}'
    for i, (row, exp) in enumerate(zip(rows, expected)):
        assert len(row) == 3, f'Raw row {i} has the wrong number of columns'
        assert int(row[0]) == exp[0], f'Wrong frame_id at row {i}'
        assert int(float(row[1])) == exp[1], f'Wrong timestamp at row {i}'
        actual_x = as_float(row[2], f'raw centroid row {i}')
        assert abs(actual_x - exp[2]) <= 0.35, f'Wrong centroid at frame {i}: got {actual_x}, expected {exp[2]}'

    result = run(['/usr/bin/go', 'run', str(clean_src)], cwd=str(PIPELINE))
    assert result.returncode == 0, f'clean.go failed:\n{result.stdout}\n{result.stderr}'
    header, clean_rows = read_csv(CLEAN)
    assert header == ['frame_id', 'timestamp_ms', 'x_centroid', 'x_smoothed_normalized'], f'Unexpected clean header: {header}'
    assert len(clean_rows) == len(rows)
    expected_norm = expected_clean([float(r[2]) for r in rows])
    for i, (raw_row, clean_row, want) in enumerate(zip(rows, clean_rows, expected_norm)):
        assert clean_row[:3] == raw_row, f'clean.go altered joined input fields at row {i}'
        got = as_float(clean_row[3], f'normalized value row {i}')
        assert abs(got - want) <= 1e-6, f'Incorrect causal cleaning at row {i}: got {got}, expected {want}'

    real_raw = RAW.read_bytes()
    try:
        prefix = [7.0, 20.0, -3.0, 40.0, 11.0, 8.0, 25.0, -9.0]
        variants = [prefix + [10000.0, -8000.0, 3.0], prefix + [-10000.0, 9000.0, 77.0]]
        prefix_outputs = []
        for values in variants:
            with open(RAW, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['frame_id', 'timestamp_ms', 'x_centroid'])
                for i, value in enumerate(values):
                    writer.writerow([i, i * 37, value])
            CLEAN.unlink(missing_ok=True)
            result = run(['/usr/bin/go', 'run', str(clean_src)], cwd=str(PIPELINE))
            assert result.returncode == 0, f'clean.go failed on a synthetic trajectory:\n{result.stdout}\n{result.stderr}'
            h, out = read_csv(CLEAN)
            assert h == ['frame_id', 'timestamp_ms', 'x_centroid', 'x_smoothed_normalized']
            assert len(out) == len(values)
            wants = expected_clean(values)
            got_values = []
            for i, (row, want) in enumerate(zip(out, wants)):
                assert int(row[0]) == i and int(row[1]) == i * 37
                assert abs(float(row[2]) - values[i]) <= 1e-12
                got = as_float(row[3], f'synthetic normalized value row {i}')
                assert abs(got - want) <= 1e-6, f'Incorrect synthetic causal result at row {i}: got {got}, expected {want}'
                got_values.append(got)
            prefix_outputs.append(got_values[:len(prefix)])
        assert prefix_outputs[0] == pytest.approx(prefix_outputs[1], abs=1e-9), 'Changing future rows changed earlier clean outputs'
    finally:
        RAW.write_bytes(real_raw)
        result = run(['/usr/bin/go', 'run', str(clean_src)], cwd=str(PIPELINE))
        assert result.returncode == 0, 'Could not restore clean_trajectory.csv after causal tests'


def assert_detector_on_corpus(binary):
    clean_dir = Path('/app/corpora/clean')
    evil_dir = Path('/app/corpora/evil')
    clean_files = sorted(clean_dir.glob('*.csv'))
    evil_files = sorted(evil_dir.glob('*.csv'))
    assert clean_files, f'Clean corpus directory {clean_dir} is empty or missing CSV files.'
    assert evil_files, f'Evil corpus directory {evil_dir} is empty or missing CSV files.'
    bad_clean = [p.name for p in clean_files if run([str(binary), str(p)]).returncode != 0]
    bad_evil = [p.name for p in evil_files if run([str(binary), str(p)]).returncode == 0]
    assert not bad_clean, f'{len(bad_clean)} clean files rejected: {bad_clean}'
    assert not bad_evil, f'{len(bad_evil)} evil files accepted: {bad_evil}'


def test_detector_adversarial_corpus():
    assert_detector_on_corpus(DETECTOR)


def test_detector_source_and_path_independent_inputs():
    detector_src = PIPELINE / 'detector.go'
    assert detector_src.is_file(), f'Missing required Go source: {detector_src}'
    with tempfile.TemporaryDirectory(prefix='trajectory-audit-') as td:
        td = Path(td)
        rebuilt = td / 'candidate'
        result = run(['/usr/bin/go', 'build', '-o', str(rebuilt), str(detector_src)], cwd=str(PIPELINE))
        assert result.returncode == 0, f'detector.go does not compile:\n{result.stdout}\n{result.stderr}'

        rng = random.SystemRandom()
        cases = []
        sources = (sorted(Path('/app/corpora/clean').glob('*.csv'))[:20] +
                   sorted(Path('/app/corpora/evil').glob('*.csv'))[:20])
        rng.shuffle(sources)
        for source in sources:
            expected_rc = 0 if source.parent.name == 'clean' else 1
            scale = rng.uniform(0.75, 1.25)
            offset = rng.uniform(-2.0, 2.0)
            destination = td / (''.join(rng.choice('abcdefghijklmnopqrstuvwxyz0123456789') for _ in range(20)) + '.csv')
            with open(source, newline='') as src, open(destination, 'w', newline='') as dst:
                reader = csv.DictReader(src)
                writer = csv.writer(dst)
                writer.writerow(['t', 'val'])
                for row in reader:
                    writer.writerow([row['t'], float(row['val']) * scale + offset])
            cases.append((destination, expected_rc))

        rng.shuffle(cases)
        failures = []
        for path, expected_rc in cases:
            result = run([str(rebuilt), str(path)], cwd=str(td))
            if (result.returncode == 0) != (expected_rc == 0):
                failures.append(path.name)
        assert not failures, f'Detector failed {len(failures)} path-neutral, value-transformed corpus cases: {failures}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
