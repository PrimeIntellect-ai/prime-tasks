#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import time

import numpy as np

BASE_DIR = "/home/user/bio_profiling"


def read_fasta(filepath):
    sequences = {}
    name = None
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                name = line[1:]
                sequences[name] = ""
            elif name is not None:
                sequences[name] += line
    return sequences


def expected_tm(gc):
    dH = -35000 - (gc * 10000)
    dS = -100 - (gc * 10)
    R = 1.987
    C = 1e-6

    def f(temp):
        return dH - temp * dS + R * temp * math.log(C)

    low, high = 200.0, 400.0
    for _ in range(200):
        mid = (low + high) / 2.0
        val = f(mid)
        if abs(val) < 1e-7:
            return mid
        if f(low) * val < 0:
            high = mid
        else:
            low = mid
    return (low + high) / 2.0


def expected_efficiency(tm):
    steps = 2000000
    a, b = 250.0, 350.0
    dx = (b - a) / steps
    total = 0.0
    chunk_size = 200000
    for start in range(0, steps, chunk_size):
        stop = min(start + chunk_size, steps)
        x = a + np.arange(start, stop, dtype=np.float64) * dx
        total += float(np.exp(-((x - tm) ** 2) / 50.0).sum()) * dx
    return total


def derive_expected_results():
    sequences = read_fasta(os.path.join(BASE_DIR, "sequences.fasta"))
    results = {}
    efficiency_cache = {}
    for name, sequence in sequences.items():
        gc = sum(1 for char in sequence if char in "GC") / len(sequence)
        tm = expected_tm(gc)
        if tm not in efficiency_cache:
            efficiency_cache[tm] = expected_efficiency(tm)
        results[name] = {"tm": tm, "efficiency": efficiency_cache[tm]}
    return results


def test_profile_notes_exists_and_correct():
    notes_path = os.path.join(BASE_DIR, "profile_notes.txt")
    assert os.path.isfile(notes_path), f"File missing: {notes_path}"

    with open(notes_path, "r") as f:
        first_line = f.readline().strip()

    assert first_line == "integrate_efficiency_slow", \
        f"The first line of profile_notes.txt must be the exact name of the slowest function. Found: '{first_line}'"


def test_optimized_script_execution_time_and_success():
    script_path = os.path.join(BASE_DIR, "optimized_primer_sim.py")
    assert os.path.isfile(script_path), f"Optimized script missing: {script_path}"

    start_time = time.time()
    proc = subprocess.run(
        ["python3", script_path],
        capture_output=True,
        text=True
    )
    elapsed = time.time() - start_time

    assert proc.returncode == 0, f"Optimized script failed with exit code {proc.returncode}.\nStderr: {proc.stderr}"
    assert elapsed < 2.0, f"Optimized script took {elapsed:.2f} seconds, which is strictly >= 2.0 seconds limit."


def test_results_json_accuracy():
    results_path = os.path.join(BASE_DIR, "results.json")
    assert os.path.isfile(results_path), f"Results file missing: {results_path}"

    expected = derive_expected_results()
    with open(results_path, "r") as f:
        actual = json.load(f)

    for key in expected:
        assert key in actual, f"Sequence key '{key}' missing in results.json"

        for metric in ["tm", "efficiency"]:
            assert metric in actual[key], f"Metric '{metric}' missing for sequence '{key}'"
            exp_val = expected[key][metric]
            act_val = actual[key][metric]
            rel_diff = abs(exp_val - act_val) / max(1e-9, abs(exp_val))
            assert rel_diff <= 1e-4, \
                f"Value mismatch for {key} {metric}: expected {exp_val}, got {act_val} (rel diff: {rel_diff:.2e} > 1e-4)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
