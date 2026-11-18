#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import os
import re
import shlex
import shutil
import subprocess
import traceback
from pathlib import Path

import cv2
import numpy as np
import pandas as pd

HOME = Path('/home/user')
FRAMES = HOME / 'frames'
CSV = HOME / 'trajectory.csv'
SCRIPT = HOME / 'etl_pipeline.sh'
CPP = HOME / 'process_radar.cpp'
CRON = HOME / 'cron_schedule.txt'
VIDEO = Path('/app/radar_scan.mp4')
META = Path('/app/sensor_meta.txt')


def natural_key(path):
    return [int(x) if x.isdigit() else x.lower()
            for x in re.split(r'(\d+)', path.name)]


def read_video(path):
    cap = cv2.VideoCapture(str(path))
    assert cap.isOpened(), f'Unable to open video {path}'
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
    cap.release()
    assert frames, f'No frames decoded from {path}'
    return frames


def center_of_mass(image):
    p = image.astype(np.float64)
    lo, hi = float(p.min()), float(p.max())
    assert hi > lo, 'Extracted frame has no intensity variation'
    p = (p - lo) / (hi - lo)
    total = float(p.sum())
    assert total > 0.0, 'Extracted frame has zero normalized intensity'
    yy, xx = np.indices(p.shape)
    return float((xx * p).sum() / total), float((yy * p).sum() / total)


def clean_outputs():
    FRAMES.mkdir(parents=True, exist_ok=True)
    for entry in FRAMES.iterdir():
        if entry.is_dir():
            shutil.rmtree(entry)
        else:
            entry.unlink()
    if CSV.exists():
        CSV.unlink()


def run_pipeline():
    clean_outputs()
    proc = subprocess.run(
        ['runuser', '-u', 'user', '--', 'bash', '-x', str(SCRIPT)],
        cwd=str(HOME), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=90
    )
    assert proc.returncode == 0, 'ETL pipeline failed:\n' + proc.stdout[-5000:]
    return proc.stdout


