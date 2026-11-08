#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

HOME = Path('/home/user')
DATA = HOME / 'data'
SAMPLES = DATA / 'samples'
NORMAL = DATA / 'normal'
ANOMALIES = DATA / 'anomalies'
BASELINE = DATA / 'baseline.csv'
SCRIPT = HOME / 'organize_datasets.py'
SUMMARY = HOME / 'summary.txt'
VENV_PYTHON = HOME / 'ml_env/bin/python'
ORIGINAL_NAMES = [f'sample_{i}.csv' for i in range(1, 6)]


def run_checked(command, timeout=120):
    return subprocess.run(
        command,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        cwd='/home/user',
    )


def compute_expected():
    code = r'''\
import glob
import json
import pandas as pd
from sklearn.ensemble import IsolationForest

baseline = pd.read_csv('/home/user/data/baseline.csv')[['sensor_x', 'sensor_y']]
model = IsolationForest(random_state=42)
model.fit(baseline)
result = {}
for path in sorted(glob.glob('/home/user/data/samples/*.csv')):
    frame = pd.read_csv(path)[['sensor_x', 'sensor_y']]
    result[path.rsplit('/', 1)[-1]] = float(model.decision_function(frame).mean())
print(json.dumps(result, sort_keys=True))
'''
    result = run_checked([str(VENV_PYTHON), '-c', code])
    return json.loads(result.stdout)


def clear_run_outputs():
    for directory in (NORMAL, ANOMALIES):
        if directory.exists():
            shutil.rmtree(directory)
    if SAMPLES.exists():
        shutil.rmtree(SAMPLES)
    SAMPLES.mkdir(parents=True)
    if SUMMARY.exists() or SUMMARY.is_symlink():
        SUMMARY.unlink()


def execute_submission():
    run_checked([str(VENV_PYTHON), str(SCRIPT)])


def assert_run_matches(expected):
    assert NORMAL.is_dir(), f'Directory not found: {NORMAL}'
    assert ANOMALIES.is_dir(), f'Directory not found: {ANOMALIES}'
    assert SAMPLES.is_dir(), f'Directory not found: {SAMPLES}'
    assert not list(SAMPLES.iterdir()), f'Expected {SAMPLES} to be empty'

    for filename, score in expected.items():
        destination = ANOMALIES if score < 0 else NORMAL
        other = NORMAL if score < 0 else ANOMALIES
        assert (destination / filename).is_file(), f'{filename} was placed in the wrong directory'
        assert not (other / filename).exists(), f'{filename} appears in both output directories'

    actual_files = {
        path.name for directory in (NORMAL, ANOMALIES)
        for path in directory.iterdir() if path.is_file()
    }
    assert actual_files == set(expected), f'Unexpected output files: {actual_files ^ set(expected)}'

    assert SUMMARY.is_file(), f'Summary file missing at {SUMMARY}'
    actual_lines = SUMMARY.read_text().splitlines()
    expected_lines = [f'{name}: {expected[name]:.3f}' for name in sorted(expected)]
    assert actual_lines == expected_lines, (
        f'Summary values or formatting are incorrect. Expected {expected_lines}, got {actual_lines}'
    )


