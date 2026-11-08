#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import cv2
import h5py
import numpy as np
import pytest

VERIFIER = Path('/home/user/verifier')
SOURCE = Path('/home/user/verifier.cpp')
VIDEO = Path('/app/experiment_video.mp4')


def run_program(program, filepath, timeout=8):
    try:
        return subprocess.run(
            [str(program), str(filepath)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        ).returncode
    except subprocess.TimeoutExpired:
        return -999


def video_frequency():
    cap = cv2.VideoCapture(str(VIDEO))
    fps = cap.get(cv2.CAP_PROP_FPS)
    positions = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        _, mask = cv2.threshold(gray, 180, 255, cv2.THRESH_BINARY)
        moments = cv2.moments(mask)
        positions.append(moments['m10'] / moments['m00'] if moments['m00'] else np.nan)
    cap.release()
    assert fps > 0 and len(positions) > 100, 'Could not analyze experiment video'
    x = np.asarray(positions, dtype=float)
    good = np.isfinite(x)
    assert good.sum() > 100, 'Pendulum blob was not detected'
    x[~good] = np.interp(np.flatnonzero(~good), np.flatnonzero(good), x[good])
    x -= x.mean()
    freqs = np.fft.rfftfreq(len(x), 1.0 / fps)
    spectrum = np.abs(np.fft.rfft(x))
    spectrum[0] = 0
    return float(freqs[int(np.argmax(spectrum))])


def rk4_classification(gamma, omega_sq, dt, t_max, target):
    theta, velocity, t = 1.0, 0.0, 0.0
    positive_crossings = []

    def accel(th, vel):
        return -gamma * vel - omega_sq * math.sin(th)

    if not all(math.isfinite(v) for v in (gamma, omega_sq, dt, t_max)):
        return False
    if dt <= 0 or t_max <= 0:
        return False

    max_steps = 2000000
    steps = 0
    while t < t_max and steps < max_steps:
        h = min(dt, t_max - t)
        old_theta = theta

        k1_th = velocity
        k1_v = accel(theta, velocity)
        k2_th = velocity + 0.5 * h * k1_v
        k2_v = accel(theta + 0.5 * h * k1_th, velocity + 0.5 * h * k1_v)
        k3_th = velocity + 0.5 * h * k2_v
        k3_v = accel(theta + 0.5 * h * k2_th, velocity + 0.5 * h * k2_v)
        k4_th = velocity + h * k3_v
        k4_v = accel(theta + h * k3_th, velocity + h * k3_v)

        theta += h * (k1_th + 2*k2_th + 2*k3_th + k4_th) / 6.0
        velocity += h * (k1_v + 2*k2_v + 2*k3_v + k4_v) / 6.0
        t += h
        steps += 1

        if not math.isfinite(theta) or not math.isfinite(velocity) or abs(theta) > 100.0:
            return False
        if old_theta < 0.0 <= theta and velocity > 0.0:
            positive_crossings.append(t)

    if steps >= max_steps or len(positive_crossings) < 2:
        return False
    periods = np.diff(positive_crossings)
    frequency = 1.0 / float(np.mean(periods))
    return abs(frequency - target) <= 0.10 * target


def write_config(path, values):
    with h5py.File(path, 'w') as f:
        for key, value in values.items():
            f.create_dataset(key, data=np.float64(value))


def test_verifier_exists():
    assert VERIFIER.is_file(), f'Verifier executable {VERIFIER} is missing.'
    assert os.access(VERIFIER, os.X_OK), f'Verifier {VERIFIER} is not executable.'


def test_required_source_and_build(tmp_path):
    assert SOURCE.is_file(), f'Required source file {SOURCE} is missing.'
    text = SOURCE.read_text(errors='ignore')
    lower = text.lower()
    assert 'h5cpp.h' in lower, 'Source does not use the HDF5 C++ API.'
    assert 'h5file' in lower and 'opendataset' in lower, 'Source does not open HDF5 datasets through the C++ API.'
    for name in ('gamma', 'omega_sq', 'dt', 't_max'):
        assert re.search(r'["\']' + re.escape(name) + r'["\']', text), f'Source does not read {name}.'
    assert 'sin(' in lower or 'std::sin' in lower, 'Pendulum sine term is missing.'
    for stage in ('k1', 'k2', 'k3', 'k4'):
        assert stage in lower, 'Source does not visibly implement all four RK4 stages.'
    assert 'isfinite' in lower and re.search(r'100(?:\.0+)?', text), 'Required stability checks are missing.'

    rebuilt = tmp_path / ('rebuilt_' + secrets.token_hex(6))
    result = subprocess.run(
        ['h5c++', '-std=c++11', str(SOURCE), '-o', str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=45,
    )
    assert result.returncode == 0, 'verifier.cpp does not compile:\n' + result.stderr.decode(errors='replace')
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)
    os.environ['REBUILT_VERIFIER'] = str(rebuilt)


def test_video_analysis_script_exists_and_runs():
    candidates = []
    for root, _, files in os.walk('/home/user'):
        for filename in files:
            path = Path(root) / filename
            if path == SOURCE or path.suffix.lower() not in ('.py', '.cpp', '.cc', '.cxx'):
                continue
            try:
                text = path.read_text(errors='ignore').lower()
            except OSError:
                continue
            references_video = 'experiment_video' in text or ('video' in text and ('cv2' in text or 'ffmpeg' in text))
            analyzes_motion = any(x in text for x in ('fft', 'fourier', 'peak', 'crossing', 'frequency', 'freq'))
            detects_blob = any(x in text for x in ('threshold', 'moment', 'centroid', 'contour', 'bright', 'white'))
            if references_video and analyzes_motion and detects_blob:
                candidates.append(path)

    assert candidates, 'No video-analysis source script was found under /home/user.'
    errors = []
    for path in candidates:
        commands = []
        if path.suffix.lower() == '.py':
            commands = [
                ['python3', str(path), str(VIDEO)],
                ['python3', str(path)],
            ]
        else:
            output = Path(tempfile.gettempdir()) / ('video_analysis_' + secrets.token_hex(6))
            build = subprocess.run(['g++', '-std=c++11', str(path), '-o', str(output)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if build.returncode == 0:
                commands = [[str(output), str(VIDEO)], [str(output)]]
            else:
                errors.append(f'{path}: compilation failed')
                continue
        for command in commands:
            try:
                result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=35)
                if result.returncode == 0:
                    return
                errors.append(f'{path}: exit {result.returncode}')
            except subprocess.TimeoutExpired:
                errors.append(f'{path}: timed out')
    pytest.fail('No video-analysis script executed successfully. ' + '; '.join(errors))


def test_clean_corpus():
    clean_dir = '/app/corpus/clean'
    assert os.path.isdir(clean_dir), f'Clean corpus directory {clean_dir} is missing.'
    clean_files = sorted(f for f in os.listdir(clean_dir) if f.endswith('.h5'))
    assert len(clean_files) > 0, 'No clean .h5 files found.'
    failed_files = []
    for filename in clean_files:
        if run_program(VERIFIER, os.path.join(clean_dir, filename)) != 0:
            failed_files.append(filename)
    assert not failed_files, f'{len(failed_files)} of {len(clean_files)} clean modified (rejected instead of accepted): {", ".join(failed_files)}'


def test_evil_corpus():
    evil_dir = '/app/corpus/evil'
    assert os.path.isdir(evil_dir), f'Evil corpus directory {evil_dir} is missing.'
    evil_files = sorted(f for f in os.listdir(evil_dir) if f.endswith('.h5'))
    assert len(evil_files) > 0, 'No evil .h5 files found.'
    bypassed_files = []
    for filename in evil_files:
        if run_program(VERIFIER, os.path.join(evil_dir, filename)) == 0:
            bypassed_files.append(filename)
    assert not bypassed_files, f'{len(bypassed_files)} of {len(evil_files)} evil bypassed (accepted instead of rejected): {", ".join(bypassed_files)}'


def test_generated_hdf5_configs(tmp_path):
    target = video_frequency()
    assert 0.35 < target < 0.70, f'Unexpected measured video frequency: {target}'
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'little'))

    configs = []
    for _ in range(6):
        configs.append({
            'gamma': float(rng.uniform(0.03, 0.18)),
            'omega_sq': float(rng.uniform(9.75, 10.20)),
            'dt': float(rng.uniform(0.004, 0.022)),
            't_max': float(rng.uniform(13.0, 17.0)),
        })
    for _ in range(4):
        omega = 2.0 * math.pi * float(rng.uniform(0.15, 0.28))
        configs.append({'gamma': 0.1, 'omega_sq': omega*omega, 'dt': float(rng.uniform(0.006, 0.02)), 't_max': 16.0})
    for _ in range(4):
        omega = 2.0 * math.pi * float(rng.uniform(1.1, 1.7))
        configs.append({'gamma': 0.1, 'omega_sq': omega*omega, 'dt': float(rng.uniform(0.003, 0.012)), 't_max': 14.0})
    for _ in range(4):
        configs.append({'gamma': 0.1, 'omega_sq': float(rng.uniform(9.5, 11.0)), 'dt': float(rng.uniform(2.3, 3.2)), 't_max': 14.0})
    configs.append({'gamma': float(rng.uniform(7.0, 12.0)), 'omega_sq': 9.9, 'dt': 0.01, 't_max': 14.0})
    configs.append({'gamma': 0.1, 'omega_sq': 9.9, 'dt': 0.01, 't_max': float(rng.uniform(0.3, 0.8))})

    programs = [VERIFIER]
    rebuilt = os.environ.get('REBUILT_VERIFIER')
    assert rebuilt, 'Independent source build was not created.'
    programs.append(Path(rebuilt))

    expected_counts = {True: 0, False: 0}
    failures = []
    random_dir = tmp_path / ('inputs_' + secrets.token_hex(10))
    random_dir.mkdir()
    for index, config in enumerate(configs):
        expected = rk4_classification(target=target, **config)
        expected_counts[expected] += 1
        filepath = random_dir / (secrets.token_hex(12) + '.h5')
        write_config(filepath, config)
        for program in programs:
            accepted = run_program(program, filepath) == 0
            if accepted != expected:
                failures.append((program.name, index, config, expected))

    assert expected_counts[True] >= 4 and expected_counts[False] >= 8, 'Generated tests lacked classification diversity.'
    assert not failures, 'Generated HDF5 classifications failed: ' + repr(failures[:5])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
