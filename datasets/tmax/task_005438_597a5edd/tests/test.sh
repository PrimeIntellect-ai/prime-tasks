#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import subprocess

import h5py
import numpy as np

PROJECT = "/home/user/primer_opt"
SOLUTION = "/home/user/solution.txt"
LANDSCAPE = "/app/genomic_landscape.h5"
SCORER = "/app/binding_scorer"
BASES = np.array(list("ACGT"))


def read_solution():
    assert os.path.exists(SOLUTION), f"Solution file {SOLUTION} does not exist."
    assert os.path.isfile(SOLUTION), f"Path {SOLUTION} is not a file."

    with open(SOLUTION, "r") as f:
        raw = f.read()
    content = raw.strip()
    assert content, "Solution file is empty."
    assert len(content.splitlines()) == 1, "Solution file must contain exactly one line."

    parts = content.split(",")
    assert len(parts) == 2, f"Solution file must contain exactly one line in format SEQUENCE,SCORE. Found: {content}"
    seq, score_str = parts
    seq = seq.strip()
    score_str = score_str.strip()

    assert len(seq) == 20, f"Sequence must be exactly 20 bp long. Found length {len(seq)}: {seq}"
    assert all(c in "ACGT" for c in seq), f"Sequence contains invalid characters. Must be A, C, G, T only. Found: {seq}"
    try:
        claimed_score = float(score_str)
    except ValueError:
        raise AssertionError(f"Could not parse submitted SCORE field: {score_str}")
    assert math.isfinite(claimed_score), "Submitted SCORE must be finite."
    return seq, claimed_score


def oracle_score(seq):
    result = subprocess.run([SCORER, seq], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Scorer binary failed with return code {result.returncode}. stderr: {result.stderr}"
    try:
        score = float(result.stdout.strip())
    except ValueError:
        raise AssertionError(f"Could not parse score from scorer output: {result.stdout}")
    assert math.isfinite(score), "Scorer returned a non-finite score."
    return score


def expected_for_landscape():
    with h5py.File(LANDSCAPE, "r") as f:
        assert "nucleotide_probs" in f, "HDF5 dataset nucleotide_probs is missing."
        probs = f["nucleotide_probs"][:]
    assert probs.shape == (4, 10000), f"Unexpected nucleotide_probs shape: {probs.shape}"

    consensus = "".join(BASES[np.argmax(probs, axis=0)])
    gc = np.fromiter((base in "GC" for base in consensus), dtype=np.int16, count=len(consensus))
    window_counts = np.convolve(gc, np.ones(500, dtype=np.int16), mode="valid")
    window_start = int(np.argmax(window_counts))
    window = consensus[window_start:window_start + 500]

    candidates = [window[i:i + 20] for i in range(481)]
    scored = [(candidate, oracle_score(candidate)) for candidate in candidates]
    best_score = max(score for _, score in scored)
    best_sequences = {candidate for candidate, score in scored if math.isclose(score, best_score, rel_tol=0.0, abs_tol=1e-9)}
    return window, best_sequences, best_score


def run_project():
    if os.path.lexists(SOLUTION):
        os.remove(SOLUTION)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "cargo", "run", "--release", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        capture_output=True,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, f"Rust project failed to compile or run. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(SOLUTION), "Running the Rust project did not create /home/user/solution.txt."


def assert_optimal_output(require_threshold):
    seq, claimed_score = read_solution()
    window, best_sequences, best_score = expected_for_landscape()
    actual_score = oracle_score(seq)

    assert seq in window, "Submitted sequence is not a contiguous 20-bp primer in the selected highest-GC 500-bp window."
    assert math.isclose(claimed_score, actual_score, rel_tol=0.0, abs_tol=1e-6), f"Submitted SCORE {claimed_score} does not match scorer output {actual_score}."
    assert seq in best_sequences, f"Submitted primer is not optimal in the selected window; its score is {actual_score}, but the maximum is {best_score}."
    assert math.isclose(actual_score, best_score, rel_tol=0.0, abs_tol=1e-9)
    if require_threshold:
        threshold = 85.0
        assert actual_score >= threshold, f"Binding affinity score {actual_score} is below the threshold of {threshold}."


def write_alternate_landscape():
    probs = np.full((4, 10000), 0.01, dtype=np.float32)
    probs[0, :] = 0.97
    probs[:, 7000:7500] = 0.01
    probs[1, 7000:7500] = 0.97
    with h5py.File(LANDSCAPE, "w") as f:
        f.create_dataset("nucleotide_probs", data=probs, dtype="float32")


def test_rust_pipeline_and_optimal_solution():
    assert os.path.isdir(PROJECT), f"Rust project directory {PROJECT} does not exist."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Rust project is missing Cargo.toml."
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "Rust project is missing src/main.rs."
    assert os.path.exists(SCORER) and os.access(SCORER, os.X_OK), f"Scorer binary {SCORER} is missing or not executable."
    assert os.path.isfile(LANDSCAPE), f"Genomic landscape {LANDSCAPE} is missing."

    backup = "/tmp/genomic_landscape.verifier_backup.h5"
    shutil.copy2(LANDSCAPE, backup)
    try:
        # Exercise the compiled project on a second landscape so a hardcoded
        # offset or primer cannot satisfy the required dynamic pipeline.
        write_alternate_landscape()
        run_project()
        assert_optimal_output(require_threshold=False)

        shutil.copy2(backup, LANDSCAPE)
        run_project()
        assert_optimal_output(require_threshold=True)
    finally:
        if os.path.exists(backup):
            shutil.copy2(backup, LANDSCAPE)
            os.remove(backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
