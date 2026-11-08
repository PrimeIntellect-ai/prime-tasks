#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math
import re

def test_c_source_exists():
    assert os.path.isfile("/home/user/analyze_seq.c"), "The C source file /home/user/analyze_seq.c is missing."

def test_output_file_exists():
    assert os.path.isfile("/home/user/analysis_output.txt"), "The output file /home/user/analysis_output.txt is missing."

def test_output_values():
    csv_path = "/home/user/sequences.csv"
    assert os.path.isfile(csv_path), "The sequences.csv file is missing."

    sequences = []
    with open(csv_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) == 3:
                sequences.append((parts[0], parts[1], parts[2]))

    def gc_prop(seq, i):
        window = seq[i:i+10]
        return (window.count('G') + window.count('C')) / 10.0

    integrals = {'WT': [], 'MUT': []}
    seq1_max_diff = -float('inf')
    seq1_max_idx = -1

    for seq_id, seq_type, seq in sequences:
        p = [gc_prop(seq, i) for i in range(91)]

        if seq_id == "SEQ1":
            for i in range(90):
                diff = p[i+1] - p[i]
                if diff > seq1_max_diff:
                    seq1_max_diff = diff
                    seq1_max_idx = i

        s = sum((p[i] + p[i+1]) / 2.0 for i in range(90))
        if seq_type in integrals:
            integrals[seq_type].append(s)

    def get_stats(vals):
        n = len(vals)
        mean = sum(vals) / n if n > 0 else 0
        var = sum((x - mean)**2 for x in vals) / (n - 1) if n > 1 else 0
        return n, mean, var

    n_wt, mu_wt, var_wt = get_stats(integrals['WT'])
    n_mut, mu_mut, var_mut = get_stats(integrals['MUT'])

    if n_wt > 0 and n_mut > 0:
        denom = math.sqrt(var_wt/n_wt + var_mut/n_mut)
        z_stat = (mu_wt - mu_mut) / denom if denom != 0 else float('inf')
    else:
        z_stat = 0.0

    expected = {
        "WT_MEAN_INTEGRAL": f"{mu_wt:.4f}",
        "MUT_MEAN_INTEGRAL": f"{mu_mut:.4f}",
        "Z_STATISTIC": f"{z_stat:.4f}",
        "SEQ1_MAX_DERIVATIVE_INDEX": str(seq1_max_idx)
    }

    with open("/home/user/analysis_output.txt", "r") as f:
        output_content = f.read()

    parsed = {}
    for line in output_content.splitlines():
        line = line.strip()
        if not line:
            continue
        if ":" in line:
            key, val = line.split(":", 1)
            parsed[key.strip()] = val.strip()

    for key, exp_val in expected.items():
        assert key in parsed, f"Missing key '{key}' in analysis_output.txt"

        if key == "SEQ1_MAX_DERIVATIVE_INDEX":
            assert parsed[key] == exp_val, f"Expected {key} to be {exp_val}, but got {parsed[key]}"
        else:
            try:
                parsed_val = float(parsed[key])
                exp_float = float(exp_val)
                assert math.isclose(parsed_val, exp_float, abs_tol=1e-3), \
                    f"Expected {key} to be close to {exp_val}, but got {parsed[key]}"
            except ValueError:
                assert False, f"Could not parse float from {key}: {parsed[key]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
