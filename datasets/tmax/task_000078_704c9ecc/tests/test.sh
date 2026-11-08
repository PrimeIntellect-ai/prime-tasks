#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import secrets
import subprocess
from math import comb

VENV_PYTHON = "/home/user/sim_env/bin/python"
SCRIPT = "/home/user/analyze_primers.py"
RESULTS = "/home/user/pcr_results.json"
REFERENCE = "/home/user/reference.fasta"
MUTANTS = "/home/user/mutants.fasta"


def run_analysis():
    if os.path.exists(RESULTS):
        os.unlink(RESULTS)
    proc = subprocess.run(
        [VENV_PYTHON, SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, (
        f"Analysis script failed with exit code {proc.returncode}.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.isfile(RESULTS), f"Results file not found at {RESULTS}."
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {RESULTS} does not contain valid JSON: {exc}")


def fisher_two_sided(a, b, c, d):
    """Independently calculate the ordinary two-sided Fisher exact p-value."""
    row1 = a + b
    row2 = c + d
    col1 = a + c
    col2 = b + d
    total = row1 + row2
    denominator = comb(total, row1)
    observed_numerator = comb(col1, a) * comb(col2, row1 - a)
    low = max(0, row1 - col2)
    high = min(row1, col1)
    included = 0
    for x in range(low, high + 1):
        numerator = comb(col1, x) * comb(col2, row1 - x)
        if numerator <= observed_numerator:
            included += numerator
    return included / denominator


def validate_result_shape(results):
    expected_keys = {
        "reference_amplified",
        "reference_total",
        "mutants_amplified",
        "mutants_total",
        "p_value",
    }
    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f"Missing keys in JSON output: {missing_keys}"
    assert set(results.keys()) == expected_keys, "Results JSON contains unexpected keys."
    for key in expected_keys - {"p_value"}:
        assert type(results[key]) is int, f"Expected {key} to be an int."
    assert isinstance(results["p_value"], float), (
        f"Expected p_value to be a float, got {type(results['p_value'])}."
    )


def write_fasta(path, amplified_count, total_count, rng):
    records = []
    negatives = [
        "C" * 13 + "ATGCGT" + "C" * 9 + "TGCGTA" + "C" * 19,
        "C" * 11 + "ATGCGT" + "C" * 101 + "TGCGTA" + "C" * 17,
        "C" * 7 + "TGCGTA" + "C" * 40 + "ATGCGT" + "C" * 23,
        "C" * 130,
    ]
    for i in range(amplified_count):
        gap = rng.randint(10, 100)
        records.append("C" * rng.randint(5, 25) + "ATGCGT" + "C" * gap + "TGCGTA" + "C" * rng.randint(5, 25))
    for i in range(total_count - amplified_count):
        records.append(negatives[i % len(negatives)])
    rng.shuffle(records)

    with open(path, "w") as f:
        for i, sequence in enumerate(records):
            f.write(f">challenge_{i}\n")
            width = rng.randint(13, 31)
            for start in range(0, len(sequence), width):
                f.write(sequence[start:start + width] + "\n")


def test_virtual_environment_exists():
    """Verify that the Python virtual environment and SciPy installation exist."""
    assert os.path.isfile(VENV_PYTHON), (
        f"Virtual environment python executable not found at {VENV_PYTHON}. "
        "Did you create the virtual environment?"
    )
    proc = subprocess.run(
        [VENV_PYTHON, "-c", "from scipy.stats import fisher_exact; print(fisher_exact([[1,2],[3,4]]).pvalue)"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, f"SciPy is not usable in the virtual environment: {proc.stderr}"


def test_analysis_script_exists():
    assert os.path.isfile(SCRIPT), f"Analysis script not found at {SCRIPT}."


def test_pcr_results_json():
    """Execute the submitted script and verify its result on the supplied FASTA files."""
    results = run_analysis()
    validate_result_shape(results)

    assert results["reference_amplified"] == 10, f"Expected reference_amplified to be 10, got {results['reference_amplified']}."
    assert results["reference_total"] == 100, f"Expected reference_total to be 100, got {results['reference_total']}."
    assert results["mutants_amplified"] == 60, f"Expected mutants_amplified to be 60, got {results['mutants_amplified']}."
    assert results["mutants_total"] == 100, f"Expected mutants_total to be 100, got {results['mutants_total']}."

    expected_p_value = 5.556284345244583e-13
    actual_p_value = results["p_value"]
    assert isinstance(actual_p_value, float), f"Expected p_value to be a float, got {type(actual_p_value)}."
    assert math.isclose(actual_p_value, expected_p_value, rel_tol=1e-5, abs_tol=1e-15), \
        f"Expected p_value to be close to {expected_p_value}, got {actual_p_value}."


def test_script_processes_fasta_and_computes_fisher_exact():
    """Exercise the script on unpredictable multiline FASTA datasets."""
    with open(REFERENCE, "rb") as f:
        original_reference = f.read()
    with open(MUTANTS, "rb") as f:
        original_mutants = f.read()

    rng = random.Random(secrets.randbits(128))
    try:
        for _ in range(3):
            reference_total = rng.randint(8, 18)
            mutants_total = rng.randint(8, 18)
            reference_amplified = rng.randint(1, reference_total - 1)
            mutants_amplified = rng.randint(1, mutants_total - 1)

            write_fasta(REFERENCE, reference_amplified, reference_total, rng)
            write_fasta(MUTANTS, mutants_amplified, mutants_total, rng)
            results = run_analysis()
            validate_result_shape(results)

            assert results["reference_amplified"] == reference_amplified
            assert results["reference_total"] == reference_total
            assert results["mutants_amplified"] == mutants_amplified
            assert results["mutants_total"] == mutants_total

            expected_p = fisher_two_sided(
                reference_amplified,
                reference_total - reference_amplified,
                mutants_amplified,
                mutants_total - mutants_amplified,
            )
            assert math.isclose(results["p_value"], expected_p, rel_tol=1e-12, abs_tol=1e-15), (
                f"Incorrect Fisher exact p-value: expected {expected_p}, got {results['p_value']}"
            )
    finally:
        with open(REFERENCE, "wb") as f:
            f.write(original_reference)
        with open(MUTANTS, "wb") as f:
            f.write(original_mutants)
        subprocess.run(
            [VENV_PYTHON, SCRIPT],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
            check=False,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
