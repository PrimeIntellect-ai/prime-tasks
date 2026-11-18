#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import subprocess
import pytest

TRACKER_DIR = '/home/user/tracker'
SOURCE_PATH = os.path.join(TRACKER_DIR, 'artifact_tracker.cpp')
BINARY_PATH = os.path.join(TRACKER_DIR, 'artifact_tracker')
OUTPUT_PATH = os.path.join(TRACKER_DIR, 'output.csv')
QUERY_PATH = '/home/user/data/query.txt'


def test_dependencies_installed():
    """Test that g++ and boost-math-dev are installed."""
    try:
        subprocess.run(['g++', '--version'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except (subprocess.CalledProcessError, FileNotFoundError):
        pytest.fail("g++ is not installed or not in PATH.")

    boost_header = '/usr/include/boost/math/distributions/beta.hpp'
    assert os.path.isfile(boost_header), f"Boost math header {boost_header} not found. libboost-math-dev might not be installed."


def test_bug_fixed_in_source():
    """Test that the integer division bug was removed from the source code."""
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."

    with open(SOURCE_PATH, 'r') as f:
        content = f.read()

    buggy_snippet = "(int(p_alpha) - 1) / (int(p_alpha) + int(p_beta) - 2)"
    assert buggy_snippet not in content, "The integer division bug is still present in artifact_tracker.cpp."


def test_binary_compiled():
    """Test that the artifact_tracker binary exists and is executable."""
    assert os.path.isfile(BINARY_PATH), f"Compiled binary {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."


def test_build_and_run_artifact():
    """Rebuild the submitted C++ source and require that its binary generates output.csv."""
    subprocess.run(
        ['make', '-B', 'artifact_tracker'],
        cwd=TRACKER_DIR,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )

    # Compile the named source directly as well, so an altered Makefile cannot
    # substitute an unrelated executable for the requested C++ tracker.
    subprocess.run(
        ['g++', '-std=c++11', '-O2', '-o', BINARY_PATH, SOURCE_PATH],
        cwd=TRACKER_DIR,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )

    assert os.path.isfile(BINARY_PATH), f"Compiled binary {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "artifact_tracker is not a compiled ELF binary."

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    subprocess.run(
        [BINARY_PATH, QUERY_PATH],
        cwd=TRACKER_DIR,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert os.path.isfile(OUTPUT_PATH), "The compiled artifact_tracker did not generate output.csv when executed."


def compute_expected_results():
    """Helper to compute the expected results from the input files."""
    models = {}

    with open('/home/user/data/models.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            models[row['model_id']] = {
                'prior_alpha': float(row['prior_alpha']),
                'prior_beta': float(row['prior_beta'])
            }

    with open('/home/user/data/trials.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            m_id = row['model_id']
            models[m_id]['successes'] = int(row['successes'])
            models[m_id]['failures'] = int(row['failures'])
            models[m_id]['embedding'] = [float(x) for x in row['embedding'].split(';')]

    with open(QUERY_PATH, 'r') as f:
        query_str = f.read().strip()
        query = [float(x) for x in query_str.split(';')]

    results = {}
    for m_id, data in models.items():
        p_alpha = data['prior_alpha'] + data['successes']
        p_beta = data['prior_beta'] + data['failures']
        map_est = (p_alpha - 1.0) / (p_alpha + p_beta - 2.0)

        emb = data['embedding']
        dot = sum(a * b for a, b in zip(emb, query))
        norm_emb = math.sqrt(sum(a * a for a in emb))
        norm_q = math.sqrt(sum(a * a for a in query))
        sim = dot / (norm_emb * norm_q)
        final_score = map_est * sim

        results[m_id] = {
            'post_alpha': p_alpha,
            'post_beta': p_beta,
            'map_estimate': map_est,
            'similarity': sim,
            'final_score': final_score
        }

    return results


def test_output_csv_correctness():
    """Test that output.csv is generated and contains the correctly computed values."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not generated."

    expected = compute_expected_results()

    actual = {}
    with open(OUTPUT_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            actual[row['model_id']] = {
                'post_alpha': float(row['post_alpha']),
                'post_beta': float(row['post_beta']),
                'map_estimate': float(row['map_estimate']),
                'similarity': float(row['similarity']),
                'final_score': float(row['final_score'])
            }

    assert len(actual) == len(expected), "Output CSV does not have the expected number of models."

    tolerance = 0.001
    for m_id, exp_vals in expected.items():
        assert m_id in actual, f"Model {m_id} missing from output."
        act_vals = actual[m_id]

        for key in ['post_alpha', 'post_beta', 'map_estimate', 'similarity', 'final_score']:
            diff = abs(exp_vals[key] - act_vals[key])
            assert diff <= tolerance, (
                f"Value mismatch for model {m_id}, metric {key}: "
                f"Expected ~{exp_vals[key]:.4f}, got {act_vals[key]:.4f}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
