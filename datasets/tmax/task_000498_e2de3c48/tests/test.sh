#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'ORACLE_EOF' > /tmp/verifier_baseline_inference.py
import sys
import numpy as np
import hashlib

def process(image_path):
    img_hash = int(hashlib.md5(open(image_path, 'rb').read()).hexdigest(), 16)
    np.random.seed(img_hash % (2**32))
    A = np.random.randn(800, 800)
    B = np.random.randn(800, 800)
    C = A @ B
    return int(np.sum(C) % 15)

if __name__ == '__main__':
    print(process(sys.argv[1]))
ORACLE_EOF
chmod 500 /tmp/verifier_baseline_inference.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import secrets
import shutil
import subprocess
import time

import numpy as np
import pandas as pd
import pytest

EXPECTED_COLUMNS = ['timestamp', 'object_count', 'speed', 'lat', 'lon']
ORACLE = '/tmp/verifier_baseline_inference.py'


def extract_frames(video, pattern):
    for path in glob.glob(pattern.replace('%04d', '*')):
        os.remove(path)
    subprocess.run(
        ['ffmpeg', '-y', '-i', video, '-vf', 'fps=1', pattern],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    return sorted(glob.glob(pattern.replace('%04d', '*')))


def oracle_count(frame):
    result = subprocess.run(
        ['python3', ORACLE, frame], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    return int(result.stdout.strip())


def assert_csv_matches(csv_path, expected_counts, expected_timestamps):
    assert os.path.isfile(csv_path), f'Output file {csv_path} does not exist.'
    df = pd.read_csv(csv_path)
    assert list(df.columns) == EXPECTED_COLUMNS, (
        f'Columns mismatch. Expected {EXPECTED_COLUMNS}, got {list(df.columns)}'
    )
    assert len(df) > 0, f'{csv_path} dataframe is empty.'
    assert len(df) == len(expected_timestamps), (
        f'Expected {len(expected_timestamps)} rows, got {len(df)}'
    )

    timestamps = pd.to_numeric(df['timestamp'], errors='raise').to_numpy()
    assert np.array_equal(timestamps, np.asarray(expected_timestamps)), (
        f'Incorrect or unsorted timestamps: {timestamps.tolist()}'
    )

    counts = pd.to_numeric(df['object_count'], errors='raise').to_numpy()
    assert np.all(np.isfinite(counts)) and np.all(counts == np.floor(counts)), (
        'object_count values must be finite integers'
    )
    assert counts.astype(int).tolist() == expected_counts, (
        f'object_count mismatch. Expected {expected_counts}, got {counts.astype(int).tolist()}'
    )

    telemetry = pd.read_csv('/app/telemetry.csv').set_index('timestamp')
    for column in ['speed', 'lat', 'lon']:
        actual = pd.to_numeric(df[column], errors='raise').to_numpy(dtype=float)
        expected = telemetry.loc[expected_timestamps, column].to_numpy(dtype=float)
        assert np.allclose(actual, expected, rtol=0, atol=1e-9), (
            f'Incorrect telemetry values in column {column}'
        )


def test_merged_results_valid():
    csv_path = '/home/user/merged_results.csv'
    assert os.path.isfile(csv_path), f'Output file {csv_path} does not exist.'

    # Retain the original shape assertions.
    initial = pd.read_csv(csv_path)
    assert list(initial.columns) == EXPECTED_COLUMNS, (
        f'Columns mismatch. Expected {EXPECTED_COLUMNS}, got {list(initial.columns)}'
    )
    assert len(initial) > 0, 'The merged_results.csv dataframe is empty.'

    frames = extract_frames('/app/experiment.mp4', '/tmp/merged_frames_%04d.png')
    assert len(frames) == 30, f'Expected 30 one-fps frames, got {len(frames)}'

    # The supplied video has repeated frames, so cache identical images while still
    # deriving every expected result from the required inference implementation.
    cache = {}
    expected_counts = []
    for frame in frames:
        digest = hashlib.sha256(open(frame, 'rb').read()).digest()
        if digest not in cache:
            cache[digest] = oracle_count(frame)
        expected_counts.append(cache[digest])

    assert_csv_matches(csv_path, expected_counts, list(range(len(frames))))


def test_optimized_pipeline_speedup():
    agent_script = '/home/user/optimized_pipeline.py'
    assert os.path.isfile(agent_script), f'Agent script {agent_script} does not exist.'
    assert os.path.isfile(agent_script) and not os.path.isdir(agent_script), (
        f'{agent_script} must be a Python file'
    )

    test_video = '/tmp/test_video.mp4'
    if os.path.exists(test_video):
        os.remove(test_video)

    # Randomize the video so a fixed fabricated list of answers cannot pass.
    noise_seed = secrets.randbelow(2_000_000_000) + 1
    subprocess.run([
        'ffmpeg', '-y', '-f', 'lavfi',
        '-i', 'testsrc=duration=10:size=640x480:rate=30',
        '-vf', f'noise=alls=25:allf=t+u:all_seed={noise_seed}',
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        test_video
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    test_out_csv = '/tmp/test_out.csv'
    if os.path.exists(test_out_csv):
        os.remove(test_out_csv)

    t0 = time.time()
    try:
        subprocess.run(['python3', agent_script, test_video, test_out_csv], check=True)
    except subprocess.CalledProcessError as exc:
        pytest.fail(f'Agent script failed to run on test video: {exc}')
    agent_time = time.time() - t0

    assert os.path.isfile(test_out_csv), (
        'Agent script did not produce the output CSV on the test video.'
    )

    # Benchmark the same sequential extraction and exact inference logic as the
    # original verifier, while retaining each derived answer for validation.
    for path in glob.glob('/tmp/test_frames_*.png'):
        os.remove(path)
    t_seq_0 = time.time()
    subprocess.run([
        'ffmpeg', '-y', '-i', test_video, '-vf', 'fps=1',
        '/tmp/test_frames_%04d.png'
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    frames = sorted(glob.glob('/tmp/test_frames_*.png'))
    assert len(frames) == 10, f'Expected 10 one-fps frames, got {len(frames)}'
    expected_counts = [oracle_count(frame) for frame in frames]
    seq_time = time.time() - t_seq_0

    assert_csv_matches(test_out_csv, expected_counts, list(range(10)))

    speedup = seq_time / agent_time
    assert speedup >= 2.0, (
        f'Pipeline speedup is {speedup:.2f}x, which is below the required 2.0x '
        f'threshold. (Agent time: {agent_time:.2f}s, Sequential baseline time: {seq_time:.2f}s)'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
