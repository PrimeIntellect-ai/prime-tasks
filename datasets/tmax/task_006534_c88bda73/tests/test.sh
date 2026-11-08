#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'RUST_EOF' > /home/user/motif_scorer/tests_verifier_determinism.rs
use motif_scorer::score_sequences;

fn sequential_score(sequences: &[String], weights: [f64; 4]) -> f64 {
    let mut total = 0.0_f64;
    for seq in sequences {
        let mut seq_score = 0.0_f64;
        for c in seq.chars() {
            seq_score += match c {
                'A' => weights[0],
                'C' => weights[1],
                'G' => weights[2],
                'T' => weights[3],
                _ => 0.0,
            };
        }
        total += (seq_score + 1.0).ln();
    }
    total
}

#[test]
fn verifier_requires_original_index_accumulation_order() {
    // The first item is deliberately much slower than all following items. The
    // old shared-Mutex implementation therefore accumulates it late, producing
    // a different floating-point reduction order from FASTA/index order.
    let mut sequences = Vec::new();
    sequences.push("T".repeat(4_000_000));
    for i in 1..97 {
        let alphabet = ['A', 'C', 'G', 'T'];
        let mut s = String::new();
        for j in 0..(7 + (i % 31)) {
            s.push(alphabet[(i * 3 + j * 5) % 4]);
        }
        sequences.push(s);
    }

    let weights = [0.101_f64, 0.203_f64, 0.307_f64, 0.389_f64];
    let expected = sequential_score(&sequences, weights);
    for _ in 0..3 {
        let actual = score_sequences(&sequences, weights);
        assert_eq!(actual.to_bits(), expected.to_bits(),
            "scores were not accumulated sequentially in original index order");
    }
}
RUST_EOF

mkdir -p /home/user/motif_scorer/tests
mv /home/user/motif_scorer/tests_verifier_determinism.rs \
   /home/user/motif_scorer/tests/verifier_determinism.rs
trap 'rm -f /home/user/motif_scorer/tests/verifier_determinism.rs' EXIT

cat <<'PY_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

import matplotlib.image as mpimg
import numpy as np
from scipy.optimize import minimize

PROJECT = "/home/user/motif_scorer"
FASTA = "/home/user/data/promoters.fasta"
EXPECTED_SEQUENCES = [
    "GGGCCCGGGCCCGGGCCC",
    "CCCGGGCCCGGGCCCGGG",
    "AGCTAGCTAGCTAGCTAG",
    "GGGGGGGGGGCCCCCCCC",
    "ATATATATATATATATAT",
]


def read_sequences(path):
    sequences = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith(">"):
                sequences.append(line)
    return sequences


def counts_for(sequences):
    return np.asarray(
        [[s.count("A"), s.count("C"), s.count("G"), s.count("T")] for s in sequences],
        dtype=float,
    )


def score_from_counts(counts, weights):
    return float(np.log1p(counts @ np.asarray(weights, dtype=float)).sum())


def independently_compute_optimum(counts):
    def objective(w):
        return -score_from_counts(counts, w)

    constraint = {"type": "eq", "fun": lambda w: float(np.sum(w) - 1.0)}
    starts = [np.full(4, 0.25)]
    starts.extend(np.eye(4))
    starts.extend([
        np.array([0.4, 0.0, 0.4, 0.2]),
        np.array([0.2, 0.0, 0.6, 0.2]),
    ])
    solutions = []
    for start in starts:
        result = minimize(
            objective,
            start,
            method="SLSQP",
            bounds=[(0.0, 1.0)] * 4,
            constraints=[constraint],
            options={"ftol": 1e-13, "maxiter": 2000},
        )
        assert result.success, result.message
        solutions.append(result.x)
    best = max(solutions, key=lambda w: score_from_counts(counts, w))
    return best, score_from_counts(counts, best)


