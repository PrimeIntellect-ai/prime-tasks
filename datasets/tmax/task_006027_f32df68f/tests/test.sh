#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def compute_expected_power():
    fasta_path = '/home/user/input/genome.fasta'
    if not os.path.exists(fasta_path):
        return []

    with open(fasta_path, 'r') as f:
        lines = f.readlines()
    seq = ''.join([l.strip() for l in lines if not l.startswith('>')])

    mapping = {'A': 0, 'T': 0, 'C': 1, 'G': 1}
    num_seq = [mapping.get(b, 0) for b in seq]

    N = 1200
    num_chunks = len(num_seq) // N
    results = []

    sqrt3_2 = math.sqrt(3) / 2

    for i in range(num_chunks):
        chunk = num_seq[i*N:(i+1)*N]
        real_part = 0.0
        imag_part = 0.0
        for n, x in enumerate(chunk):
            if x == 0:
                continue
            mod = n % 3
            if mod == 0:
                real_part += x
            elif mod == 1:
                real_part -= 0.5 * x
                imag_part -= sqrt3_2 * x
            elif mod == 2:
                real_part -= 0.5 * x
                imag_part += sqrt3_2 * x

        power = real_part**2 + imag_part**2
        results.append((i, round(power, 2)))

    return results

def test_run_pipeline_script_exists():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Master shell script {script_path} is missing."

def test_spectral_plot_exists():
    plot_path = "/home/user/output/spectral_plot.png"
    assert os.path.isfile(plot_path), f"Plot file {plot_path} is missing."
    assert os.path.getsize(plot_path) > 0, f"Plot file {plot_path} is empty."

def test_spectral_analysis_csv():
    csv_path = "/home/user/output/spectral_analysis.csv"
    assert os.path.isfile(csv_path), f"CSV output file {csv_path} is missing."

    expected_results = compute_expected_power()
    assert len(expected_results) > 0, "Could not compute expected results (missing or empty fasta)."

    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"CSV file {csv_path} is empty.")

        assert header == ['chunk_id', 'period_3_power'], \
            f"CSV header is incorrect. Expected ['chunk_id', 'period_3_power'], got {header}"

        rows = list(reader)
        assert len(rows) == len(expected_results), \
            f"Expected {len(expected_results)} rows of data, got {len(rows)}."

        for row, (exp_id, exp_power) in zip(rows, expected_results):
            try:
                chunk_id = int(row[0])
                power = float(row[1])
            except ValueError:
                pytest.fail(f"Could not parse row {row} as (int, float).")

            assert chunk_id == exp_id, f"Expected chunk_id {exp_id}, got {chunk_id}."
            assert abs(power - exp_power) <= 0.1, \
                f"For chunk {chunk_id}, expected power ~{exp_power}, got {power}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
