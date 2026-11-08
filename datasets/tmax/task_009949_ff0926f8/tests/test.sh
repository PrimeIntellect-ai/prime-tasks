#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import tempfile
import uuid

import pytest
from scipy import stats

PROJECT = "/home/user/sequence_project"
EXE = PROJECT + "/bin/analyze_seqs"
FASTA_A = PROJECT + "/data/cohort_A.fasta"
FASTA_B = PROJECT + "/data/cohort_B.fasta"
CSV_A = PROJECT + "/data/cohort_A_results.csv"
CSV_B = PROJECT + "/data/cohort_B_results.csv"
JSON_PATH = PROJECT + "/results.json"


def get_nucleotide_value(c):
    if c == 'A': return 10.0
    if c == 'C': return 20.0
    if c == 'G': return 30.0
    if c == 'T': return 40.0
    return 0.0


def calculate_population_variance(seq):
    vals = [get_nucleotide_value(c) for c in seq if c in 'ACGT']
    if not vals:
        return 0.0
    mean = sum(vals) / len(vals)
    return sum((x - mean) ** 2 for x in vals) / len(vals)


def parse_fasta(filepath):
    seqs = {}
    with open(filepath, 'r') as f:
        seq_id = None
        seq_data = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('>'):
                if seq_id is not None:
                    seqs[seq_id] = ''.join(seq_data)
                seq_id = line[1:]
                seq_data = []
            else:
                seq_data.append(line)
        if seq_id is not None:
            seqs[seq_id] = ''.join(seq_data)
    return seqs


def parse_csv_text(text, expected_ids, source):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert len(lines) == len(expected_ids), \
        f"Expected {len(expected_ids)} lines in {source}, found {len(lines)}"

    values = {}
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid CSV format in {source}: {line}"
        seq_id, var_str = parts
        assert seq_id in expected_ids, f"Unknown sequence ID in {source}: {seq_id}"
        assert seq_id not in values, f"Duplicate sequence ID in {source}: {seq_id}"
        try:
            value = float(var_str)
        except ValueError:
            pytest.fail(f"Invalid variance in {source}: {var_str}")
        assert math.isfinite(value), f"Non-finite variance in {source}: {var_str}"
        values[seq_id] = value

    assert set(values) == set(expected_ids), \
        f"Sequence IDs in {source} do not exactly match the FASTA records"
    return values


def parse_csv_file(path, seqs):
    with open(path, 'r') as f:
        return parse_csv_text(f.read(), seqs, path)


