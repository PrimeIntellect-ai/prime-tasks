#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import subprocess
import wave
from pathlib import Path

import numpy as np
import pandas as pd

REPORT = Path('/home/user/final_report.csv')
ANOMALIES = Path('/home/user/anomalies.csv')
SOURCE = Path('/home/user/detector.cpp')
BINARY = Path('/tmp/submitted_detector')


def audio_truth():
    with wave.open('/app/sensor_audio.wav', 'rb') as wf:
        assert wf.getnchannels() == 1
        rate = wf.getframerate()
        width = wf.getsampwidth()
        assert width == 2
        samples = np.frombuffer(wf.readframes(wf.getnframes()), dtype='<i2').astype(np.int32)

    above = np.abs(samples) > 26214
    starts = []
    i = 0
    while i < len(above):
        if not above[i]:
            i += 1
            continue
        start = i
        while i < len(above) and above[i]:
            i += 1
        if i - start >= 5:
            starts.append(start / rate)
    return np.asarray(starts, dtype=float)


def extracted_text_files():
    excluded = {REPORT.resolve(), ANOMALIES.resolve(), SOURCE.resolve()}
    found = []
    for root in (Path('/home/user'), Path('/tmp')):
        if not root.exists():
            continue
        for path in root.rglob('*'):
            try:
                resolved = path.resolve()
                if not path.is_file() or resolved in excluded or path.stat().st_size < 50000:
                    continue
                with path.open('r', encoding='utf-8', errors='strict') as f:
                    chunk = f.read(2_000_000)
                # A readable sample extraction should contain substantial numeric data.
                if len(re.findall(r'[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?', chunk)) >= 1000:
                    found.append(path)
            except (OSError, UnicodeError):
                pass
    return sorted(found, key=lambda p: str(p))[:12]


def generated_anomalies_are_readable():
    if not ANOMALIES.exists() or ANOMALIES.stat().st_size == 0:
        return False
    try:
        df = pd.read_csv(ANOMALIES)
        return 'Anomaly_Time_sec' in df.columns and len(df) > 0
    except Exception:
        return False


def run_submitted_detector(candidates):
    subprocess.run(
        ['g++', '-std=c++17', '-O2', str(SOURCE), '-o', str(BINARY)],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    attempts = [([str(BINARY)], None)]
    for candidate in candidates:
        attempts.extend([
            ([str(BINARY), str(candidate)], None),
            ([str(BINARY), str(candidate), str(ANOMALIES)], None),
            ([str(BINARY)], candidate),
        ])

    for command, stdin_path in attempts:
        ANOMALIES.unlink(missing_ok=True)
        try:
            if stdin_path is None:
                subprocess.run(command, cwd='/home/user', timeout=8,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            else:
                with stdin_path.open('rb') as inp:
                    subprocess.run(command, cwd='/home/user', stdin=inp, timeout=8,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except (subprocess.SubprocessError, OSError):
            continue
        if generated_anomalies_are_readable():
            return
    assert False, 'The submitted detector.cpp could not be executed to generate /home/user/anomalies.csv from the extracted amplitude data.'


def test_complete_audio_pipeline():
    # Preserve the original final-report assertions.
    assert REPORT.exists(), f'Final report file {REPORT} is missing.'
    try:
        report = pd.read_csv(REPORT)
    except Exception as e:
        assert False, f'Failed to read {REPORT} as CSV: {e}'

    assert 'Anomaly_Time_sec' in report.columns, f"'Anomaly_Time_sec' column is missing in {REPORT}."
    pred = np.sort(pd.to_numeric(report['Anomaly_Time_sec'], errors='coerce').to_numpy(dtype=float))
    original_truth = np.array([12.45, 45.12, 89.33])
    if len(pred) != len(original_truth):
        assert False, f'Expected {len(original_truth)} anomalies, but found {len(pred)}. MSE penalty applied.'
    mse = np.mean((pred - original_truth) ** 2)
    assert mse <= 0.05, f'MSE {mse:.4f} is greater than the threshold of 0.05. Predictions: {pred}'

    assert list(report.columns) == ['Anomaly_Time_sec', 'Machine_State', 'Batch_ID'], \
        'final_report.csv must contain exactly Anomaly_Time_sec,Machine_State,Batch_ID in that order.'
    assert np.isfinite(pred).all(), 'Anomaly_Time_sec contains a non-finite value.'

    assert SOURCE.exists() and SOURCE.is_file() and SOURCE.stat().st_size > 0, \
        '/home/user/detector.cpp is missing or empty.'
    candidates = extracted_text_files()
    assert candidates, 'No readable extracted amplitude data was found under /home/user or /tmp.'

    truth = audio_truth()
    assert len(truth) > 0, 'No qualifying anomaly runs were found in the supplied audio.'
    run_submitted_detector(candidates)

    generated = pd.read_csv(ANOMALIES)
    assert list(generated.columns) == ['Anomaly_Time_sec'], \
        'anomalies.csv must contain the Anomaly_Time_sec column.'
    generated_times = np.sort(pd.to_numeric(generated['Anomaly_Time_sec'], errors='coerce').to_numpy(dtype=float))
    assert len(generated_times) == len(truth), \
        f'detector.cpp generated {len(generated_times)} anomalies; the audio contains {len(truth)} qualifying runs.'
    assert np.isfinite(generated_times).all(), 'Generated anomaly times contain a non-finite value.'
    generated_mse = np.mean((generated_times - np.sort(truth)) ** 2)
    assert generated_mse <= 0.05, \
        f'detector.cpp output does not match anomalies derived from the WAV (MSE={generated_mse:.4f}).'

    logs = pd.read_csv('/app/machine_logs.csv')
    assert {'Timestamp_sec', 'Machine_State', 'Batch_ID'}.issubset(logs.columns)
    log_times = pd.to_numeric(logs['Timestamp_sec'], errors='raise').to_numpy(dtype=float)

    ordered = report.copy()
    ordered['Anomaly_Time_sec'] = pd.to_numeric(ordered['Anomaly_Time_sec'], errors='raise')
    ordered = ordered.sort_values('Anomaly_Time_sec').reset_index(drop=True)
    for row, expected_time in zip(ordered.itertuples(index=False), np.sort(truth)):
        distances = np.abs(log_times - expected_time)
        nearest = int(np.argmin(distances))
        assert distances[nearest] <= 1.0, 'A detected anomaly has no log entry within the required 1.0-second window.'
        assert str(row.Machine_State) == str(logs.iloc[nearest]['Machine_State']), \
            f'Incorrect Machine_State for anomaly near {expected_time:.6f}.'
        assert str(row.Batch_ID) == str(logs.iloc[nearest]['Batch_ID']), \
            f'Incorrect Batch_ID for anomaly near {expected_time:.6f}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
