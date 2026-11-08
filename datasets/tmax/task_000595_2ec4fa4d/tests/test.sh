#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy.io import wavfile

WORKSPACE = '/home/user/workspace'
SCRIPT_PATH = os.path.join(WORKSPACE, 'decode.py')
CSV_PATH = os.path.join(WORKSPACE, 'loads.csv')
WAV_PATH = '/app/telemetry.wav'


def expected_from_wav(path):
    rate, samples = wavfile.read(path)
    values = np.asarray(samples, dtype=np.float64)
    if values.ndim > 1:
        values = np.max(np.abs(values), axis=1)
    else:
        values = np.abs(values)

    peak = float(np.max(values))
    assert peak > 0, 'Telemetry audio contains no signal'
    active = np.flatnonzero(values > max(1.0, peak * 0.05))
    assert len(active) > 0, 'Telemetry audio contains no detectable beeps'

    # Tone zero-crossings are very short; only long silent gaps separate beeps.
    split_points = np.flatnonzero(np.diff(active) > int(rate * 0.1)) + 1
    groups = np.split(active, split_points)
    return np.array([
        round((((group[-1] - group[0] + 1) / rate) * 1000.0) / 10.0, 1)
        for group in groups
    ])


def read_and_validate_csv(expected):
    assert os.path.exists(CSV_PATH), f'File not found: {CSV_PATH}'
    try:
        df = pd.read_csv(CSV_PATH)
    except Exception as exc:
        pytest.fail(f'Failed to read or parse {CSV_PATH}: {exc}')

    assert list(df.columns) == ['Day', 'Load'], "CSV must have exactly the columns 'Day' and 'Load'"
    assert len(df) == len(expected), f'Expected {len(expected)} rows in CSV, found {len(df)}'
    assert np.array_equal(df['Day'].to_numpy(), np.arange(1, len(expected) + 1)), 'Day must run from 1 through 30'

    loads = pd.to_numeric(df['Load'], errors='coerce').to_numpy(dtype=float)
    assert np.all(np.isfinite(loads)), 'All Load values must be finite numbers'
    assert np.allclose(loads, np.round(loads, 1), atol=1e-9), 'Load values must be rounded to one decimal place'
    assert np.allclose(loads, expected, atol=0.15), f'Decoded loads do not match beep durations: {loads}'
    return df


def run_decoder():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f'decode.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}'
    assert os.path.isfile(CSV_PATH), 'decode.py did not create loads.csv'


def write_test_wav(path, loads):
    rate = 44100
    frequency = 1000.0
    chunks = []
    for index, load in enumerate(loads):
        duration = (load * 10.0) / 1000.0
        t = np.arange(int(rate * duration), dtype=np.float64) / rate
        chunks.append(np.int16(np.sin(2 * np.pi * frequency * t) * 32767))
        if index != len(loads) - 1:
            chunks.append(np.zeros(int(rate * 0.5), dtype=np.int16))
    wavfile.write(path, rate, np.concatenate(chunks))


def test_decode_script_executes_and_decodes_audio():
    assert os.path.isfile(SCRIPT_PATH), f'File not found: {SCRIPT_PATH}'
    original_audio = open(WAV_PATH, 'rb').read()
    try:
        # Runtime-random durations prevent a script that merely writes the known CSV
        # from passing without decoding the audio.
        synthetic_loads = np.array([
            (250 + secrets.randbelow(701)) / 10.0 for _ in range(30)
        ])
        write_test_wav(WAV_PATH, synthetic_loads)
        synthetic_expected = expected_from_wav(WAV_PATH)
        assert len(synthetic_expected) == 30
        run_decoder()
        read_and_validate_csv(synthetic_expected)
    finally:
        with open(WAV_PATH, 'wb') as audio_file:
            audio_file.write(original_audio)

    # Leave loads.csv generated from the actual supplied telemetry.
    original_expected = expected_from_wav(WAV_PATH)
    assert len(original_expected) == 30, f'Expected 30 beeps, found {len(original_expected)}'
    run_decoder()
    read_and_validate_csv(original_expected)


