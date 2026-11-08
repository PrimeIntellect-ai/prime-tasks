#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import numpy as np
import pytest

PACKAGE_ROOT = '/app/dna_factorize-1.2.0'
CORE_PATH = os.path.join(PACKAGE_ROOT, 'dna_factorize', 'core.py')
PRIMERS_PATH = '/home/user/primers.txt'
TARGET_PATH = '/home/user/target_profile.npy'
WEIGHTS_PATH = '/home/user/weights.csv'


def expected_fixtures():
    rng = random.Random(123)
    bases = ['A', 'C', 'G', 'T']
    primers = []
    for _ in range(100):
        pattern = ''.join(rng.choices(bases, k=2))
        primers.append(pattern * 15)
    target = np.random.RandomState(123).rand(16) * 2.0
    return primers, target


def reference_embeddings(seqs):
    k = 3
    counts_by_sequence = []
    for sequence in seqs:
        counts = {}
        for i in range(len(sequence) - k + 1):
            kmer = sequence[i:i + k]
            counts[kmer] = counts.get(kmer, 0) + 1
        counts_by_sequence.append(counts)

    all_kmers = sorted({kmer for counts in counts_by_sequence for kmer in counts})
    X = np.zeros((len(seqs), len(all_kmers)))
    for i, counts in enumerate(counts_by_sequence):
        for j, kmer in enumerate(all_kmers):
            X[i, j] = counts.get(kmer, 0)
    X = X.T

    rng = np.random.RandomState(42)
    W = rng.rand(X.shape[0], 16)
    H = rng.rand(16, X.shape[1])
    for _ in range(50):
        H = H * (W.T @ X) / (W.T @ W @ H + 1e-9)
        W = W * (X @ H.T) / (W @ H @ H.T + 1e-9)
    return H.T


def contains_epsilon(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return np.isclose(float(node.value), 1e-9, rtol=0.0, atol=1e-15)
    if isinstance(node, ast.Name) and node.id in assignments:
        return contains_epsilon(assignments[node.id], assignments)
    return any(contains_epsilon(child, assignments) for child in ast.iter_child_nodes(node))


def assert_h_denominator_has_epsilon():
    assert os.path.isfile(CORE_PATH), f'Missing vendored source file {CORE_PATH}'
    with open(CORE_PATH, encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=CORE_PATH)

    assignments = {}
    fixed_h_update = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value

    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        if not any(isinstance(target, ast.Name) and target.id == 'H' for target in node.targets):
            continue
        if isinstance(node.value, ast.BinOp) and isinstance(node.value.op, ast.Div):
            if contains_epsilon(node.value.right, assignments):
                fixed_h_update = True
                break

    assert fixed_h_update, 'The denominator of the multiplicative H update does not include epsilon 1e-9.'


def test_weights_file_exists():
    assert os.path.isfile(WEIGHTS_PATH), 'The file /home/user/weights.csv is missing.'


def test_package_fixed_and_mse_threshold():
    assert_h_denominator_has_epsilon()

    try:
        import dna_factorize
        from dna_factorize import embed_sequences
        import dna_factorize.core as core
    except ImportError:
        pytest.fail('Could not import `dna_factorize`. Was the fixed package installed?')

    actual_core = os.path.realpath(core.__file__)
    assert actual_core == os.path.realpath(CORE_PATH), (
        f'Imported dna_factorize.core from {actual_core}, not the fixed vendored package.'
    )

    expected_primers, expected_target = expected_fixtures()

    assert os.path.isfile(PRIMERS_PATH), f'Missing {PRIMERS_PATH}'
    with open(PRIMERS_PATH) as f:
        primers = [line.strip() for line in f if line.strip()]
    assert primers == expected_primers, 'primers.txt was modified from the original fixture.'

    assert os.path.isfile(TARGET_PATH), f'Missing {TARGET_PATH}'
    target = np.load(TARGET_PATH, allow_pickle=False)
    assert target.shape == (16,), f'Expected target shape (16,), got {target.shape}'
    assert np.array_equal(target, expected_target), 'target_profile.npy was modified from the original fixture.'

    expected_embeddings = reference_embeddings(expected_primers)
    try:
        embeddings = embed_sequences(primers)
    except Exception as e:
        pytest.fail(f'embed_sequences failed with error: {e}. Is the NaN bug fixed?')

    embeddings = np.asarray(embeddings)
    assert not np.isnan(embeddings).any(), 'Embeddings contain NaNs. The division-by-zero bug in dna_factorize/core.py is not properly fixed.'
    assert embeddings.shape == (100, 16), f'Expected embeddings shape (100, 16), got {embeddings.shape}'
    assert np.isfinite(embeddings).all(), 'Embeddings contain non-finite values.'
    assert np.allclose(embeddings, expected_embeddings, rtol=1e-10, atol=1e-12), (
        'embed_sequences does not produce the embeddings from the fixed vendored implementation.'
    )

    try:
        weights = np.loadtxt(WEIGHTS_PATH, delimiter=',')
    except Exception as e:
        pytest.fail(f'Could not load weights from {WEIGHTS_PATH}: {e}')

    assert weights.shape == (100,), f'Expected 100 weights in {WEIGHTS_PATH}, got shape {weights.shape}'
    assert np.isfinite(weights).all(), 'Weights must all be finite.'
    assert np.all(weights >= 0), 'All weights must be non-negative.'

    weights_sum = np.sum(weights)
    assert weights_sum > 0, 'Sum of weights must be greater than 0'
    assert np.isclose(weights_sum, 1.0, rtol=0.0, atol=1e-6), f'Weights must sum to 1, got {weights_sum}'
    weights = weights / weights_sum

    pred = np.average(expected_embeddings, axis=0, weights=weights)
    mse = np.mean((pred - expected_target) ** 2)
    threshold = 0.005
    assert mse <= threshold, f'MSE {mse:.6f} is greater than the threshold {threshold}. The optimized weights do not match the target profile closely enough.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
