#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess

import nbformat
import pytest
from scipy import stats

C_PATH = "/home/user/score_fasta.c"
EXE_PATH = "/home/user/score_fasta"
INPUT_PATH = "/home/user/input.fasta"
NOTEBOOK_PATH = "/home/user/evaluate.ipynb"
REPORT_PATH = "/home/user/final_report.json"
BASELINE_PATH = "/home/user/baseline_results.txt"


def expected_score(path):
    total = 0.0
    with open(path, "r") as f:
        for line in f:
            if line.startswith(">"):
                continue
            seq = line.rstrip("\n")
            if not seq:
                continue
            gc_count = sum(ch in "GC" for ch in seq)
            length = len(seq)
            total += (gc_count / length) * 1.337 + (length * 0.001)
    return total


def run_score(path, threads=None):
    env = os.environ.copy()
    if threads is not None:
        env["OMP_NUM_THREADS"] = str(threads)
        env["OMP_DYNAMIC"] = "FALSE"
    result = subprocess.run(
        [EXE_PATH, path], capture_output=True, text=True, env=env, timeout=60
    )
    assert result.returncode == 0, f"Execution failed: {result.stderr}"
    output = result.stdout.strip()
    assert len(result.stdout.splitlines()) == 1, "Program must print only one output line"
    try:
        value = float(output)
    except ValueError:
        pytest.fail(f"Output is not a valid float: {result.stdout}")
    assert math.isfinite(value), "Output must be a finite float"
    return output, value


def test_c_code_fixed():
    assert os.path.isfile(C_PATH), f"File not found: {C_PATH}"
    with open(C_PATH, "r") as f:
        content = f.read()
    assert "#pragma omp atomic" not in content, "The C code still uses '#pragma omp atomic'"


def test_c_code_compiles_and_runs_correctly_and_deterministically():
    result = subprocess.run(
        ["gcc", "-O3", "-fopenmp", C_PATH, "-o", EXE_PATH],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Compilation failed: {result.stderr}"
    assert os.path.isfile(EXE_PATH) and os.access(EXE_PATH, os.X_OK)

    outputs = []
    for threads in [1, 2, 3, 4, 8] * 4:
        output, value = run_score(INPUT_PATH, threads)
        outputs.append(output)
        assert math.isclose(value, expected_score(INPUT_PATH), rel_tol=0.0, abs_tol=1e-6), (
            f"Incorrect score: got {value}, expected {expected_score(INPUT_PATH)}"
        )
    assert len(set(outputs)) == 1, "Score is not exactly deterministic across runs/thread counts"

    extra_path = "/tmp/verifier_extra.fasta"
    with open(extra_path, "w") as f:
        f.write(">all_gc\nGCGCGC\n>no_gc\nATATATAT\n>mixed\nACGTGCA\n")
    extra_outputs = []
    for threads in [1, 2, 4]:
        output, value = run_score(extra_path, threads)
        extra_outputs.append(output)
        assert math.isclose(value, expected_score(extra_path), rel_tol=0.0, abs_tol=1e-9), (
            f"Incorrect score on an additional FASTA: got {value}, expected {expected_score(extra_path)}"
        )
    assert len(set(extra_outputs)) == 1, "Additional FASTA result is not deterministic"


def test_notebook_execution_and_final_report():
    assert os.path.isfile(NOTEBOOK_PATH), f"File not found: {NOTEBOOK_PATH}"
    try:
        nbformat.read(NOTEBOOK_PATH, as_version=4)
    except Exception as exc:
        pytest.fail(f"evaluate.ipynb is not a valid Jupyter notebook: {exc}")

    real_exe = "/tmp/score_fasta.real"
    call_log = "/tmp/notebook_score_calls.log"
    if os.path.exists(call_log):
        os.remove(call_log)
    shutil.move(EXE_PATH, real_exe)
    wrapper = f'''#!/bin/bash
printf '%s\\n' "$(readlink -f -- "$1")" >> {call_log}
exec {real_exe} "$@"
'''
    with open(EXE_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(EXE_PATH, 0o755)

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    try:
        result = subprocess.run(
            ["jupyter", "nbconvert", "--to", "notebook", "--execute", "--inplace", NOTEBOOK_PATH],
            capture_output=True,
            text=True,
            timeout=300,
            cwd="/home/user",
        )
        assert result.returncode == 0, (
            f"Notebook execution failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    finally:
        if os.path.exists(real_exe):
            os.replace(real_exe, EXE_PATH)

    assert os.path.isfile(call_log), "The notebook did not execute the score_fasta binary"
    with open(call_log, "r") as f:
        calls = [line.strip() for line in f if line.strip()]
    input_realpath = os.path.realpath(INPUT_PATH)
    input_calls = [path for path in calls if path == input_realpath]
    assert len(input_calls) >= 20, (
        f"The notebook must execute score_fasta on input.fasta 20 times; observed {len(input_calls)} calls"
    )

    assert os.path.isfile(REPORT_PATH), f"File not found after notebook execution: {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("final_report.json is not valid JSON")

    assert "deterministic" in data, "Missing 'deterministic' key"
    assert data["deterministic"] is True, "'deterministic' should be true"
    assert "p_value" in data, "Missing 'p_value' key"
    assert isinstance(data["p_value"], float), "'p_value' should be a float"
    assert "mean_score" in data, "Missing 'mean_score' key"
    assert isinstance(data["mean_score"], float), "'mean_score' should be a float"
    assert set(data) == {"deterministic", "p_value", "mean_score"}, "Unexpected report structure"

    fresh_outputs = []
    fresh_values = []
    for _ in range(20):
        output, value = run_score(INPUT_PATH)
        fresh_outputs.append(output)
        fresh_values.append(value)
    assert len(set(fresh_outputs)) == 1, "Twenty verifier runs were not exactly deterministic"

    with open(BASELINE_PATH, "r") as f:
        baseline = [float(line.strip()) for line in f if line.strip()]
    assert len(baseline) == 50
    expected_p = float(stats.levene(baseline, fresh_values).pvalue)
    expected_mean = float(sum(fresh_values) / len(fresh_values))

    assert math.isfinite(data["p_value"])
    assert math.isclose(data["p_value"], expected_p, rel_tol=1e-10, abs_tol=1e-12), (
        f"Incorrect Levene p-value: got {data['p_value']}, expected {expected_p}"
    )
    assert math.isclose(data["mean_score"], expected_mean, rel_tol=0.0, abs_tol=1e-9), (
        f"Incorrect mean score: got {data['mean_score']}, expected {expected_mean}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
