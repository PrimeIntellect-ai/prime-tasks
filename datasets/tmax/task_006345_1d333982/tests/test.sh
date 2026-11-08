#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess

import numpy as np

SCRIPT_PATH = '/home/user/run_pipeline.sh'
RESULT_PATH = '/home/user/analysis_results.json'

# Derive the expected answers from the original input matrices before executing
# the submitted pipeline, so the pipeline cannot alter inputs to influence them.
SIMULATED = np.loadtxt('/home/user/simulated_data.csv', delimiter=',')
BASELINE = np.loadtxt('/home/user/baseline_data.csv', delimiter=',')
U, S, _ = np.linalg.svd(SIMULATED, full_matrices=False)
BASELINE_S = np.linalg.svd(BASELINE, compute_uv=False)

TOTAL_NORM = np.linalg.norm(S)
EXPECTED_K = next(
    k for k in range(len(S) + 1)
    if np.linalg.norm(S[k:]) / TOTAL_NORM < 0.05
)
EXPECTED_RATIO = round(float(S[0] / BASELINE_S[0]), 3)
SPECTRUM = np.abs(np.fft.fft(U[:, 0]))
EXPECTED_FREQ = int(np.argmax(SPECTRUM[1:]) + 1)


def test_run_pipeline_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SCRIPT_PATH} is not executable."


def test_run_pipeline_uses_jq():
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()
    assert 'jq' in content, f"The script {SCRIPT_PATH} does not use 'jq' as required."


def test_run_pipeline_uses_python():
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read().lower()
    assert 'python' in content, f"The script {SCRIPT_PATH} does not invoke Python as required."


def test_execute_run_pipeline():
    # Ensure the checked output is freshly produced by the submitted pipeline.
    if os.path.lexists(RESULT_PATH):
        os.unlink(RESULT_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_analysis_results_json():
    assert os.path.exists(RESULT_PATH), f"The output file {RESULT_PATH} is missing."
    assert os.path.isfile(RESULT_PATH), f"{RESULT_PATH} is not a file."

    with open(RESULT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {RESULT_PATH} is not valid JSON."

    assert "minimum_k" in data, "Key 'minimum_k' missing in JSON."
    assert "sv1_ratio" in data, "Key 'sv1_ratio' missing in JSON."
    assert "dominant_freq_index" in data, "Key 'dominant_freq_index' missing in JSON."

    assert data["minimum_k"] == EXPECTED_K, (
        f"Expected minimum_k to be {EXPECTED_K}, got {data['minimum_k']}."
    )
    assert abs(data["sv1_ratio"] - EXPECTED_RATIO) < 1e-4, (
        f"Expected sv1_ratio to be {EXPECTED_RATIO}, got {data['sv1_ratio']}."
    )
    assert data["dominant_freq_index"] == EXPECTED_FREQ, (
        f"Expected dominant_freq_index to be {EXPECTED_FREQ}, "
        f"got {data['dominant_freq_index']}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