def assert_cpp_compilation_and_execution(trace):
    build = subprocess.run(
        ['g++', '-std=c++17', str(CPP), '-o', '/tmp/verifier_process_radar'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45
    )
    assert build.returncode == 0, 'process_radar.cpp does not compile as standalone C++17 using standard libraries:\n' + build.stdout

    lines = [line[2:] for line in trace.splitlines() if line.startswith('+ ')]
    compile_index = None
    output_name = None
    for index, line in enumerate(lines):
        try:
            words = shlex.split(line)
        except ValueError:
            continue
        if not words:
            continue
        compiler = os.path.basename(words[0])
        if compiler in ('g++', 'c++') and any(os.path.basename(w) == 'process_radar.cpp' for w in words):
            compile_index = index
            output_name = 'a.out'
            for i, word in enumerate(words):
                if word == '-o' and i + 1 < len(words):
                    output_name = os.path.basename(words[i + 1])
                elif word.startswith('-o') and len(word) > 2:
                    output_name = os.path.basename(word[2:])
            break
    assert compile_index is not None, 'Pipeline did not compile process_radar.cpp with a C++ compiler'

    executed = False
    for line in lines[compile_index + 1:]:
        try:
            words = shlex.split(line)
        except ValueError:
            continue
        if words and os.path.basename(words[0]) == output_name:
            executed = True
            break
    assert executed, f'Pipeline compiled {output_name} but did not execute it'


def validate_run(expected_timestamps, require_original_metric=False):
    # Validate that ffmpeg actually produced one grayscale PGM per source frame.
    source_frames = read_video(VIDEO)
    pgms = sorted(FRAMES.glob('*.pgm'), key=natural_key)
    assert len(pgms) == len(source_frames), (
        f'Expected {len(source_frames)} PGM frames at 10 fps, found {len(pgms)}')

    extracted = []
    for i, (path, reference) in enumerate(zip(pgms, source_frames)):
        with open(path, 'rb') as f:
            magic = f.read(2)
        assert magic in (b'P5', b'P2'), f'{path} is not a PGM image'
        image = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
        assert image is not None and image.ndim == 2, f'{path} is not a grayscale image'
        assert image.shape == reference.shape, f'Wrong dimensions for {path}'
        rmse = float(np.sqrt(np.mean((image.astype(float) - reference.astype(float)) ** 2)))
        assert rmse <= 4.0, f'{path} does not match source video frame {i}: RMSE={rmse:.3f}'
        extracted.append(image)

    # Retain the original CSV existence/readability/column/nonempty assertions.
    assert CSV.is_file(), f'Missing output CSV at {CSV}'
    try:
        df = pd.read_csv(CSV)
    except Exception as exc:
        raise AssertionError(f'Failed to read {CSV} as CSV: {exc}')
    assert 'distance_to_center' in df.columns, f"Missing column 'distance_to_center' in {CSV}"
    distances = pd.to_numeric(df['distance_to_center'], errors='coerce').dropna().to_numpy()
    assert len(distances) > 0, 'No valid data rows found in trajectory.csv'

    assert list(df.columns) == ['timestamp_ms', 'x', 'y', 'distance_to_center'], 'CSV header is not exact'
    assert len(df) == len(expected_timestamps), (
        f'Expected {len(expected_timestamps)} valid metadata rows, found {len(df)}')
    numeric = df.apply(pd.to_numeric, errors='coerce')
    assert np.isfinite(numeric.to_numpy(dtype=float)).all(), 'CSV contains missing or non-numeric values'

    actual_ts = numeric['timestamp_ms'].to_numpy(dtype=float)
    assert np.allclose(actual_ts, expected_timestamps, atol=0, rtol=0), 'CSV timestamps do not match valid ACTIVE metadata entries'

    for row, timestamp in zip(numeric.itertuples(index=False), expected_timestamps):
        frame_index = int(timestamp // 100)
        assert 0 <= frame_index < len(extracted), f'Timestamp {timestamp} selects a nonexistent frame'
        ex, ey = center_of_mass(extracted[frame_index])
        expected_distance = float(np.hypot(ex - extracted[frame_index].shape[1] / 2.0,
                                           ey - extracted[frame_index].shape[0] / 2.0))
        assert abs(float(row.x) - ex) <= 0.75, f'Incorrect x at timestamp {timestamp}'
        assert abs(float(row.y) - ey) <= 0.75, f'Incorrect y at timestamp {timestamp}'
        assert abs(float(row.distance_to_center) - expected_distance) <= 0.75, f'Incorrect distance at timestamp {timestamp}'
        reported_distance = float(np.hypot(float(row.x) - 50.0, float(row.y) - 50.0))
        assert abs(float(row.distance_to_center) - reported_distance) <= 0.15, f'Distance is inconsistent with x/y at timestamp {timestamp}'

    if require_original_metric:
        gt_distances = np.full_like(distances, 30.0)
        mse = np.mean((distances - gt_distances) ** 2)
        assert mse <= 2.5, f'MSE of distance_to_center is {mse:.4f}, which exceeds the threshold of 2.5'


def make_challenge():
    writer = cv2.VideoWriter(str(VIDEO), cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100), isColor=False)
    assert writer.isOpened(), 'Could not create verifier challenge video'
    for i in range(36):
        frame = np.zeros((100, 100), dtype=np.uint8)
        x = 12 + (17 * i) % 76
        y = 10 + (29 * i) % 78
        frame[max(0, y-2):min(100, y+3), max(0, x-2):min(100, x+3)] = 255
        writer.write(frame)
    writer.release()

    valid = [0, 300, 600, 900, 1200, 1500, 1800, 2100, 2400, 2700, 3000, 3300]
    with open(META, 'w') as f:
        for t in valid:
            f.write(f'[VALID] T:{t} S:ACTIVE\n')
            f.write(f'[INVALID] T:{t + 50} S:OFF\n')
            f.write(f'[VALID] T:{t + 25} S:OFF\n')
            f.write(f'noise T:{t} S:ACTIVE\n')
    os.chmod(VIDEO, 0o644)
    os.chmod(META, 0o644)
    return valid


def main():
    # Retain all original artifact and cron assertions.
    assert SCRIPT.is_file(), f'Missing bash script at {SCRIPT}'
    assert CPP.is_file(), f'Missing C++ source file at {CPP}'
    assert CRON.is_file(), f'Missing cron schedule file at {CRON}'
    content = CRON.read_text().strip()
    assert '*/5 * * * *' in content, f"Cron schedule does not contain the correct interval '*/5 * * * *'. Content: {content}"
    assert '/home/user/etl_pipeline.sh' in content, f'Cron schedule does not contain the script path. Content: {content}'

    backup_video = Path('/tmp/original_radar_scan.mp4')
    backup_meta = Path('/tmp/original_sensor_meta.txt')
    shutil.copy2(VIDEO, backup_video)
    shutil.copy2(META, backup_meta)
    try:
        original_trace = run_pipeline()
        assert_cpp_compilation_and_execution(original_trace)
        validate_run(list(range(0, 10000, 100)), require_original_metric=True)

        challenge_timestamps = make_challenge()
        run_pipeline()
        validate_run(challenge_timestamps, require_original_metric=False)
    finally:
        shutil.copy2(backup_video, VIDEO)
        shutil.copy2(backup_meta, META)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        traceback.print_exc()
        raise
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
