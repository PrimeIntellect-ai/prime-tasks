#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

import numpy as np
import pytest

RESULT = "/home/user/result.txt"
OUTPUT = "/home/user/output.txt"
SOURCE = "/home/user/simulator.c"
EVALUATE = "/home/user/evaluate.py"
REFERENCE = "/home/user/ref_data.txt"
CANONICAL_REFERENCE = np.array([
    0.812678, 0.835439, 0.755928, 0.684033, 0.618933,
    0.560032, 0.506740, 0.458525, 0.414902, 0.375422,
], dtype=float)


def read_result():
    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert content, f"{RESULT} is empty."
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Content of {RESULT} is not a valid float: '{content}'")
    return content, value


def test_result_file_exists():
    assert os.path.isfile(RESULT), f"Expected file {RESULT} does not exist."


def test_result_file_content():
    assert os.path.isfile(RESULT), f"Expected file {RESULT} does not exist."
    _, kl_value = read_result()
    assert kl_value < 0.01, (
        f"KL divergence value in {RESULT} is {kl_value}, which is not less than 0.01. "
        "The C code bug might not be correctly fixed."
    )


def test_output_file_exists():
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist. Did you run the compiled C program?"
    with open(OUTPUT, "r") as f:
        lines = f.read().strip().split('\n')
    assert len(lines) > 0, f"{OUTPUT} is empty."
    try:
        float(lines[0])
    except ValueError:
        pytest.fail(f"First line of {OUTPUT} is not a valid number: '{lines[0]}'")


def test_freshly_compiled_solver_and_evaluation():
    assert os.path.isfile(SOURCE), f"Expected C source {SOURCE} does not exist."
    assert os.path.isfile(EVALUATE), f"Expected evaluator {EVALUATE} does not exist."
    assert os.path.isfile(REFERENCE), f"Expected reference data {REFERENCE} does not exist."

    # Preserve the agent's submitted result, then regenerate output from its C source.
    _, reported_kl = read_result()
    assert math.isfinite(reported_kl), "The reported KL divergence must be finite."

    try:
        ref = np.loadtxt(REFERENCE, dtype=float)
    except Exception as exc:
        pytest.fail(f"Could not read {REFERENCE}: {exc}")
    assert ref.shape == CANONICAL_REFERENCE.shape and np.array_equal(ref, CANONICAL_REFERENCE), (
        "The provided reference dataset was modified."
    )

    binary = "/tmp/submitted_simulator"
    compile_run = subprocess.run(
        ["gcc", SOURCE, "-O2", "-o", binary, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_run.returncode == 0, f"simulator.c did not compile:\n{compile_run.stderr}"

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    execute_run = subprocess.run(
        [binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert execute_run.returncode == 0, (
        f"Freshly compiled simulator failed with exit code {execute_run.returncode}:\n"
        f"{execute_run.stderr}"
    )
    assert os.path.isfile(OUTPUT), "The freshly compiled simulator did not create output.txt."

    try:
        simulated = np.loadtxt(OUTPUT, dtype=float)
    except Exception as exc:
        pytest.fail(f"Could not parse freshly generated output.txt: {exc}")
    assert simulated.shape == CANONICAL_REFERENCE.shape, (
        f"Expected 10 simulated values, got shape {simulated.shape}."
    )
    assert np.all(np.isfinite(simulated)), "Fresh simulator output contains NaN or infinity."

    # Actually run the required evaluator on the freshly generated artifact.
    eval_run = subprocess.run(
        ["python3", EVALUATE, OUTPUT, REFERENCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert eval_run.returncode == 0, f"evaluate.py failed:\n{eval_run.stderr}"
    tokens = eval_run.stdout.strip().split()
    assert len(tokens) == 1, f"evaluate.py must output one numeric value, got: {eval_run.stdout!r}"
    try:
        evaluated_kl = float(tokens[0])
    except ValueError:
        pytest.fail(f"evaluate.py output is not numeric: {eval_run.stdout!r}")
    assert math.isfinite(evaluated_kl), "evaluate.py returned a non-finite KL divergence."

    # Independently derive the KL value rather than trusting either result.txt or evaluate.py.
    p = simulated + 1e-10
    q = CANONICAL_REFERENCE + 1e-10
    p = p / p.sum()
    q = q / q.sum()
    independent_kl = float(np.sum(np.where(p != 0, p * np.log(p / q), 0)))
    rounded_independent = float(f"{independent_kl:.6e}")

    assert math.isclose(evaluated_kl, rounded_independent, rel_tol=1e-12, abs_tol=1e-15), (
        f"evaluate.py reported {evaluated_kl}, but the independently computed value is "
        f"{rounded_independent}."
    )
    assert math.isclose(reported_kl, evaluated_kl, rel_tol=1e-12, abs_tol=1e-15), (
        f"result.txt contains {reported_kl}, but evaluate.py reports {evaluated_kl} for the "
        "freshly generated output."
    )
    assert independent_kl < 0.01, (
        f"The freshly generated output has KL divergence {independent_kl}, not less than 0.01."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