@pytest.fixture(scope='session', autouse=True)
def prepared_state():
    assert SCRIPT.is_file(), f'Required Python script not found at {SCRIPT}'
    assert not SCRIPT.is_symlink(), f'Required script must be a regular file, not a symlink: {SCRIPT}'
    assert VENV_PYTHON.is_file(), f'Virtual environment python not found at {VENV_PYTHON}'

    package_check = '''
from importlib import metadata
import pandas
import sklearn
from sklearn.ensemble import IsolationForest
assert metadata.version('pandas')
assert metadata.version('scikit-learn')
'''
    run_checked([str(VENV_PYTHON), '-c', package_check])

    baseline_bytes = BASELINE.read_bytes()
    original_files = {}
    for name in ORIGINAL_NAMES:
        locations = [directory / name for directory in (SAMPLES, NORMAL, ANOMALIES)]
        present = [path for path in locations if path.is_file()]
        assert len(present) == 1, f'Expected exactly one existing copy of {name}, found {present}'
        original_files[name] = present[0].read_bytes()

    original_expected = None
    try:
        clear_run_outputs()
        seed = int.from_bytes(os.urandom(8), 'big')
        rng = np.random.default_rng(seed)
        pd.DataFrame({
            'sensor_x': rng.normal(1.7, 0.55, 450),
            'sensor_y': rng.normal(-2.2, 0.65, 450),
        }).to_csv(BASELINE, index=False)

        probes = {
            'probe_alpha.csv': (rng.normal(1.7, 0.45, 73), rng.normal(-2.2, 0.5, 73)),
            'probe_beta.csv': (rng.normal(10.0, 0.4, 61), rng.normal(9.0, 0.4, 61)),
            'probe_gamma.csv': (rng.normal(-8.0, 0.5, 89), rng.normal(-10.0, 0.5, 89)),
        }
        for name, (x_values, y_values) in probes.items():
            pd.DataFrame({'sensor_x': x_values, 'sensor_y': y_values}).to_csv(SAMPLES / name, index=False)

        probe_expected = compute_expected()
        assert set(probe_expected) == set(probes)
        execute_submission()
        assert_run_matches(probe_expected)
    finally:
        clear_run_outputs()
        BASELINE.write_bytes(baseline_bytes)
        for name, contents in original_files.items():
            (SAMPLES / name).write_bytes(contents)
        original_expected = compute_expected()
        execute_submission()

    return original_expected


def test_virtual_environment_exists():
    venv_python = '/home/user/ml_env/bin/python'
    assert os.path.isfile(venv_python), f'Virtual environment python not found at {venv_python}'


def test_directories_and_files_moved():
    normal_dir = '/home/user/data/normal'
    anomalies_dir = '/home/user/data/anomalies'
    samples_dir = '/home/user/data/samples'

    assert os.path.isdir(normal_dir), f'Directory not found: {normal_dir}'
    assert os.path.isdir(anomalies_dir), f'Directory not found: {anomalies_dir}'

    expected_normal = ['sample_1.csv', 'sample_3.csv', 'sample_5.csv']
    expected_anomalies = ['sample_2.csv', 'sample_4.csv']

    for filename in expected_normal:
        path = os.path.join(normal_dir, filename)
        assert os.path.isfile(path), f'Expected normal file missing: {path}'

    for filename in expected_anomalies:
        path = os.path.join(anomalies_dir, filename)
        assert os.path.isfile(path), f'Expected anomaly file missing: {path}'

    remaining_samples = os.listdir(samples_dir)
    assert len(remaining_samples) == 0, f'Expected {samples_dir} to be empty, but found: {remaining_samples}'


def test_summary_file(prepared_state):
    summary_path = '/home/user/summary.txt'
    assert os.path.isfile(summary_path), f'Summary file missing at {summary_path}'

    with open(summary_path, 'r') as handle:
        lines = [line.strip() for line in handle if line.strip()]

    assert len(lines) == 5, f'Expected 5 lines in summary.txt, found {len(lines)}'

    filenames = []
    reported = {}
    for line in lines:
        match = re.match(r'^(sample_\d\.csv):\s*(-?\d+\.\d{3})$', line)
        assert match, f"Line does not match expected format 'filename.csv: <mean_score>' with 3 decimal places: '{line}'"

        filename = match.group(1)
        score = float(match.group(2))
        filenames.append(filename)
        reported[filename] = match.group(2)

        if filename in ['sample_2.csv', 'sample_4.csv']:
            assert score < 0, f'Expected negative score for anomaly {filename}, got {score}'
        else:
            assert score >= 0, f'Expected non-negative score for normal {filename}, got {score}'

    assert filenames == sorted(filenames), 'The lines in summary.txt are not sorted alphabetically by filename.'
    assert set(filenames) == set(ORIGINAL_NAMES), f'Unexpected or duplicate summary filenames: {filenames}'

    expected_text = {name: f'{score:.3f}' for name, score in prepared_state.items()}
    assert reported == expected_text, f'Reported scores do not match IsolationForest results: {reported}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