def test_loads_csv_metric():
    """Test that loads.csv is generated and MSE is within threshold."""
    assert os.path.exists(CSV_PATH), f"File not found: {CSV_PATH}"

    truth_loads = np.array([
        45.0, 52.1, 60.5, 42.0, 39.5, 70.2, 85.0, 91.5, 40.0, 38.5,
        45.6, 50.0, 55.5, 60.1, 62.3, 75.0, 80.0, 82.5, 88.0, 95.5,
        30.0, 35.5, 40.0, 42.5, 45.0, 50.0, 52.5, 60.0, 65.5, 70.0
    ])

    try:
        df = pd.read_csv(CSV_PATH)
        assert 'Load' in df.columns, "CSV must contain a 'Load' column"
        agent_loads = df['Load'].values
        assert len(agent_loads) == 30, f"Expected 30 rows in CSV, found {len(agent_loads)}"
        mse = np.mean((truth_loads - agent_loads) ** 2)
    except Exception as e:
        pytest.fail(f"Failed to read or parse {CSV_PATH}: {e}")

    assert mse <= 1.5, f"MSE {mse} exceeds threshold of 1.5"


def test_git_repo_and_commits():
    """Test that git repo exists and files are committed."""
    assert os.path.exists(os.path.join(WORKSPACE, '.git')), 'Git repository not initialized'

    status = subprocess.run(['git', 'ls-files'], cwd=WORKSPACE, capture_output=True, text=True)
    assert status.returncode == 0, 'Git ls-files command failed'
    committed_files = status.stdout.splitlines()
    assert 'decode.py' in committed_files, 'decode.py is not committed to the repository'
    assert 'loads.csv' in committed_files, 'loads.csv is not committed to the repository'

    head = subprocess.run(
        ['git', 'rev-parse', '--verify', 'HEAD'], cwd=WORKSPACE, capture_output=True, text=True
    )
    assert head.returncode == 0, 'Repository has no commit'
    tree = subprocess.run(
        ['git', 'ls-tree', '-r', '--name-only', 'HEAD'],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
    )
    assert tree.returncode == 0, 'Failed to inspect the HEAD commit'
    head_files = tree.stdout.splitlines()
    assert 'decode.py' in head_files, 'decode.py is not present in the HEAD commit'
    assert 'loads.csv' in head_files, 'loads.csv is not present in the HEAD commit'


def hook_csv(high_value=None):
    rows = ['Day,Load']
    for day in range(1, 31):
        value = 50.0
        if day == 1 and high_value is not None:
            value = high_value
        rows.append(f'{day},{value:.1f}')
    return ('\n'.join(rows) + '\n').encode()


def test_pre_commit_hook():
    """Test that pre-commit hook exists, is executable, and enforces the limit."""
    hook_path = os.path.join(WORKSPACE, '.git', 'hooks', 'pre-commit')
    assert os.path.exists(hook_path), f'pre-commit hook not found at {hook_path}'

    st = os.stat(hook_path)
    is_executable = bool(st.st_mode & stat.S_IXUSR)
    assert is_executable, f'pre-commit hook at {hook_path} is not executable'

    original_csv = open(CSV_PATH, 'rb').read()
    try:
        for forbidden in (100.0, 105.5):
            with open(CSV_PATH, 'wb') as csv_file:
                csv_file.write(hook_csv(forbidden))
            result = subprocess.run([hook_path], cwd=WORKSPACE, capture_output=True, text=True, timeout=10)
            assert result.returncode != 0, f'Hook accepted forbidden load {forbidden}'

        with open(CSV_PATH, 'wb') as csv_file:
            csv_file.write(hook_csv(99.9))
        result = subprocess.run([hook_path], cwd=WORKSPACE, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f'Hook rejected loads below 100.0: {result.stderr}'
    finally:
        with open(CSV_PATH, 'wb') as csv_file:
            csv_file.write(original_csv)


def test_cron_job():
    """Test that the cron job is configured correctly and is active."""
    status = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
    assert status.returncode == 0, 'Failed to read crontab or no crontab configured'

    crontab_content = status.stdout
    assert '0 2 * * *' in crontab_content, "Cron schedule '0 2 * * *' not found in crontab"
    assert SCRIPT_PATH in crontab_content, 'Script path not found in crontab'

    active_lines = [
        line.strip() for line in crontab_content.splitlines()
        if line.strip() and not line.lstrip().startswith('#')
    ]
    matching = []
    for line in active_lines:
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[:5] == ['0', '2', '*', '*', '*'] and SCRIPT_PATH in fields[5]:
            matching.append(line)
    assert matching, 'No active 02:00 daily cron entry runs decode.py'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
