#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess


def get_expected_mode():
    """
    Computes the expected mode using the same libraries available in the environment,
    but invoked via subprocess to keep the test file itself strictly stdlib-only.
    """
    script = """
import numpy as np
import pandas as pd
from scipy.stats import gaussian_kde
from scipy.optimize import minimize

df = pd.read_csv('/home/user/observations.csv')
vals = df[['val_1', 'val_2', 'val_3']].values.flatten()
kde = gaussian_kde(vals)

def neg_kde(x):
    return -kde(x)[0]

res = minimize(neg_kde, x0=np.array([0.0]))
print(f"{res.x[0]:.3f}")
"""
    result = subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    )
    return result.stdout.strip()


def run_pipeline():
    """Execute the submitted pipeline and require it to freshly create its result."""
    result_path = "/home/user/result.txt"
    if os.path.exists(result_path):
        os.remove(result_path)

    completed = subprocess.run(
        [sys.executable, "/home/user/pipeline.py"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, (
        "pipeline.py failed when executed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(result_path), (
        "pipeline.py did not freshly create /home/user/result.txt"
    )


def test_pipeline_script_exists():
    """Check that the pipeline script was created."""
    path = "/home/user/pipeline.py"
    assert os.path.isfile(path), f"Pipeline script {path} does not exist."


def test_pipeline_executes():
    """Execute the submitted artifact on the original observations."""
    run_pipeline()


def test_result_file_exists():
    """Check that the result file was created."""
    path = "/home/user/result.txt"
    assert os.path.isfile(path), f"Result file {path} does not exist."


def test_result_content():
    """Check that the result file contains the correct mode value."""
    path = "/home/user/result.txt"
    assert os.path.isfile(path), f"Result file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_mode = get_expected_mode()

    assert content == expected_mode, (
        f"Incorrect value in {path}. "
        f"Expected '{expected_mode}', but got '{content}'."
    )


def test_pipeline_on_unseen_observations():
    """Exercise the pipeline on fresh wide-format inputs with derived answers."""
    import numpy as np
    import pandas as pd

    observations_path = "/home/user/observations.csv"
    result_path = "/home/user/result.txt"

    with open(observations_path, "rb") as f:
        original_observations = f.read()
    with open(result_path, "rb") as f:
        original_result = f.read()

    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    cases = [
        rng.normal(loc=1.1, scale=0.55, size=(47, 3)),
        np.concatenate([
            rng.normal(loc=-1.4, scale=0.35, size=(31, 3)),
            rng.normal(loc=1.8, scale=0.65, size=(16, 3)),
        ], axis=0),
    ]

    try:
        for values in cases:
            frame = pd.DataFrame(values, columns=["val_1", "val_2", "val_3"])
            frame.insert(0, "id", rng.permutation(np.arange(1000, 1000 + len(frame))))
            frame.to_csv(observations_path, index=False)

            expected_mode = get_expected_mode()
            run_pipeline()

            with open(result_path, "r") as f:
                content = f.read().strip()
            assert content == expected_mode, (
                "pipeline.py did not compute the KDE mode for a fresh input. "
                f"Expected '{expected_mode}', but got '{content}'."
            )
    finally:
        with open(observations_path, "wb") as f:
            f.write(original_observations)
        with open(result_path, "wb") as f:
            f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
