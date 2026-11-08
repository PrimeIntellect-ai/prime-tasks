#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import subprocess
import tarfile

import numpy as np
import pytest
from sklearn.linear_model import LinearRegression

SCRIPT_PATH = "/home/user/predict.sh"
ARCHIVE_PATH = "/home/user/logs.tar.gz"


def test_script_exists():
    """Test that the predict.sh script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Expected {SCRIPT_PATH} to be a file."


def test_script_prediction_1():
    """Test the prediction for learning_rate=0.04 and batch_size=48."""
    result = subprocess.run(
        ["bash", SCRIPT_PATH, "0.04", "48"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    output = result.stdout.strip()
    assert output == "0.8920", f"Expected prediction '0.8920', got '{output}'"


def test_script_prediction_2():
    """Test the prediction for learning_rate=0.08 and batch_size=256."""
    result = subprocess.run(
        ["bash", SCRIPT_PATH, "0.08", "256"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    output = result.stdout.strip()
    assert output == "0.7240", f"Expected prediction '0.7240', got '{output}'"


def test_predictions_from_runtime_archive():
    """Require the script to parse and fit a freshly generated, unknown dataset."""
    assert os.path.isfile(ARCHIVE_PATH), f"Expected archive {ARCHIVE_PATH} does not exist."
    with open(ARCHIVE_PATH, "rb") as f:
        original_archive = f.read()

    rng = secrets.SystemRandom()
    intercept = rng.uniform(0.72, 0.96)
    lr_weight = rng.uniform(-0.9, 1.8)
    bs_weight = rng.uniform(-0.0017, -0.00015)
    rows = []

    try:
        archive_buffer = io.BytesIO()
        with tarfile.open(fileobj=archive_buffer, mode="w:gz") as archive:
            for i in range(17):
                lr = rng.uniform(0.004, 0.16)
                bs = rng.randint(16, 320)
                noise = rng.uniform(-0.018, 0.018)
                accuracy = intercept + lr_weight * lr + bs_weight * bs + noise
                lr_text = f"{lr:.8f}"
                accuracy_text = f"{accuracy:.8f}"
                rows.append((float(lr_text), float(bs), float(accuracy_text)))
                content = (
                    f"Experiment ID: {i}\n"
                    f"learning_rate: {lr_text}\n"
                    f"batch_size: {bs}\n"
                    f"validation_accuracy: {accuracy_text}\n"
                ).encode()
                info = tarfile.TarInfo(name=f"experiments/exp_{i}.log")
                info.size = len(content)
                info.mode = 0o644
                archive.addfile(info, io.BytesIO(content))

        with open(ARCHIVE_PATH, "wb") as f:
            f.write(archive_buffer.getvalue())
        os.chmod(ARCHIVE_PATH, 0o666)

        features = np.array([[lr, bs] for lr, bs, _ in rows], dtype=float)
        targets = np.array([acc for _, _, acc in rows], dtype=float)
        model = LinearRegression().fit(features, targets)

        for _ in range(5):
            query_lr = rng.uniform(0.006, 0.15)
            query_bs = rng.randint(20, 300)
            lr_arg = f"{query_lr:.8f}"
            bs_arg = str(query_bs)
            expected = f"{model.predict([[float(lr_arg), float(bs_arg)]])[0]:.4f}"
            result = subprocess.run(
                ["bash", SCRIPT_PATH, lr_arg, bs_arg],
                capture_output=True,
                text=True,
                timeout=30
            )
            assert result.returncode == 0, f"Script failed with error: {result.stderr}"
            output = result.stdout.strip()
            assert output == expected, (
                f"For learning_rate={lr_arg}, batch_size={bs_arg}, "
                f"expected '{expected}', got '{output}'"
            )
    finally:
        with open(ARCHIVE_PATH, "wb") as f:
            f.write(original_archive)
        os.chmod(ARCHIVE_PATH, 0o666)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
