#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import cmath
import math
import os
import re
import secrets
import subprocess
import tempfile
import pytest

DNADIR = "/home/user/dnastat"
ANALYZER = os.path.join(DNADIR, "analyzer.go")
RUN_SCRIPT = os.path.join(DNADIR, "run_analysis.sh")
RESULTS = os.path.join(DNADIR, "results.log")
DATA1 = "/home/user/data/seq1.txt"
DATA2 = "/home/user/data/seq2.txt"
ENCODING = {"A": 1.0, "C": -1.0, "G": 2.0, "T": -2.0}


def analyze_reference(sequence):
    values = [ENCODING[c] for c in sequence]
    n = 1
    while n < len(values):
        n *= 2
    values += [0.0] * (n - len(values))

    powers = []
    for k in range(1, n):
        value = sum(values[j] * cmath.exp(-2j * math.pi * j * k / n) for j in range(n))
        powers.append(value.real * value.real + value.imag * value.imag)

    mean = sum(powers) / len(powers)
    stddev = math.sqrt(sum((p - mean) ** 2 for p in powers) / len(powers))
    z_score = (max(powers) - mean) / stddev
    return z_score, "Periodic" if z_score >= 3.0 else "Random"


def expected_line(filename, sequence):
    z_score, hypothesis = analyze_reference(sequence)
    return f"File: {filename}, Z: {z_score:.2f}, Hypothesis: {hypothesis}"


def safe_sequence(length, periodic=False):
    alphabet = "ACGT"
    for _ in range(2000):
        if periodic:
            motif_len = 2 + secrets.randbelow(min(5, length - 1))
            motif = "".join(secrets.choice(alphabet) for _ in range(motif_len))
            sequence = (motif * ((length + motif_len - 1) // motif_len))[:length]
        else:
            sequence = "".join(secrets.choice(alphabet) for _ in range(length))
        try:
            z_score, _ = analyze_reference(sequence)
        except (ValueError, ZeroDivisionError):
            continue
        fraction = z_score * 100.0 - math.floor(z_score * 100.0)
        if math.isfinite(z_score) and abs(z_score - 3.0) > 0.01 and abs(fraction - 0.5) > 0.05:
            return sequence
    pytest.fail("Could not generate a numerically stable hidden DNA test case")


def run_analysis_script():
    return subprocess.run(
        ["bash", RUN_SCRIPT],
        cwd=DNADIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )


def test_execute_script_and_analyzer_on_derived_inputs():
    assert os.path.isdir(DNADIR), "Directory /home/user/dnastat does not exist."
    assert os.path.isfile(ANALYZER), "File /home/user/dnastat/analyzer.go does not exist."
    assert os.path.isfile(RUN_SCRIPT), "File /home/user/dnastat/run_analysis.sh does not exist."

    original1 = open(DATA1, "rb").read()
    original2 = open(DATA2, "rb").read()
    script_seq1 = safe_sequence(11, False)
    script_seq2 = safe_sequence(29, True)
    dynamic_log = None
    dynamic_run = None

    try:
        with open(DATA1, "w") as f:
            f.write(script_seq1)
        with open(DATA2, "w") as f:
            f.write(script_seq2)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        dynamic_run = run_analysis_script()
        if os.path.isfile(RESULTS):
            with open(RESULTS, "r") as f:
                dynamic_log = f.read()
    finally:
        with open(DATA1, "wb") as f:
            f.write(original1)
        with open(DATA2, "wb") as f:
            f.write(original2)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        final_run = run_analysis_script()

    assert dynamic_run is not None and dynamic_run.returncode == 0, (
        "run_analysis.sh failed on hidden inputs: "
        + (dynamic_run.stderr if dynamic_run is not None else "not executed")
    )
    expected_dynamic = (
        expected_line("seq1.txt", script_seq1) + "\n"
        + expected_line("seq2.txt", script_seq2) + "\n"
    )
    assert dynamic_log == expected_dynamic, (
        "run_analysis.sh did not run the analyzer correctly on both input files. "
        f"Expected {expected_dynamic!r}, got {dynamic_log!r}"
    )
    assert final_run.returncode == 0, f"run_analysis.sh failed on the supplied inputs: {final_run.stderr}"

    binary = os.path.join(tempfile.gettempdir(), "dnastat-analyzer-" + secrets.token_hex(8))
    build = subprocess.run(
        ["go", "build", "-o", binary, ANALYZER],
        cwd=DNADIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert build.returncode == 0, f"analyzer.go does not build: {build.stderr}"

    try:
        for index, length in enumerate([5, 9, 10, 15, 17, 26, 33, 48]):
            sequence = safe_sequence(length, periodic=(index % 2 == 1))
            token = secrets.token_hex(6)
            input_path = os.path.join(tempfile.gettempdir(), f"dnastat_case_{token}_{index}.txt")
            with open(input_path, "w") as f:
                f.write(sequence)
            try:
                result = subprocess.run(
                    [binary, input_path],
                    cwd=DNADIR,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=20,
                )
                assert result.returncode == 0, f"Analyzer failed for a hidden input: {result.stderr}"
                expected = expected_line(os.path.basename(input_path), sequence) + "\n"
                assert result.stdout == expected, (
                    f"Incorrect analyzer output for hidden DNA input of length {length}. "
                    f"Expected {expected!r}, got {result.stdout!r}"
                )
            finally:
                if os.path.exists(input_path):
                    os.remove(input_path)
    finally:
        if os.path.exists(binary):
            os.remove(binary)


def test_dnastat_directory_exists():
    assert os.path.isdir("/home/user/dnastat"), "Directory /home/user/dnastat does not exist."


def test_analyzer_go_exists():
    assert os.path.isfile("/home/user/dnastat/analyzer.go"), "File /home/user/dnastat/analyzer.go does not exist."


def test_run_analysis_sh_exists():
    assert os.path.isfile("/home/user/dnastat/run_analysis.sh"), "File /home/user/dnastat/run_analysis.sh does not exist."


def test_results_log_exists():
    assert os.path.isfile("/home/user/dnastat/results.log"), "File /home/user/dnastat/results.log does not exist. Did you run the bash script?"


def test_results_log_content():
    log_path = "/home/user/dnastat/results.log"
    if not os.path.isfile(log_path):
        pytest.fail(f"File {log_path} not found.")

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines of output in results.log, found {len(lines)}."

    seq1_match = re.search(r"File:\s*seq1\.txt,\s*Z:\s*([0-9.]+),\s*Hypothesis:\s*Random", lines[0])
    assert seq1_match is not None, f"Line 1 does not match expected format for seq1.txt. Got: {lines[0]}"
    z1 = float(seq1_match.group(1))
    assert 1.5 < z1 < 1.7, f"Z-score for seq1.txt is out of expected range (expected ~1.63). Got: {z1}"

    seq2_match = re.search(r"File:\s*seq2\.txt,\s*Z:\s*([0-9.]+),\s*Hypothesis:\s*Periodic", lines[1])
    assert seq2_match is not None, f"Line 2 does not match expected format for seq2.txt. Got: {lines[1]}"
    z2 = float(seq2_match.group(1))
    assert 3.2 < z2 < 3.4, f"Z-score for seq2.txt is out of expected range (expected ~3.33). Got: {z2}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
