#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import glob
import math
import csv
import random
import shutil
import subprocess
import pytest

PROBE_PATH = "/home/user/experiments/exp_999.json"

@pytest.fixture(scope="module", autouse=True)
def execute_pipeline():
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"Pipeline script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Pipeline script {script_path} is not a regular file."
    assert os.access(script_path, os.X_OK), f"Pipeline script {script_path} is not executable."

    rng = random.SystemRandom()
    probe = {
        "run_id": "exp_999",
        "accuracy": rng.uniform(0.15, 0.98),
        "accuracy_variance": rng.uniform(0.001, 0.05),
        "latency_ms": rng.uniform(5.0, 120.0),
        "memory_mb": rng.uniform(50.0, 500.0),
    }
    with open(PROBE_PATH, "w") as f:
        json.dump(probe, f)

    for output_path in ("/home/user/covariance.csv", "/home/user/report.json"):
        if os.path.isdir(output_path):
            shutil.rmtree(output_path)
        elif os.path.lexists(output_path):
            os.remove(output_path)

    try:
        result = subprocess.run(
            ["bash", script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, (
            f"Pipeline exited with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
        assert os.path.isfile(PROBE_PATH), "Pipeline removed the verifier experiment input."
        with open(PROBE_PATH, "r") as f:
            assert json.load(f) == probe, "Pipeline modified the verifier experiment input."
        yield
    finally:
        if os.path.exists(PROBE_PATH):
            os.remove(PROBE_PATH)

def compute_ground_truth():
    files = glob.glob("/home/user/experiments/*.json")
    assert len(files) > 0, "No experiment files found."

    data = []
    for f in files:
        with open(f, 'r') as file:
            data.append(json.load(file))

    # Sort by run_id to ensure consistent ordering if needed,
    # though sum and cov don't strictly require it, it's good practice.
    data.sort(key=lambda x: x['run_id'])

    n = len(data)

    # Extract metrics
    accs = [d['accuracy'] for d in data]
    lats = [d['latency_ms'] for d in data]
    mems = [d['memory_mb'] for d in data]

    # Compute means
    mean_acc = sum(accs) / n
    mean_lat = sum(lats) / n
    mean_mem = sum(mems) / n

    # Compute covariance matrix
    def cov(xs, ys, mean_x, mean_y):
        return sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / (n - 1)

    cov_matrix = [
        [cov(accs, accs, mean_acc, mean_acc), cov(accs, lats, mean_acc, mean_lat), cov(accs, mems, mean_acc, mean_mem)],
        [cov(lats, accs, mean_lat, mean_acc), cov(lats, lats, mean_lat, mean_lat), cov(lats, mems, mean_lat, mean_mem)],
        [cov(mems, accs, mean_mem, mean_acc), cov(mems, lats, mean_mem, mean_lat), cov(mems, mems, mean_mem, mean_mem)]
    ]

    mu_0 = 0.80
    var_0 = 0.01

    best_bayesian_score = -float('inf')
    best_bayesian_run = ""

    most_similar_score = -float('inf')
    most_similar_run = ""
    ideal_vec = [1.0, 10.0, 100.0]
    ideal_norm = math.sqrt(sum(v**2 for v in ideal_vec))

    for d in data:
        # Bayesian posterior mean
        x = d['accuracy']
        var_x = d['accuracy_variance']

        post_mean = (mu_0 / var_0 + x / var_x) / (1/var_0 + 1/var_x)
        if post_mean > best_bayesian_score:
            best_bayesian_score = post_mean
            best_bayesian_run = d['run_id']

        # Cosine similarity
        vec = [d['accuracy'], d['latency_ms'], d['memory_mb']]
        dot_product = sum(v1 * v2 for v1, v2 in zip(vec, ideal_vec))
        vec_norm = math.sqrt(sum(v**2 for v in vec))
        cos_sim = dot_product / (vec_norm * ideal_norm)

        if cos_sim > most_similar_score:
            most_similar_score = cos_sim
            most_similar_run = d['run_id']

    return cov_matrix, best_bayesian_run, most_similar_run

def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"Pipeline script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Pipeline script {script_path} is not executable."

def test_covariance_csv():
    cov_path = "/home/user/covariance.csv"
    assert os.path.exists(cov_path), f"Covariance file {cov_path} does not exist."

    expected_cov, _, _ = compute_ground_truth()

    with open(cov_path, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 3, f"Expected 3 rows in covariance.csv, found {len(rows)}."

    for i in range(3):
        assert len(rows[i]) == 3, f"Expected 3 columns in row {i} of covariance.csv, found {len(rows[i])}."
        for j in range(3):
            try:
                val = float(rows[i][j])
            except ValueError:
                assert False, f"Non-numeric value found in covariance.csv at row {i}, col {j}: {rows[i][j]}"

            expected_val = expected_cov[i][j]
            assert abs(val - expected_val) <= 0.0002, (
                f"Covariance mismatch at row {i}, col {j}. "
                f"Expected ~{expected_val:.4f}, found {val}"
            )

def test_report_json():
    report_path = "/home/user/report.json"
    assert os.path.exists(report_path), f"Report file {report_path} does not exist."

    try:
        with open(report_path, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError:
        assert False, f"Report file {report_path} is not valid JSON."

    _, expected_bayesian, expected_similar = compute_ground_truth()

    assert "best_bayesian_run" in report, "Key 'best_bayesian_run' missing in report.json."
    assert "most_similar_run" in report, "Key 'most_similar_run' missing in report.json."

    assert report["best_bayesian_run"] == expected_bayesian, (
        f"Expected best_bayesian_run to be {expected_bayesian}, "
        f"but got {report['best_bayesian_run']}."
    )

    assert report["most_similar_run"] == expected_similar, (
        f"Expected most_similar_run to be {expected_similar}, "
        f"but got {report['most_similar_run']}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