def test_cargo_and_required_reduction_algorithm():
    assert os.path.isdir(PROJECT), "Project directory is missing"
    source_path = os.path.join(PROJECT, "src", "lib.rs")
    assert os.path.isfile(source_path), "src/lib.rs is missing"
    source = open(source_path, encoding="utf-8").read()

    # The requested repair explicitly associates scores with original indices
    # and sorts before reduction, rather than merely changing synchronization.
    assert re.search(r"\.enumerate\s*\(", source), \
        "score computation must retain each sequence's original index"
    assert re.search(r"\.sort(?:_unstable)?_by(?:_key)?\s*\(", source), \
        "individual results must be sorted by original index before summing"
    assert not re.search(r"Mutex\s*::\s*new\s*\(\s*0(?:\.0(?:_f64)?)?\s*\)", source), \
        "the shared floating-point accumulator is still present"

    result = subprocess.run(
        ["cargo", "test", "--all-targets"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180,
    )
    assert result.returncode == 0, f"cargo test failed:\n{result.stdout}\n{result.stderr}"


def test_outputs_are_the_true_optimum_and_cli_agrees():
    sequences = read_sequences(FASTA)
    assert sequences == EXPECTED_SEQUENCES, "promoters.fasta was modified"
    counts = counts_for(sequences)
    optimum_weights, optimum_score = independently_compute_optimum(counts)

    weights_path = "/home/user/best_weights.txt"
    assert os.path.isfile(weights_path), f"{weights_path} does not exist"
    weights_text = open(weights_path, encoding="utf-8").read().strip()
    assert re.fullmatch(r"(?:\d+\.\d{3},){3}\d+\.\d{3}", weights_text), \
        "best_weights.txt must contain four values rounded to exactly 3 decimals"
    weights = np.asarray([float(x) for x in weights_text.split(",")])
    assert np.all(np.isfinite(weights)) and np.all(weights >= 0.0)
    assert abs(float(weights.sum()) - 1.0) <= 1e-12, \
        f"weights sum to {weights.sum()}, not 1.0"
    assert np.max(np.abs(weights - optimum_weights)) <= 0.0011, \
        f"reported weights {weights.tolist()} are not the optimum {optimum_weights.tolist()}"

    score_path = "/home/user/max_score.txt"
    assert os.path.isfile(score_path), f"{score_path} does not exist"
    score_text = open(score_path, encoding="utf-8").read().strip()
    assert re.fullmatch(r"-?\d+\.\d{2}", score_text), \
        "max_score.txt must be rounded to exactly 2 decimals"
    reported_score = float(score_text)
    assert math.isfinite(reported_score)
    assert score_text == f"{optimum_score:.2f}", \
        f"reported score {score_text} does not match optimum {optimum_score:.12g}"

    build = subprocess.run(
        ["cargo", "build", "--release"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180,
    )
    assert build.returncode == 0, f"release build failed:\n{build.stdout}\n{build.stderr}"
    binary = os.path.join(PROJECT, "target", "release", "motif_scorer")
    run = subprocess.run(
        [binary, FASTA] + [format(x, ".3f") for x in weights],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30,
    )
    assert run.returncode == 0, f"motif_scorer failed: {run.stderr}"
    cli_score = float(run.stdout.strip())
    independently_scored = score_from_counts(counts, weights)
    assert math.isfinite(cli_score)
    assert math.isclose(cli_score, independently_scored, rel_tol=1e-12, abs_tol=1e-12), \
        f"CLI score {cli_score} disagrees with FASTA-derived score {independently_scored}"


def test_optimization_trace_is_a_real_nontrivial_png():
    path = "/home/user/optimization_trace.png"
    assert os.path.isfile(path), f"{path} does not exist"
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "trace is not a PNG file"
    image = np.asarray(mpimg.imread(path))
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, \
        "optimization trace has invalid or implausibly small dimensions"
    assert np.all(np.isfinite(image)), "optimization trace contains invalid pixels"
    assert float(np.max(image) - np.min(image)) > 0.05, \
        "optimization trace is visually empty or uniform"
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
