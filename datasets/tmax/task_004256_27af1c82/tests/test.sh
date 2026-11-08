#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import random
import subprocess
import uuid
from collections import Counter
from functools import lru_cache
from pathlib import Path

HOME = Path('/home/user')
FILTER = HOME / 'telemetry_filter'
FILTER_SOURCE = HOME / 'filter.go'
PIPELINE = HOME / 'pipeline.sh'
RAW = Path('/app/raw_telemetry.csv')
VIDEO = Path('/app/drone_flight.mp4')
HEADER = ['timestamp_sec', 'latitude', 'longitude', 'altitude', 'status']
MERGED_HEADER = HEADER + ['brightness']
GENERATED = [
    FILTER,
    HOME / 'clean_telemetry.csv',
    HOME / 'video_features.csv',
    HOME / 'merged_output.csv',
]


def read_csv(path):
    with open(path, newline='') as f:
        return list(csv.reader(f))


def valid_row(row):
    if len(row) != 5:
        return False
    try:
        if not row[0] or any(ch not in '0123456789' for ch in row[0]):
            return False
        ts = int(row[0])
        lat = float(row[1])
        lon = float(row[2])
        alt = float(row[3])
    except ValueError:
        return False
    return (
        ts >= 0 and
        math.isfinite(lat) and -90.0 <= lat <= 90.0 and
        math.isfinite(lon) and -180.0 <= lon <= 180.0 and
        math.isfinite(alt) and alt >= 0.0 and
        row[4] in ('OK', 'WARN', 'ERR')
    )


def expected_clean(rows):
    assert rows and rows[0] == HEADER
    return [HEADER] + [row for row in rows[1:] if valid_row(row)]


def run_pipeline():
    process = subprocess.run(
        ['bash', str(PIPELINE)],
        cwd=str(HOME),
        text=True,
        capture_output=True,
        timeout=180,
        check=False,
    )
    assert process.returncode == 0, (
        f'pipeline.sh exited with {process.returncode}\n'
        f'stdout:\n{process.stdout}\nstderr:\n{process.stderr}'
    )


def run_filter(input_content, executable=FILTER):
    process = subprocess.run(
        [str(executable)],
        input=input_content,
        text=True,
        capture_output=True,
        timeout=20,
        check=False,
    )
    assert process.returncode == 0, process.stderr
    return process.stdout


@lru_cache(maxsize=1)
def expected_video_brightness():
    probe = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0',
         '-show_entries', 'stream=width,height', '-of', 'csv=p=0:s=x', str(VIDEO)],
        capture_output=True, text=True, check=True,
    )
    width, height = map(int, probe.stdout.strip().split('x'))

    def decode(pixel_format, channels):
        process = subprocess.run(
            ['ffmpeg', '-v', 'error', '-i', str(VIDEO), '-vf', 'fps=1',
             '-pix_fmt', pixel_format, '-f', 'rawvideo', 'pipe:1'],
            capture_output=True, check=True,
        )
        frame_size = width * height * channels
        assert frame_size > 0 and len(process.stdout) % frame_size == 0
        return [
            sum(process.stdout[i:i + frame_size]) / frame_size
            for i in range(0, len(process.stdout), frame_size)
        ]

    gray = decode('gray', 1)
    rgb = decode('rgb24', 3)
    assert gray and len(gray) == len(rgb)
    return gray, rgb


def verify_pipeline_outputs(raw_rows):
    clean_path = HOME / 'clean_telemetry.csv'
    feature_path = HOME / 'video_features.csv'
    merged_path = HOME / 'merged_output.csv'

    assert clean_path.is_file(), '/home/user/clean_telemetry.csv is missing.'
    assert feature_path.is_file(), '/home/user/video_features.csv is missing.'
    assert merged_path.is_file(), '/home/user/merged_output.csv is missing.'

    clean_rows = read_csv(clean_path)
    expected = expected_clean(raw_rows)
    assert clean_rows == expected, f'Incorrect cleaned telemetry: {clean_rows}'

    feature_rows = read_csv(feature_path)
    assert feature_rows and feature_rows[0] == ['timestamp_sec', 'brightness']
    gray, rgb = expected_video_brightness()
    assert len(feature_rows) == len(gray) + 1
    brightness_by_ts = {}
    for index, row in enumerate(feature_rows[1:]):
        assert len(row) == 2
        assert row[0] == str(index), f'Unexpected video timestamp row: {row}'
        try:
            value = int(row[1])
        except ValueError:
            raise AssertionError(f'Brightness is not an integer: {row[1]!r}')
        assert 0 <= value <= 255
        assert min(abs(value - gray[index]), abs(value - rgb[index])) <= 2.0, (
            f'Incorrect brightness at timestamp {index}: {value}'
        )
        brightness_by_ts[row[0]] = row[1]

    merged_rows = read_csv(merged_path)
    assert len(merged_rows) > 0, 'merged_output.csv is empty.'
    assert merged_rows[0] == MERGED_HEADER, (
        f'merged_output.csv header is incorrect. Expected {MERGED_HEADER}, got {merged_rows[0]}'
    )
    for row in merged_rows[1:]:
        assert len(row) == 6, 'merged_output.csv data rows do not have 6 columns.'

    expected_merged = [row + [brightness_by_ts[row[0]]] for row in expected[1:]
                       if row[0] in brightness_by_ts]
    assert Counter(map(tuple, merged_rows[1:])) == Counter(map(tuple, expected_merged)), (
        f'Incorrect inner join. Expected {expected_merged}, got {merged_rows[1:]}'
    )


