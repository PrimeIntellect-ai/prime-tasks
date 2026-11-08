#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import shutil
import subprocess
from pathlib import Path

import cv2
import numpy as np
import pytest

VIDEO = Path('/app/manufacturing_feed.mp4')
MASTER = Path('/home/user/run_pipeline.sh')
OUTPUT = Path('/home/user/anomaly_timestamps.json')
BACKUP = Path('/tmp/manufacturing_feed.original.mp4')


def read_output():
    assert OUTPUT.exists(), f'Output file is missing: {OUTPUT}'
    assert OUTPUT.is_file(), f'Output path is not a file: {OUTPUT}'
    text = OUTPUT.read_text()
    try:
        values = json.loads(text)
    except Exception as e:
        pytest.fail(f'Failed to parse JSON from {OUTPUT}: {e}')
    assert isinstance(values, list), f'Expected a JSON array, got {type(values).__name__}'
    for val in values:
        assert isinstance(val, (int, float)) and not isinstance(val, bool), f'Expected numbers in JSON array, got {type(val).__name__}: {val}'
        assert math.isfinite(val), f'Expected finite timestamps, got {val}'
    # Require JSON numbers formatted to exactly one decimal place.
    assert re.fullmatch(r'\s*\[\s*(?:-?\d+\.\d(?:\s*,\s*-?\d+\.\d)*)?\s*\]\s*', text), 'Timestamps must be JSON numbers formatted to exactly one decimal place'
    return values


def run_pipeline():
    assert MASTER.exists(), f'Missing master script: {MASTER}'
    assert MASTER.is_file(), f'Master script is not a file: {MASTER}'
    assert os.access(MASTER, os.X_OK), f'Master script is not executable: {MASTER}'
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    proc = subprocess.run(
        ['runuser', '-u', 'user', '--', 'bash', '-x', str(MASTER)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert proc.returncode == 0, f'Pipeline failed with exit code {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    return proc.stdout + '\n' + proc.stderr


def language_for(path):
    suffix = path.suffix.lower()
    if suffix == '.py': return 'python'
    if suffix in ('.js', '.mjs', '.cjs'): return 'node'
    if suffix in ('.cpp', '.cc', '.cxx', '.c++'): return 'cpp'
    if suffix == '.pl': return 'perl'
    if suffix == '.rb': return 'ruby'
    if suffix == '.awk': return 'awk'
    if suffix in ('.sh', '.bash'): return 'shell'
    try:
        first = path.open(errors='ignore').readline().lower()
    except Exception:
        return None
    for token, lang in [('python', 'python'), ('node', 'node'), ('perl', 'perl'), ('ruby', 'ruby'), ('awk', 'awk'), ('bash', 'shell'), ('/sh', 'shell')]:
        if token in first:
            return lang
    return None


def assert_multilanguage(trace):
    master_text = MASTER.read_text(errors='ignore')
    used = []
    for path in Path('/home/user').rglob('*'):
        if not path.is_file() or path in (MASTER, OUTPUT):
            continue
        lang = language_for(path)
        if not lang:
            continue
        # The separate source must be invoked/referenced by the master and must
        # appear in the execution trace from the successful run.
        if (str(path) in master_text or path.name in master_text) and (str(path) in trace or path.name in trace):
            used.append((path, lang))
    langs = {lang for _, lang in used}
    assert len(used) >= 2 and len(langs) >= 2, f'Expected two separate, executed processing scripts in different languages; found {used}'


def make_challenge(path):
    # Secret positions prevent a pipeline from passing by printing fixed answers.
    a = 18 + secrets.randbelow(8)
    b = a + 6 + secrets.randbelow(4)
    c = b + 18 + secrets.randbelow(7)
    level = 160 + secrets.randbelow(70)
    sample_count = c + 20

    # Ten-FPS source: every logical 5-FPS frame is repeated twice. Closely
    # spaced impulses make a 10-frame rolling window differ from a pipeline
    # that incorrectly processes all 10-FPS source frames.
    logical = [0] * sample_count
    for index in (a, b, c):
        logical[index] = level
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*'mp4v'), 10, (64, 64))
    assert writer.isOpened(), 'Could not create challenge video'
    for value in logical:
        frame = np.full((64, 64, 3), value, dtype=np.uint8)
        writer.write(frame)
        writer.write(frame)
    writer.release()


