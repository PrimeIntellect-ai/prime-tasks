#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import subprocess
import time

import pytest

ROOT = "/home/user/profiler_test"
OPT_PATH = os.path.join(ROOT, "process_optimized.py")
FASTA_PATH = os.path.join(ROOT, "reads.fasta")
CSV_PATH = os.path.join(ROOT, "final_concentrations.csv")


def get_truth(file_path=FASTA_PATH):
    """Compute expected output independently using the original ODE solver."""
    script = r'''
import json
import sys
from scipy.integrate import solve_ivp

def decay_ode(t, y, k):
    return -k * y

def read_fasta(file_path):
    seqs = {}
    with open(file_path, "r") as f:
        curr_id = ""
        curr_seq = []
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if curr_id:
                    seqs[curr_id] = "".join(curr_seq)
                curr_id = line[1:]
                curr_seq = []
            else:
                curr_seq.append(line)
        if curr_id:
            seqs[curr_id] = "".join(curr_seq)
    return seqs

results = {}
for seq_id, seq in read_fasta(sys.argv[1]).items():
    window = 100
    if len(seq) < window:
        max_gc = 0.5
    else:
        gc_count = sum(1 for base in seq[:window] if base in "GC")
        max_gc_count = gc_count
        for i in range(1, len(seq) - window + 1):
            if seq[i - 1] in "GC":
                gc_count -= 1
            if seq[i + window - 1] in "GC":
                gc_count += 1
            if gc_count > max_gc_count:
                max_gc_count = gc_count
        max_gc = max_gc_count / window
    sol = solve_ivp(decay_ode, [0, 10], [100.0], args=(max_gc,))
    results[seq_id] = f"{sol.y[0][-1]:.5f}"
print(json.dumps(results))
'''
    out = subprocess.check_output(["python3", "-c", script, file_path], timeout=30)
    return json.loads(out)


def parse_and_check_csv(text, truth):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert lines, "The CSV file is empty."
    assert lines[0] == "SeqID,Final_C", (
        "CSV header is incorrect. Expected 'SeqID,Final_C', "
        f"got '{lines[0]}'"
    )
    assert len(lines) - 1 == len(truth), (
        f"Expected {len(truth)} data rows, found {len(lines) - 1}."
    )

    seen = set()
    for line in lines[1:]:
        parts = line.split(",")
        assert len(parts) == 2, f"Invalid CSV line format: {line}"
        seq_id, final_c = parts
        assert seq_id not in seen, f"Duplicate SeqID found in CSV: {seq_id}"
        seen.add(seq_id)
        assert seq_id in truth, f"Unexpected SeqID found in CSV: {seq_id}"
        expected_c = truth[seq_id]
        assert final_c == expected_c, (
            f"Incorrect Final_C for {seq_id}. Expected {expected_c}, got {final_c}. "
            "Make sure the values are rounded to 5 decimal places and match the original script's output."
        )

    assert seen == set(truth), (
        f"CSV SeqIDs do not exactly match the FASTA records; missing={sorted(set(truth)-seen)}, "
        f"unexpected={sorted(seen-set(truth))}"
    )


def run_script(timeout=30):
    return subprocess.run(
        ["python3", OPT_PATH],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=True,
    )


SLOW_BASELINE = r'''
from scipy.integrate import solve_ivp

def read_fasta(path):
    seqs = {}
    curr_id = ""
    curr_seq = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if curr_id:
                    seqs[curr_id] = "".join(curr_seq)
                curr_id = line[1:]
                curr_seq = []
            else:
                curr_seq.append(line)
        if curr_id:
            seqs[curr_id] = "".join(curr_seq)
    return seqs

def decay_ode(t, y, k):
    return -k * y

for seq in read_fasta("reads.fasta").values():
    ratios = []
    for i in range(len(seq) - 100 + 1):
        subseq = seq[i:i+100]
        ratios.append(sum(1 for base in subseq if base in "GC") / 100)
    k = max(ratios) if ratios else 0.5
    solve_ivp(decay_ode, [0, 10], [100.0], args=(k,))
'''


@pytest.fixture(scope="session")
def executed_outputs():
    assert os.path.isfile(OPT_PATH), f"Optimized script {OPT_PATH} does not exist."
    with open(FASTA_PATH, "rb") as f:
        original_fasta = f.read()

    actual_truth = get_truth(FASTA_PATH)

    baseline_start = time.monotonic()
    subprocess.run(
        ["python3", "-c", SLOW_BASELINE],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        check=True,
    )
    baseline_elapsed = time.monotonic() - baseline_start

    rng = random.Random(91357)
    random_fasta = "".join(
        f">probe_{i}\n{''.join(rng.choices('ACGT', k=length))}\n"
        for i, length in enumerate([5031, 4877, 5203, 4999, 5111, 4763], 1)
    ).encode()

    try:
        with open(FASTA_PATH, "wb") as f:
            f.write(random_fasta)
        random_truth = get_truth(FASTA_PATH)
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        run_script()
        assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} does not exist after running the optimized script."
        with open(CSV_PATH) as f:
            random_csv = f.read()
    finally:
        with open(FASTA_PATH, "wb") as f:
            f.write(original_fasta)

    try:
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        optimized_start = time.monotonic()
        run_script()
        optimized_elapsed = time.monotonic() - optimized_start
        assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} does not exist after running the optimized script."
        with open(CSV_PATH) as f:
            actual_csv = f.read()
    finally:
        with open(FASTA_PATH, "wb") as f:
            f.write(original_fasta)

    return {
        "actual_truth": actual_truth,
        "actual_csv": actual_csv,
        "random_truth": random_truth,
        "random_csv": random_csv,
        "baseline_elapsed": baseline_elapsed,
        "optimized_elapsed": optimized_elapsed,
    }


def test_process_optimized_exists_and_uses_numpy():
    assert os.path.isfile(OPT_PATH), f"Optimized script {OPT_PATH} does not exist."
    with open(OPT_PATH, "r") as f:
        content = f.read()

    assert "import numpy" in content or "import numpy as np" in content, \
        "The optimized script must import and use numpy for vectorization."

    tree = ast.parse(content, filename=OPT_PATH)
    vector_ops = {
        "convolve", "correlate", "cumsum", "sliding_window_view",
        "uniform_filter1d", "lfilter", "fftconvolve"
    }
    called = {
        node.func.attr if isinstance(node.func, ast.Attribute) else node.func.id
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, (ast.Attribute, ast.Name))
    }
    assert called & vector_ops, (
        "The optimized script must actually use a vectorized sliding-window/signal-processing operation."
    )


def test_optimized_script_handles_derived_input(executed_outputs):
    parse_and_check_csv(executed_outputs["random_csv"], executed_outputs["random_truth"])


def test_final_concentrations_csv_correctness(executed_outputs):
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    parse_and_check_csv(executed_outputs["actual_csv"], executed_outputs["actual_truth"])


def test_optimized_script_is_faster(executed_outputs):
    optimized = executed_outputs["optimized_elapsed"]
    baseline = executed_outputs["baseline_elapsed"]
    assert optimized < baseline * 0.80, (
        f"Optimized script was not substantially faster than the naive implementation: "
        f"optimized={optimized:.3f}s, naive={baseline:.3f}s"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