def run_analyzer(fasta_path, seqs):
    try:
        proc = subprocess.run(
            [EXE, fasta_path], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=20, check=False
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Could not execute analyzer on {fasta_path}: {exc}")
    assert proc.returncode == 0, \
        f"Analyzer failed on {fasta_path} with code {proc.returncode}: {proc.stderr}"
    return parse_csv_text(proc.stdout, seqs, f"analyzer output for {fasta_path}")


def welch_t_test(var_a, var_b):
    n1 = len(var_a)
    n2 = len(var_b)
    m1 = sum(var_a) / n1
    m2 = sum(var_b) / n2
    v1 = sum((x - m1) ** 2 for x in var_a) / (n1 - 1)
    v2 = sum((x - m2) ** 2 for x in var_b) / (n2 - 1)
    return (m1 - m2) / math.sqrt(v1 / n1 + v2 / n2)


def assert_correct_values(values, seqs, source):
    for seq_id, seq in seqs.items():
        expected = calculate_population_variance(seq)
        actual = values[seq_id]
        assert math.isclose(actual, expected, rel_tol=1e-4, abs_tol=1e-4), \
            f"Variance mismatch for {seq_id} in {source}: expected {expected}, got {actual}. Numerical instability might not be fixed."


def test_executable_exists():
    assert os.path.isfile(EXE), f"Compiled executable missing at {EXE}"
    assert os.access(EXE, os.X_OK), f"File at {EXE} is not executable"
    with open(EXE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{EXE} is not a compiled ELF executable"


def test_executable_runs_and_calculates_stable_variances():
    rng = random.SystemRandom()
    token = uuid.uuid4().hex
    records = {
        f"balanced_{token}": "ACGT" * 2048,
        f"constant_{token}": "A" * 8191,
        f"two_value_{token}": ("A" * 3071) + ("T" * 5021),
    }
    alphabet = "ACGT"
    for i in range(5):
        records[f"random_{i}_{token}"] = ''.join(rng.choice(alphabet) for _ in range(5000 + i * 137))

    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "challenge.fasta")
        with open(path, 'w') as f:
            for seq_id, seq in records.items():
                f.write(f">{seq_id}\n")
                for start in range(0, len(seq), 73):
                    f.write(seq[start:start + 73] + "\n")
        output = run_analyzer(path, records)

    assert_correct_values(output, records, "challenge analyzer output")


def test_csv_outputs_exist_and_correct():
    assert os.path.isfile(CSV_A), f"Missing CSV output: {CSV_A}"
    assert os.path.isfile(CSV_B), f"Missing CSV output: {CSV_B}"

    seqs_a = parse_fasta(FASTA_A)
    seqs_b = parse_fasta(FASTA_B)
    saved_a = parse_csv_file(CSV_A, seqs_a)
    saved_b = parse_csv_file(CSV_B, seqs_b)

    assert_correct_values(saved_a, seqs_a, CSV_A)
    assert_correct_values(saved_b, seqs_b, CSV_B)

    actual_a = run_analyzer(FASTA_A, seqs_a)
    actual_b = run_analyzer(FASTA_B, seqs_b)
    assert_correct_values(actual_a, seqs_a, "analyzer output for cohort A")
    assert_correct_values(actual_b, seqs_b, "analyzer output for cohort B")

    for saved, actual, path in ((saved_a, actual_a, CSV_A), (saved_b, actual_b, CSV_B)):
        for seq_id in saved:
            assert math.isclose(saved[seq_id], actual[seq_id], rel_tol=0.0, abs_tol=1e-12), \
                f"Saved result in {path} does not match the compiled analyzer for {seq_id}"


def test_json_output_exists_and_correct():
    assert os.path.isfile(JSON_PATH), f"Missing JSON output: {JSON_PATH}"
    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON format in {JSON_PATH}")

    assert isinstance(data, dict), "JSON result must be an object"
    assert "t_statistic" in data, "Missing 't_statistic' in JSON"
    assert "p_value" in data, "Missing 'p_value' in JSON"
    assert set(data) == {"t_statistic", "p_value"}, \
        "JSON must contain exactly 't_statistic' and 'p_value'"

    seqs_a = parse_fasta(FASTA_A)
    seqs_b = parse_fasta(FASTA_B)
    var_a = [calculate_population_variance(seq) for seq in seqs_a.values()]
    var_b = [calculate_population_variance(seq) for seq in seqs_b.values()]

    expected_t_stat = welch_t_test(var_a, var_b)
    expected_p_value = float(stats.ttest_ind(var_a, var_b, equal_var=False).pvalue)

    try:
        actual_t_stat = float(data["t_statistic"])
        actual_p_value = float(data["p_value"])
    except (TypeError, ValueError):
        pytest.fail("t_statistic and p_value must be numeric")

    assert math.isfinite(actual_t_stat), "t_statistic must be finite"
    assert math.isfinite(actual_p_value), "p_value must be finite"
    assert math.isclose(actual_t_stat, expected_t_stat, rel_tol=1e-3, abs_tol=1e-3) or \
           math.isclose(actual_t_stat, -expected_t_stat, rel_tol=1e-3, abs_tol=1e-3), \
        f"t_statistic mismatch: expected {expected_t_stat}, got {actual_t_stat}"
    assert 0.0 <= actual_p_value <= 1.0, f"p_value out of valid range: {actual_p_value}"
    assert math.isclose(actual_p_value, expected_p_value, rel_tol=1e-3, abs_tol=1e-300), \
        f"p_value mismatch: expected {expected_p_value}, got {actual_p_value}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