def reference_result(video):
    frame_dir = Path('/tmp/reference_frames')
    shutil.rmtree(frame_dir, ignore_errors=True)
    frame_dir.mkdir()
    subprocess.run([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(video),
        '-vf', 'fps=5', str(frame_dir / '%06d.png')
    ], check=True, timeout=120)
    files = sorted(frame_dir.glob('*.png'))
    assert len(files) > 10
    frames = [cv2.imread(str(p), cv2.IMREAD_COLOR).astype(np.float64) for p in files]
    mse = [float(np.mean((frames[i] - frames[i - 1]) ** 2)) for i in range(1, len(frames))]
    anomalies = []
    for i in range(10, len(mse)):
        prior = np.asarray(mse[i - 10:i], dtype=np.float64)
        if mse[i] > float(prior.mean()) + 3.0 * float(prior.std(ddof=0)):
            # mse[i] compares extracted frame i+1 with frame i.
            anomalies.append(round((i + 1) / 5.0, 1))
    return anomalies


def test_pipeline_on_unseen_video_and_multilanguage():
    shutil.copy2(VIDEO, BACKUP)
    challenge = Path('/tmp/challenge.mp4')
    try:
        make_challenge(challenge)
        expected = reference_result(challenge)
        assert expected, 'Internal challenge produced no anomalies'
        shutil.copy2(challenge, VIDEO)
        trace = run_pipeline()
        detected = read_output()
        assert len(detected) == len(expected), f'Expected {expected}, detected {detected}'
        assert all(abs(a - b) <= 0.11 for a, b in zip(sorted(detected), sorted(expected))), f'Expected {expected}, detected {detected}'
        assert_multilanguage(trace)
    finally:
        if BACKUP.exists():
            shutil.copy2(BACKUP, VIDEO)


def test_anomaly_timestamps_mae():
    """Verify the detected anomaly timestamps against the ground truth using MAE."""
    run_pipeline()
    target_file = "/home/user/anomaly_timestamps.json"

    assert os.path.exists(target_file), f"Output file is missing: {target_file}"
    assert os.path.isfile(target_file), f"Output path is not a file: {target_file}"

    try:
        with open(target_file, "r") as f:
            detected = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to parse JSON from {target_file}: {e}")

    assert isinstance(detected, list), f"Expected a JSON array, got {type(detected).__name__}"

    # Ensure all elements are numbers
    for val in detected:
        assert isinstance(val, (int, float)), f"Expected numbers in JSON array, got {type(val).__name__}: {val}"

    truth = [14.2, 42.6, 89.0]

    detected = sorted(detected)
    truth = sorted(truth)

    error_sum = 0.0

    for d in detected:
        if not truth:
            break
        closest = min(truth, key=lambda t: abs(t - d))
        error_sum += abs(closest - d)

    # Penalties for length mismatch
    penalty = abs(len(detected) - len(truth)) * 10.0
    error_sum += penalty

    mae = error_sum / max(len(truth), 1)

    threshold = 1.0
    assert mae <= threshold, f"MAE {mae:.2f} exceeds threshold of {threshold:.2f}. Detected: {detected}, Truth: {truth}"

    # Require one-to-one matching so a repeated timestamp cannot stand in for
    # multiple distinct anomalies.
    assert len(detected) == len(truth), f'Expected exactly {len(truth)} anomalies, got {detected}'
    paired_mae = sum(abs(d - t) for d, t in zip(detected, truth)) / len(truth)
    assert paired_mae <= threshold, f'One-to-one MAE {paired_mae:.2f} exceeds threshold of {threshold:.2f}. Detected: {detected}, Truth: {truth}'
    read_output()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