def test_required_sources_and_original_pipeline():
    assert FILTER_SOURCE.is_file(), '/home/user/filter.go is missing.'
    assert PIPELINE.is_file(), '/home/user/pipeline.sh is missing.'
    assert VIDEO.is_file(), '/app/drone_flight.mp4 is missing.'
    assert RAW.is_file(), '/app/raw_telemetry.csv is missing.'

    raw_rows = read_csv(RAW)
    for path in GENERATED:
        if path.exists():
            path.unlink()
    run_pipeline()
    verify_pipeline_outputs(raw_rows)


def test_telemetry_filter_executable():
    assert FILTER.is_file(), f'Executable not found at {FILTER}'
    assert os.access(FILTER, os.X_OK), f'File at {FILTER} is not executable'


def test_clean_corpus_preserved():
    clean_dir = Path('/app/corpus/clean')
    assert clean_dir.exists(), 'Clean corpus directory missing.'
    modified_files = []
    for csv_file in clean_dir.glob('*.csv'):
        original_content = csv_file.read_text()
        output = run_filter(original_content)
        orig_rows = [row for row in csv.reader(original_content.strip().splitlines()) if row]
        out_rows = [row for row in csv.reader(output.strip().splitlines()) if row]
        if orig_rows != out_rows:
            modified_files.append(csv_file.name)
    assert not modified_files, (
        f'{len(modified_files)} clean corpus files were incorrectly modified: '
        + ', '.join(modified_files)
    )


def test_evil_corpus_rejected():
    evil_dir = Path('/app/corpus/evil')
    assert evil_dir.exists(), 'Evil corpus directory missing.'
    bypassed_files = []
    for csv_file in evil_dir.glob('*.csv'):
        original_content = csv_file.read_text()
        original_rows = list(csv.reader(original_content.strip().splitlines()))
        output_rows = list(csv.reader(run_filter(original_content).strip().splitlines()))
        if output_rows != expected_clean(original_rows):
            bypassed_files.append(csv_file.name)
    assert not bypassed_files, (
        f'{len(bypassed_files)} evil corpus files bypassed validation: '
        + ', '.join(bypassed_files)
    )


def test_filter_on_unshipped_randomized_input_and_source_build():
    rng = random.SystemRandom()
    token = uuid.uuid4().hex
    valid = []
    for i in range(18):
        ts = str(rng.randrange(0, 1000000))
        lat = f'{rng.uniform(-89.5, 89.5):.8f}'
        lon = f'{rng.uniform(-179.5, 179.5):.8f}'
        alt = f'{rng.uniform(0, 5000):.5f}'
        valid.append([ts, lat, lon, alt, rng.choice(['OK', 'WARN', 'ERR'])])

    invalid = [
        ['-1', '0', '0', '0', 'OK'],
        ['not_' + token, '0', '0', '0', 'OK'],
        ['1', '90.00001', '0', '0', 'OK'],
        ['2', '-90.00001', '0', '0', 'OK'],
        ['3', '0', '180.00001', '0', 'OK'],
        ['4', '0', '-180.00001', '0', 'OK'],
        ['5', '0', '0', '-0.01', 'OK'],
        ['6', '0', '0', '0', token],
        ['7', 'NaN', '0', '0', 'OK'],
        ['8', '0', 'NaN', '0', 'OK'],
        ['9', '0', '0', 'NaN', 'OK'],
        ['10', '0', '0', '0'],
        ['11', '0', '0', '0', 'OK', 'extra'],
    ]
    rows = valid + invalid
    rng.shuffle(rows)
    expected = [HEADER] + [row for row in rows if valid_row(row)]
    stream = io.StringIO()
    csv.writer(stream, lineterminator='\n').writerows([HEADER] + rows)

    built = Path('/tmp/filter_from_source')
    build = subprocess.run(
        ['go', 'build', '-o', str(built), str(FILTER_SOURCE)],
        cwd=str(HOME), capture_output=True, text=True, timeout=120, check=False,
    )
    assert build.returncode == 0, f'filter.go does not build:\n{build.stderr}'

    for executable in (FILTER, built):
        output = list(csv.reader(run_filter(stream.getvalue(), executable).splitlines()))
        assert output == expected, f'{executable} failed randomized validation'


def test_pipeline_consumes_dynamic_raw_input_and_joins():
    original = RAW.read_bytes()
    rng = random.SystemRandom()
    rows = [HEADER]
    for ts in (0, 2, 5, 9):
        rows.append([
            str(ts),
            f'{rng.uniform(-80, 80):.7f}',
            f'{rng.uniform(-170, 170):.7f}',
            f'{rng.uniform(1, 900):.4f}',
            rng.choice(['OK', 'WARN', 'ERR']),
        ])
    rows.extend([
        ['1', '99.5', '0', '10', 'OK'],
        ['3', '0', '0', '-7', 'WARN'],
        ['7', '0', '0', '10', uuid.uuid4().hex],
        ['8', '0', '0'],
    ])
    stream = io.StringIO()
    csv.writer(stream, lineterminator='\n').writerows(rows)
    try:
        RAW.write_text(stream.getvalue())
        for path in GENERATED:
            if path.exists():
                path.unlink()
        run_pipeline()
        assert FILTER.is_file() and os.access(FILTER, os.X_OK)
        verify_pipeline_outputs(rows)
    finally:
        RAW.write_bytes(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
