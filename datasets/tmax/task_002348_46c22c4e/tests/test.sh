#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess
import pytest

RESULT = "/home/user/result.txt"
FASTA = "/home/user/sequences.fasta"
DETREND = "/app/bio-spectral-v1.0/detrend.awk"
RUNNER = "/app/bio-spectral-v1.0/run_spectral.sh"


def parse_fasta(path):
    records = []
    ident = None
    parts = []
    with open(path, "r") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith(">"):
                if ident is not None:
                    records.append((ident, "".join(parts)))
                ident = line[1:].split()[0]
                parts = []
            else:
                assert ident is not None, "Sequence data appeared before a FASTA header"
                parts.append(line)
    if ident is not None:
        records.append((ident, "".join(parts)))
    return records


def expected_score(sequence):
    values = [1.0 if c == "A" else 2.0 if c == "C" else 3.0 if c == "G" else 4.0 for c in sequence]
    n = len(values)
    mean = sum(values) / n
    variance = sum(v * v for v in values) / n - mean * mean
    normalized = [(v - mean) / math.sqrt(variance + 1e-6) for v in values]
    return sum((normalized[i] - normalized[i - 1]) ** 2 for i in range(1, n))


def run_score(sequence):
    proc = subprocess.run(
        [RUNNER, sequence], text=True, capture_output=True, timeout=10
    )
    assert proc.returncode == 0, f"run_spectral.sh failed for {sequence!r}: {proc.stderr}"
    output = proc.stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", output), \
        f"run_spectral.sh did not emit one floating-point number: {output!r}"
    value = float(output)
    assert math.isfinite(value), "run_spectral.sh emitted a non-finite score"
    return value


def assert_close(actual, expected, label):
    tolerance = max(1e-5, abs(expected) * 2e-5)
    assert abs(actual - expected) <= tolerance, \
        f"{label}: expected {expected}, got {actual}"


def test_result_file_exists():
    assert os.path.isfile(RESULT), f"Result file {RESULT} does not exist."


def test_result_content_and_metric():
    with open(RESULT, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    top_id_match = re.search(r"Top_ID:\s*(\S+)", content)
    assert top_id_match is not None, "Could not find 'Top_ID: <Sequence_ID>' in result.txt"
    top_id = top_id_match.group(1)
    assert top_id == "seq4", f"Expected Top_ID to be 'seq4', but got '{top_id}'"

    top_score_match = re.search(r"Top_Score:\s*([0-9.]+)", content)
    assert top_score_match is not None, "Could not find 'Top_Score: <Score>' in result.txt"
    try:
        top_score = float(top_score_match.group(1))
    except ValueError:
        pytest.fail(f"Top_Score is not a valid float: {top_score_match.group(1)}")

    p_value_match = re.search(r"P-value:\s*([0-9.]+)", content)
    assert p_value_match is not None, "Could not find 'P-value: <p_value>' in result.txt"
    try:
        p_value = float(p_value_match.group(1))
    except ValueError:
        pytest.fail(f"P-value is not a valid float: {p_value_match.group(1)}")

    ref_p_value = 0.02
    abs_diff = abs(p_value - ref_p_value)
    assert abs_diff <= 0.05, f"P-value metric failed: agent p-value {p_value} is not within 0.05 of reference {ref_p_value} (difference: {abs_diff})"

    # Enforce the requested exact three-line output and a p-value attainable from 100 trials.
    strict = re.fullmatch(
        r"Top_ID: (\S+)\nTop_Score: ([0-9]+(?:\.[0-9]+)?)\nP-value: ([0-9]+(?:\.[0-9]+)?)\n?",
        content,
    )
    assert strict is not None, "result.txt must contain exactly the three requested lines"
    assert strict.group(1) == top_id
    assert math.isfinite(top_score)
    assert math.isfinite(p_value) and 0.0 <= p_value <= 1.0
    assert abs(p_value * 100 - round(p_value * 100)) <= 1e-9, \
        "An empirical p-value from 100 permutations must be a multiple of 0.01"

    # Independently derive every expected score, execute the repaired toolkit, and
    # verify that the reported score is the actual maximum rather than a placeholder.
    records = parse_fasta(FASTA)
    assert records, "No FASTA records found"
    independently_scored = []
    for ident, sequence in records:
        expected = expected_score(sequence)
        observed = run_score(sequence)
        assert_close(observed, expected, f"Toolkit score for {ident}")
        independently_scored.append((expected, ident, sequence, observed))

    expected, expected_id, expected_sequence, observed = max(independently_scored, key=lambda item: item[0])
    assert expected_id == "seq4", f"Expected Top_ID to be 'seq4', but derived {expected_id!r}"
    assert top_id == expected_id
    assert_close(top_score, expected, "Reported Top_Score")
    assert_close(top_score, observed, "Reported score versus toolkit output")


def test_detrend_awk_fixed():
    assert os.path.isfile(DETREND), f"File {DETREND} does not exist."
    with open(DETREND, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    assert "1e-6" in content or "0.000001" in content or "1e-5" in content or "0.00001" in content, \
        "Could not find a small epsilon (e.g., 1e-6) added to the variance in detrend.awk"

    # Exercise detrend.awk directly so an epsilon in a comment cannot pass.
    samples = [1.0, 2.0, 4.0, 8.0]
    proc = subprocess.run(
        ["awk", "-f", DETREND],
        input="".join(f"{v}\n" for v in samples),
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"detrend.awk failed: {proc.stderr}"
    outputs = proc.stdout.split()
    assert len(outputs) == len(samples), "detrend.awk emitted the wrong number of values"
    actual = [float(v) for v in outputs]
    assert all(math.isfinite(v) for v in actual), "detrend.awk emitted a non-finite value"
    mean = sum(samples) / len(samples)
    variance = sum(v * v for v in samples) / len(samples) - mean * mean
    expected = [(v - mean) / math.sqrt(variance + 1e-6) for v in samples]
    for i, (got, want) in enumerate(zip(actual, expected), 1):
        assert_close(got, want, f"Detrended value {i}")

    # Uniform input is the original crash case and must execute successfully.
    uniform = subprocess.run(
        ["awk", "-f", DETREND],
        input="3\n3\n3\n3\n",
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert uniform.returncode == 0, f"detrend.awk still crashes on uniform input: {uniform.stderr}"
    uniform_values = [float(v) for v in uniform.stdout.split()]
    assert len(uniform_values) == 4
    assert all(math.isfinite(v) and abs(v) <= 1e-12 for v in uniform_values), \
        "Uniform input should produce finite zero residuals"

    assert os.path.isfile(RUNNER), f"File {RUNNER} does not exist"
    assert os.stat(RUNNER).st_mode & stat.S_IXUSR, "run_spectral.sh is not executable"
    assert_close(run_score("AAAAAAAA"), 0.0, "Uniform-sequence spectral score")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
