#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from pathlib import Path

import numpy as np
import pytest

SCRIPT_PATH = Path('/home/user/analyze.sh')
DATA_PATH = Path('/home/user/sensor_data.csv')
PEAK_PATH = Path('/home/user/peak_freq.txt')
ZSCORE_PATH = Path('/home/user/zscore.txt')


def run_script():
    result = subprocess.run(
        ['bash', str(SCRIPT_PATH)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Script failed with error:\n{result.stderr}\n{result.stdout}"
    )


def expected_outputs(X):
    _, _, V = np.linalg.svd(X, full_matrices=False)
    temporal_component = V[0, :]
    spectrum = np.fft.rfft(temporal_component)
    power = np.abs(spectrum) ** 2
    power[0] = 0.0
    peak = int(np.argmax(power))
    zscore = (power[peak] - np.mean(power)) / np.std(power)
    return str(peak), f'{zscore:.2f}'


def read_outputs():
    assert PEAK_PATH.exists(), f"Output file {PEAK_PATH} is missing."
    assert ZSCORE_PATH.exists(), f"Output file {ZSCORE_PATH} is missing."
    return PEAK_PATH.read_text().strip(), ZSCORE_PATH.read_text().strip()


def test_analyze_script_exists_and_executable():
    """Check that the analyze.sh script exists and is executable."""
    assert SCRIPT_PATH.exists(), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_run_analyze_script():
    """Run the analyze.sh script to generate the outputs."""
    if not SCRIPT_PATH.exists():
        pytest.skip(f"Script {SCRIPT_PATH} does not exist.")
    run_script()


def test_peak_freq_output():
    """Check that the peak frequency output file has the correct value."""
    assert PEAK_PATH.exists(), f"Output file {PEAK_PATH} is missing."
    content = PEAK_PATH.read_text().strip()
    assert content == '150', f"Expected '150' in {PEAK_PATH}, but got '{content}'."


def test_zscore_output():
    """Check that the z-score output file has the correct value."""
    assert ZSCORE_PATH.exists(), f"Output file {ZSCORE_PATH} is missing."
    content = ZSCORE_PATH.read_text().strip()
    assert content == '22.51', f"Expected '22.51' in {ZSCORE_PATH}, but got '{content}'."


def test_pipeline_recomputes_from_csv():
    """Exercise the submitted pipeline on fresh, unpredictable input matrices."""
    original_data = DATA_PATH.read_bytes()
    try:
        seed = int.from_bytes(os.urandom(16), 'big')
        rng = np.random.default_rng(seed)

        for artifact_bin in rng.choice(
            np.array([37, 83, 219, 301, 407]), size=2, replace=False
        ):
            samples = np.arange(1024)
            phase = rng.uniform(0.0, 2.0 * np.pi)
            temporal = np.sin(
                2.0 * np.pi * int(artifact_bin) * samples / 1024.0 + phase
            )
            spatial = rng.normal(size=(50, 1))
            X = 7.0 * spatial @ temporal.reshape(1, -1)
            X += rng.normal(scale=0.8, size=(50, 1024))

            expected_peak, expected_zscore = expected_outputs(X)
            np.savetxt(DATA_PATH, X, delimiter=',')

            for output in (PEAK_PATH, ZSCORE_PATH):
                if output.exists():
                    output.unlink()

            run_script()
            actual_peak, actual_zscore = read_outputs()
            assert actual_peak == expected_peak, (
                f"Expected peak frequency '{expected_peak}' for generated data, "
                f"but got '{actual_peak}'."
            )
            assert actual_zscore == expected_zscore, (
                f"Expected z-score '{expected_zscore}' for generated data, "
                f"but got '{actual_zscore}'."
            )
    finally:
        DATA_PATH.write_bytes(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
