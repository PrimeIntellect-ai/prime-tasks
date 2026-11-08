#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

import nbformat
import pytest

SCRIPT_PATH = "/home/user/orchestrate_pipeline.sh"
NOTEBOOK_PATH = "/home/user/generate_scores.ipynb"
RAW_SCORES_PATH = "/home/user/raw_scores.txt"
CALC_VAR_PATH = "/home/user/calculated_variance.txt"
REF_VAR_PATH = "/home/user/reference_variance.txt"
STATUS_LOG_PATH = "/home/user/pipeline_status.log"
MARKER_PATH = "/tmp/notebook_execution_marker"


def test_orchestrator_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        script = f.read()
    assert re.search(r"\bawk\b", script), "The orchestrator must use awk to calculate the variance."
    assert (re.search(r"\bjupyter\b", script) and re.search(r"\bnbconvert\b", script)) or re.search(r"\bpapermill\b", script), \
        "The orchestrator must execute the notebook using jupyter nbconvert or papermill."


def install_notebook(scores, marker):
    code = f'''scores = {scores!r}
with open({RAW_SCORES_PATH!r}, "w") as f:
    for score in scores:
        f.write(format(score, ".17g") + "\\n")
with open({MARKER_PATH!r}, "w") as f:
    f.write({marker!r})
'''
    nb = nbformat.v4.new_notebook()
    nb["cells"] = [nbformat.v4.new_code_cell(code)]
    nbformat.write(nb, NOTEBOOK_PATH)


def run_and_check(scores, reference):
    marker = secrets.token_hex(24)
    install_notebook(scores, marker)
    with open(REF_VAR_PATH, "w") as f:
        f.write(f"{reference:.12f}\n")

    for path in [RAW_SCORES_PATH, CALC_VAR_PATH, STATUS_LOG_PATH, MARKER_PATH]:
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"

    assert os.path.isfile(MARKER_PATH), "The notebook's execution marker was not created."
    with open(MARKER_PATH) as f:
        assert f.read() == marker, "The expected notebook instance was not executed."

    executed_nb = nbformat.read(NOTEBOOK_PATH, as_version=4)
    assert executed_nb.cells[0].get("execution_count") is not None, \
        "The notebook was not executed in place."

    assert os.path.isfile(RAW_SCORES_PATH), f"{RAW_SCORES_PATH} was not created by the notebook."
    with open(RAW_SCORES_PATH) as f:
        raw_lines = [line.strip() for line in f if line.strip()]
    parsed_scores = [float(line) for line in raw_lines]
    assert len(parsed_scores) > 0, "No scores found in raw_scores.txt"
    assert len(parsed_scores) == len(scores), "raw_scores.txt does not contain the notebook's complete output."
    assert all(a == b for a, b in zip(parsed_scores, scores)), \
        "raw_scores.txt does not match the notebook's true output."

    n = len(parsed_scores)
    mean = sum(parsed_scores) / n
    expected_variance = sum((x - mean) ** 2 for x in parsed_scores) / n

    assert os.path.isfile(CALC_VAR_PATH), f"{CALC_VAR_PATH} was not created."
    with open(CALC_VAR_PATH) as f:
        calc_var_str = f.read().strip()
    try:
        calc_var = float(calc_var_str)
    except ValueError:
        pytest.fail(f"Calculated variance is not a valid float: {calc_var_str}")

    assert math.isfinite(calc_var), "Calculated variance must be finite."
    assert math.isclose(calc_var, expected_variance, rel_tol=1e-5, abs_tol=1e-6), \
        f"Calculated variance {calc_var} does not match expected {expected_variance}"
    assert len(calc_var_str.split('.')[-1]) == 6, \
        f"Variance {calc_var_str} is not formatted to 6 decimal places."
    assert re.fullmatch(r"[+-]?\d+\.\d{6}", calc_var_str), \
        f"Variance {calc_var_str} is not a single number formatted to 6 decimal places."

    assert os.path.isfile(REF_VAR_PATH), f"Reference variance file {REF_VAR_PATH} is missing."
    with open(REF_VAR_PATH) as f:
        ref_var = float(f.read().strip())
    expected_status = "PASS" if abs(calc_var - ref_var) < 0.0001 else "FAIL"

    assert os.path.isfile(STATUS_LOG_PATH), f"{STATUS_LOG_PATH} was not created."
    with open(STATUS_LOG_PATH) as f:
        status = f.read().strip()
    assert status == expected_status, \
        f"Expected status '{expected_status}', but got '{status}' in {STATUS_LOG_PATH}"


def test_orchestrator_execution_and_outputs():
    rng = secrets.SystemRandom()
    offsets = [rng.randint(-50, 50) / 1000.0 for _ in range(37)]
    offsets.extend([-0.075, 0.083, 0.041])
    scores = [1_000_000_000.0 + offset for offset in offsets]

    mean = sum(scores) / len(scores)
    expected = sum((x - mean) ** 2 for x in scores) / len(scores)

    run_and_check(scores, expected)
    run_and_check(list(reversed(scores)), expected + 1.0)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
