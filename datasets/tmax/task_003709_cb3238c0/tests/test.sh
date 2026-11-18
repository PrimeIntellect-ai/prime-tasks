#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import uuid

import numpy as np

SCRIPT_PATH = "/home/user/filter_edm.py"
TOLERANCE = 1.2e-4


def run_filter(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=15,
    ).returncode


def test_filter_edm_on_corpora():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    evil_corpus_path = "/app/corpora/evil/"
    clean_corpus_path = "/app/corpora/clean/"

    evil_files = [os.path.join(evil_corpus_path, f) for f in os.listdir(evil_corpus_path) if f.endswith('.pdist')]
    clean_files = [os.path.join(clean_corpus_path, f) for f in os.listdir(clean_corpus_path) if f.endswith('.pdist')]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run(["python3", SCRIPT_PATH, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = subprocess.run(["python3", SCRIPT_PATH, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    assert not errors, " | ".join(errors)


def write_pdist(directory, distances, rng):
    n = distances.shape[0]
    path = os.path.join(directory, uuid.uuid4().hex + ".pdist")
    pairs = [(i, j) for i in range(n) for j in range(i + 1, n)]
    rng.shuffle(pairs)
    with open(path, "w") as f:
        f.write(f">{uuid.uuid4().hex} {'A' * n}\n")
        # Deliberately provide each pair only once and in shuffled order. The
        # required parser must populate the other half of the symmetric matrix.
        for i, j in pairs:
            f.write(f"{i} {j} {distances[i, j]:.12f}\n")
    return path


def read_serialized_distances(path):
    entries = []
    maximum = -1
    with open(path) as f:
        next(f)
        for line in f:
            i, j, value = line.split()
            i, j = int(i), int(j)
            entries.append((i, j, float(value)))
            maximum = max(maximum, i, j)
    d = np.zeros((maximum + 1, maximum + 1), dtype=float)
    for i, j, value in entries:
        d[i, j] = value
        d[j, i] = value
    return d


def expected_returncode(path):
    d = read_serialized_distances(path)
    n = d.shape[0]
    j = np.eye(n) - np.ones((n, n)) / n
    gram = -0.5 * j @ (d ** 2) @ j
    minimum = np.linalg.eigvalsh(gram)[0]
    return 0 if minimum >= -TOLERANCE else 1


def distances_with_gram_eigenvalue(target, rng):
    # Build a centered Gram matrix whose nonzero eigenvalues consist of three
    # positive values and the requested small negative value.
    n = 5
    centered = np.eye(n) - np.ones((n, n)) / n
    q, _ = np.linalg.qr(centered @ rng.normal(size=(n, n - 1)))
    q = q[:, :n - 1]
    gram = q @ np.diag([1.7, 0.9, 0.35, target]) @ q.T
    diagonal = np.diag(gram)
    squared = diagonal[:, None] + diagonal[None, :] - 2.0 * gram
    assert squared.min() > -1e-10
    np.fill_diagonal(squared, 0.0)
    return np.sqrt(np.maximum(squared, 0.0))


def test_generated_neutral_paths_and_memo_tolerance():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))

    with tempfile.TemporaryDirectory() as directory:
        paths = []

        # Independently generated Euclidean point clouds.
        for n in (4, 6, 9):
            points = rng.normal(size=(n, 3))
            distances = np.linalg.norm(points[:, None, :] - points[None, :, :], axis=2)
            paths.append(write_pdist(directory, distances, rng))

        # Cases on opposite sides of the tolerance from the audio memo. These
        # distinguish 1.2e-4 from nearby, guessed tolerances.
        paths.append(write_pdist(directory, distances_with_gram_eigenvalue(-1.1e-4, rng), rng))
        paths.append(write_pdist(directory, distances_with_gram_eigenvalue(-1.3e-4, rng), rng))

        # Random symmetric dissimilarities supply additional invalid matrices.
        for _ in range(3):
            n = int(rng.integers(5, 9))
            distances = rng.uniform(0.2, 8.0, size=(n, n))
            distances = (distances + distances.T) / 2.0
            np.fill_diagonal(distances, 0.0)
            paths.append(write_pdist(directory, distances, rng))

        expected = [expected_returncode(path) for path in paths]
        assert 0 in expected and 1 in expected, "Generated suite must contain both outcomes"

        failures = []
        for path, wanted in zip(paths, expected):
            actual = run_filter(path)
            if actual != wanted:
                failures.append(f"{os.path.basename(path)}: expected {wanted}, got {actual}")
        assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
