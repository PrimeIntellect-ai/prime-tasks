#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import subprocess
import tempfile
import numpy as np
from scipy.io import wavfile

TRUTH_PATH = "/tests/test_clean.wav"
assert os.path.isfile(TRUTH_PATH), f"Ground truth {TRUTH_PATH} is missing."
TRUTH_RATE, TRUTH_RAW = wavfile.read(TRUTH_PATH)
assert TRUTH_RAW.dtype == np.int16
TRUTH_DATA = TRUTH_RAW.astype(np.float32) / 32768.0
# Do not expose the oracle to the submitted pipeline when it is executed.
os.unlink(TRUTH_PATH)


def test_experiments_csv_exists_and_valid():
    csv_path = "/app/experiments.csv"
    assert os.path.isfile(csv_path), f"{csv_path} is missing."

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    # Preserve the original header-plus-five-rows assertion.
    assert len(rows) >= 6, f"{csv_path} must contain at least 5 different parameter combinations tested (plus header)."

    header = [cell.strip().lower() for cell in rows[0]]
    assert "mse" in header, "experiments.csv must include an mse column."
    mse_index = header.index("mse")
    parameter_indexes = [i for i, name in enumerate(header) if i != mse_index and name]
    assert parameter_indexes, "experiments.csv must include filter parameter columns."

    trials = rows[1:]
    for row in trials:
        assert len(row) > mse_index
        mse = float(row[mse_index])
        assert np.isfinite(mse), "Every trial must contain a finite MSE."

    combinations = {
        tuple(row[i].strip() if i < len(row) else "" for i in parameter_indexes)
        for row in trials
    }
    assert len(combinations) >= 5, "At least 5 different parameter combinations must be tracked."


def test_run_pipeline_sh_exists_and_executable():
    script_path = "/app/run_pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_test_cleaned_wav_exists():
    out_path = "/app/data/test_cleaned.wav"
    assert os.path.isfile(out_path), f"The output file {out_path} is missing."


def read_pcm16(filepath):
    rate, data = wavfile.read(filepath)
    assert data.dtype == np.int16, f"{filepath} must be a 16-bit PCM WAV file."
    return rate, data, data.astype(np.float32) / 32768.0


def assert_valid_audio(filepath):
    rate, raw, data = read_pcm16(filepath)
    assert rate == TRUTH_RATE, f"Sampling rates do not match: truth={TRUTH_RATE}, pred={rate}"
    assert raw.shape == TRUTH_RAW.shape, f"Output shape {raw.shape} does not match expected shape {TRUTH_RAW.shape}."
    mse = np.mean((TRUTH_DATA - data) ** 2)
    threshold = 0.005
    assert mse <= threshold, f"MSE {mse:.6f} exceeds the threshold of {threshold}."


def test_audio_mse_metric():
    pred_path = "/app/data/test_cleaned.wav"
    assert os.path.isfile(pred_path), f"Prediction {pred_path} is missing."
    assert_valid_audio(pred_path)


def test_pipeline_reproduces_valid_output():
    fd, output_path = tempfile.mkstemp(prefix="pipeline_output_", suffix=".wav")
    os.close(fd)
    os.unlink(output_path)
    try:
        subprocess.run(
            ["/app/run_pipeline.sh", "/app/data/test_noisy.wav", output_path],
            check=True,
            timeout=30,
            cwd="/app",
        )
        assert os.path.isfile(output_path), "run_pipeline.sh did not create its requested output."
        assert_valid_audio(output_path)
    finally:
        if os.path.exists(output_path):
            os.unlink(output_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
