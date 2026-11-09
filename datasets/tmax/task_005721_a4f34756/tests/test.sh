#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

import h5py
import numpy as np

SCRIPT_PATH = "/home/user/fit.sh"
DATASET_PATH = "/home/user/dataset.h5"
WEIGHT_PATH = "/home/user/weight.txt"


def run_fit():
    result = subprocess.run(
        [SCRIPT_PATH],
        text=True,
        capture_output=True,
        timeout=20,
        check=True,
    )
    return result.stdout.strip()


def test_h5dump_installed():
    """Verify that h5dump is installed."""
    assert shutil.which("h5dump") is not None, "h5dump is not installed. Did you install hdf5-tools?"


def test_fit_script_modified():
    """Verify that fit.sh is executable and has a lowered learning rate."""
    assert os.path.isfile(SCRIPT_PATH), f"Script file is missing at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "lr = 0.5" not in content, "The learning rate in /home/user/fit.sh is still 0.5. It should be lowered."
    matches = re.findall(r"\blr\s*=\s*([0-9]*\.?[0-9]+)", content)
    assert matches, "No numeric learning-rate assignment was found in /home/user/fit.sh"
    assert any(0 < float(value) <= 0.05 for value in matches), "The learning rate was not lowered to a sensible value."


def test_weight_file_exists_and_correct():
    """Verify that weight.txt exists and contains the correct weight."""
    assert os.path.isfile(WEIGHT_PATH), f"Output file {WEIGHT_PATH} is missing. Did you run the script and save the output?"

    with open(WEIGHT_PATH, "r") as f:
        content = f.read().strip()

    assert content == "3.50", f"The weight in {WEIGHT_PATH} is '{content}', expected '3.50'. Make sure the script converged properly."
    actual_output = run_fit()
    assert actual_output == content, "The saved weight does not match the output produced by /home/user/fit.sh."

    with h5py.File(DATASET_PATH, "r") as f:
        observations = np.asarray(f["/observations"])
    expected = np.dot(observations[:, 0], observations[:, 1]) / np.dot(observations[:, 0], observations[:, 0])
    assert actual_output == f"{expected:.2f}", "The script output does not match the fitted weight derived from dataset.h5."


def test_script_fits_unseen_datasets():
    """Execute the submitted script on fresh datasets with verifier-derived answers."""
    rng = np.random.default_rng()
    backup_fd, backup_path = tempfile.mkstemp(suffix=".h5")
    os.close(backup_fd)
    shutil.copy2(DATASET_PATH, backup_path)

    try:
        for _ in range(2):
            coefficient = rng.uniform(1.0, 5.0)
            x = np.linspace(0.0, 10.0, 50)
            y = coefficient * x + rng.normal(0.0, 0.004, x.size)
            observations = np.column_stack((x, y))

            with h5py.File(DATASET_PATH, "w") as f:
                f.create_dataset("/observations", data=observations)

            expected = np.dot(x, y) / np.dot(x, x)
            output = run_fit()
            assert output == f"{expected:.2f}", (
                f"fit.sh returned {output!r} for an unseen dataset; "
                f"expected the converged fitted weight {expected:.2f}."
            )
    finally:
        shutil.move(backup_path, DATASET_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
