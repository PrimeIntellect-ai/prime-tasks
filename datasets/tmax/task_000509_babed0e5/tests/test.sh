#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import math

def compute_truth():
    fasta_path = '/home/user/input.fasta'
    assert os.path.exists(fasta_path), f"Input file not found at {fasta_path}. Cannot compute truth."

    with open(fasta_path, 'r') as f:
        lines = f.readlines()
    seq = "".join(l.strip() for l in lines if not l.startswith(">"))

    bin_size = 500
    initial_bins = []
    for i in range(0, len(seq), bin_size):
        chunk = seq[i:i+bin_size]
        gc = (chunk.count('G') + chunk.count('C')) / len(chunk)
        initial_bins.append({'start': i, 'end': i+len(chunk), 'gc': gc})

    to_split = [False] * len(initial_bins)
    for i in range(len(initial_bins)):
        diff_left = abs(initial_bins[i]['gc'] - initial_bins[i-1]['gc']) if i > 0 else 0
        diff_right = abs(initial_bins[i]['gc'] - initial_bins[i+1]['gc']) if i < len(initial_bins)-1 else 0
        if diff_left > 0.15 or diff_right > 0.15:
            to_split[i] = True

    final_bins = []
    for i, b in enumerate(initial_bins):
        if to_split[i]:
            mid = b['start'] + 250
            chunk1 = seq[b['start']:mid]
            chunk2 = seq[mid:b['end']]
            final_bins.append({
                'midpoint': b['start'] + 125.0,
                'gc': (chunk1.count('G') + chunk1.count('C')) / len(chunk1) if len(chunk1) > 0 else 0
            })
            final_bins.append({
                'midpoint': mid + 125.0,
                'gc': (chunk2.count('G') + chunk2.count('C')) / len(chunk2) if len(chunk2) > 0 else 0
            })
        else:
            final_bins.append({
                'midpoint': b['start'] + 250.0,
                'gc': b['gc']
            })

    x = [b['midpoint'] for b in final_bins]
    y = [b['gc'] for b in final_bins]

    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_xy = sum(x[i]*y[i] for i in range(n))
    sum_xx = sum(x[i]**2 for i in range(n))

    m = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x**2)
    b_int = (sum_y - m * sum_x) / n

    return {
        "sequence_length": len(seq),
        "initial_bins": len(initial_bins),
        "refined_bins": len(final_bins),
        "slope": round(m, 6),
        "intercept": round(b_int, 6)
    }

def test_results_json():
    results_path = '/home/user/results.json'
    assert os.path.exists(results_path), f"Results file not found at {results_path}"

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, "results.json is not a valid JSON file."

    expected = compute_truth()

    # Check sequence length
    assert 'sequence_length' in results, "Missing 'sequence_length' in results.json"
    assert results['sequence_length'] == expected['sequence_length'], \
        f"Expected sequence_length {expected['sequence_length']}, got {results['sequence_length']}"

    # Check initial bins
    assert 'initial_bins' in results, "Missing 'initial_bins' in results.json"
    assert results['initial_bins'] == expected['initial_bins'], \
        f"Expected initial_bins {expected['initial_bins']}, got {results['initial_bins']}"

    # Check refined bins
    assert 'refined_bins' in results, "Missing 'refined_bins' in results.json"
    assert results['refined_bins'] == expected['refined_bins'], \
        f"Expected refined_bins {expected['refined_bins']}, got {results['refined_bins']}"

    # Check slope
    assert 'slope' in results, "Missing 'slope' in results.json"
    assert isinstance(results['slope'], (int, float)), "'slope' must be a number"
    assert math.isclose(results['slope'], expected['slope'], abs_tol=1e-5), \
        f"Expected slope {expected['slope']}, got {results['slope']}"

    # Check intercept
    assert 'intercept' in results, "Missing 'intercept' in results.json"
    assert isinstance(results['intercept'], (int, float)), "'intercept' must be a number"
    assert math.isclose(results['intercept'], expected['intercept'], abs_tol=1e-5), \
        f"Expected intercept {expected['intercept']}, got {results['intercept']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
