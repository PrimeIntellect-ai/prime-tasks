#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

ETL = "/home/user/etl"
LABELS = [
    "Centroid_A_Dim0",
    "Centroid_A_Dim25",
    "Mean_Distance",
    "Std_Dev",
    "CI_95_Lower",
    "CI_95_Upper",
]


def compute_embeddings(filepath):
    embeddings = []
    with open(filepath, 'r') as f:
        for line in f:
            counts = [0] * 26
            total = 0
            for char in line:
                if char.isalpha():
                    counts[ord(char.lower()) - ord('a')] += 1
                    total += 1
            if total > 0:
                embeddings.append([c / total for c in counts])
            else:
                embeddings.append([0.0] * 26)
    return embeddings


def expected_metrics(embed_A, embed_B):
    assert embed_A and embed_B
    centroid_A = [sum(col) / len(embed_A) for col in zip(*embed_A)]
    distances = [
        math.sqrt(sum((value - center) ** 2 for value, center in zip(row, centroid_A)))
        for row in embed_B
    ]
    mean_dist = sum(distances) / len(distances)
    variance = (
        sum((distance - mean_dist) ** 2 for distance in distances) / (len(distances) - 1)
        if len(distances) > 1 else 0.0
    )
    std_dev = math.sqrt(variance)
    margin = 1.96 * std_dev / math.sqrt(len(distances))
    return {
        "Centroid_A_Dim0": centroid_A[0],
        "Centroid_A_Dim25": centroid_A[25],
        "Mean_Distance": mean_dist,
        "Std_Dev": std_dev,
        "CI_95_Lower": mean_dist - margin,
        "CI_95_Upper": mean_dist + margin,
    }


def read_csv(path):
    rows = []
    with open(path, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            assert len(parts) == 26, f"Expected 26 dimensions in {path}, got {len(parts)}."
            rows.append([float(part) for part in parts])
    assert rows, f"{path} is empty."
    return rows


def parse_exact_metrics(path):
    with open(path, 'r') as f:
        text = f.read()
    pattern = r'\A' + ''.join(
        re.escape(label) + r': -?\d+\.\d{6}\n' for label in LABELS
    ) + r'\Z'
    assert re.fullmatch(pattern, text), (
        "metrics.txt must contain exactly the six requested lines in order, "
        "with one space after each colon and exactly six decimal places."
    )
    values = {}
    for line in text.splitlines():
        key, value = line.split(': ', 1)
        values[key] = float(value)
    return values


def assert_metric_values(actual, expected, tolerance=1.1e-6):
    for key, expected_value in expected.items():
        assert key in actual, f"Missing metric {key} in metrics.txt"
        assert math.isclose(actual[key], expected_value, rel_tol=0.0, abs_tol=tolerance), (
            f"Metric {key} mismatch. Expected {expected_value:.6f}, got {actual[key]:.6f}"
        )


def run_evaluate():
    metrics_path = os.path.join(ETL, "metrics.txt")
    with open(metrics_path, 'w') as output:
        result = subprocess.run(
            [os.path.join(ETL, "evaluate")],
            cwd=ETL,
            stdout=output,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    assert result.returncode == 0, f"evaluate failed: {result.stderr}"
    return parse_exact_metrics(metrics_path)


def test_files_exist():
    expected_files = [
        "/home/user/etl/embedder",
        "/home/user/etl/embed_A.csv",
        "/home/user/etl/embed_B.csv",
        "/home/user/etl/evaluate.c",
        "/home/user/etl/evaluate",
        "/home/user/etl/metrics.txt"
    ]
    for path in expected_files:
        assert os.path.exists(path), f"Expected file {path} is missing."
    assert os.path.isfile(os.path.join(ETL, "evaluate")), "evaluate is not a regular file."
    assert os.access(os.path.join(ETL, "evaluate"), os.X_OK), "evaluate is not executable."


def test_metrics_values():
    metrics_path = "/home/user/etl/metrics.txt"
    assert os.path.isfile(metrics_path), f"File {metrics_path} is missing."

    embed_A = compute_embeddings("/home/user/etl/dataset_A.txt")
    embed_B = compute_embeddings("/home/user/etl/dataset_B.txt")
    expected = expected_metrics(embed_A, embed_B)

    parsed_metrics = {}
    with open(metrics_path, 'r') as f:
        for line in f:
            match = re.match(r'^([^:]+):\s*([\d\.\-]+)', line.strip())
            if match:
                key, value = match.groups()
                parsed_metrics[key] = float(value)

    for key, expected_val in expected.items():
        assert key in parsed_metrics, f"Missing metric {key} in metrics.txt"
        actual_val = parsed_metrics[key]
        assert math.isclose(actual_val, expected_val, abs_tol=1e-4), \
            f"Metric {key} mismatch. Expected ~{expected_val:.6f}, got {actual_val:.6f}"

    parse_exact_metrics(metrics_path)


def test_embed_csv_format():
    embed_a_path = "/home/user/etl/embed_A.csv"
    with open(embed_a_path, 'r') as f:
        lines = f.readlines()
        assert len(lines) > 0, "embed_A.csv is empty."
        for line in lines:
            parts = line.strip().split(',')
            assert len(parts) == 26, f"Expected 26 dimensions in embed_A.csv, got {len(parts)}."
            for p in parts:
                float(p)


def test_compile_and_execute_evaluate_on_real_and_unseen_inputs():
    source = os.path.join(ETL, "evaluate.c")
    executable = os.path.join(ETL, "evaluate")
    compile_result = subprocess.run(
        ["gcc", "-std=c11", source, "-o", executable, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"evaluate.c did not compile: {compile_result.stderr}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)

    original_A_path = os.path.join(ETL, "embed_A.csv")
    original_B_path = os.path.join(ETL, "embed_B.csv")
    metrics_path = os.path.join(ETL, "metrics.txt")

    original_A = read_csv(original_A_path)
    original_B = read_csv(original_B_path)
    actual = run_evaluate()
    assert_metric_values(actual, expected_metrics(original_A, original_B), tolerance=2.1e-6)

    backups = {}
    for path in (original_A_path, original_B_path, metrics_path):
        with open(path, 'rb') as f:
            backups[path] = f.read()

    try:
        rng = random.SystemRandom()

        def make_rows(count):
            rows = []
            for _ in range(count):
                weights = [rng.randint(1, 1000) for _ in range(26)]
                total = sum(weights)
                rows.append([weight / total for weight in weights])
            return rows

        challenge_A = make_rows(4)
        challenge_B = make_rows(7)
        for path, rows in ((original_A_path, challenge_A), (original_B_path, challenge_B)):
            with open(path, 'w') as f:
                for row in rows:
                    f.write(','.join(f"{value:.12f}" for value in row) + '\n')

        written_A = read_csv(original_A_path)
        written_B = read_csv(original_B_path)
        challenge_actual = run_evaluate()
        assert_metric_values(
            challenge_actual,
            expected_metrics(written_A, written_B),
            tolerance=2.1e-6,
        )
    finally:
        for path, contents in backups.items():
            with open(path, 'wb') as f:
                f.write(contents)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
