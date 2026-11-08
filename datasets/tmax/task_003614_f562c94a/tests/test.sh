#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import secrets
import subprocess

import pytest

GO_PATH = "/home/user/ml_prep/analyzer.go"
GO_DIR = "/home/user/ml_prep"
DATA_PATH = "/home/user/data.csv"
JSON_PATH = "/home/user/stats.json"
EXPECTED_KEYS = {"correlation_length_score", "covariance_ai_score", "filtered_count"}


def run_analyzer():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        ["go", "run", "analyzer.go"],
        cwd=GO_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "go run analyzer.go failed.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    return load_stats()


def load_stats():
    assert os.path.exists(JSON_PATH), f"The output file {JSON_PATH} is missing."
    assert os.path.isfile(JSON_PATH), f"The path {JSON_PATH} is not a file."
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")
    assert set(data.keys()) == EXPECTED_KEYS, (
        f"Expected keys {EXPECTED_KEYS}, but got {set(data.keys())}."
    )
    return data


def oracle(rows):
    token_counts = []
    ai_values = []
    scores = []
    for _, text, score_text in rows:
        normalized = re.sub(r"[^a-z0-9]", " ", text.lower())
        tokens = [token for token in normalized.split(" ") if token]
        token_counts.append(len(tokens))
        ai_values.append(1 if "ai" in tokens else 0)
        scores.append(float(score_text))

    mean_x = sum(token_counts) / len(token_counts)
    mean_y = sum(scores) / len(scores)
    cross = sum((x - mean_x) * (y - mean_y) for x, y in zip(token_counts, scores))
    sum_x2 = sum((x - mean_x) ** 2 for x in token_counts)
    sum_y2 = sum((y - mean_y) ** 2 for y in scores)
    correlation = cross / math.sqrt(sum_x2 * sum_y2)

    filtered = [
        (ai, score)
        for count, ai, score in zip(token_counts, ai_values, scores)
        if count > 5
    ]
    mean_ai = sum(ai for ai, _ in filtered) / len(filtered)
    mean_score = sum(score for _, score in filtered) / len(filtered)
    covariance = sum(
        (ai - mean_ai) * (score - mean_score) for ai, score in filtered
    ) / (len(filtered) - 1)

    return {
        "correlation_length_score": correlation,
        "covariance_ai_score": covariance,
        "filtered_count": len(filtered),
    }


def assert_matches(data, expected, tolerance=1e-9):
    assert set(data.keys()) == EXPECTED_KEYS
    assert data["filtered_count"] == expected["filtered_count"]
    for key in ("correlation_length_score", "covariance_ai_score"):
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{key} must be a number."
        assert math.isfinite(value), f"{key} must be finite."
        assert math.isclose(value, expected[key], rel_tol=tolerance, abs_tol=tolerance), (
            f"Expected {key} to be {expected[key]}, but got {value}."
        )


def test_go_code_exists():
    """Test that the Go program exists at the specified location."""
    assert os.path.exists(GO_PATH), f"The Go source file {GO_PATH} is missing."
    assert os.path.isfile(GO_PATH), f"The path {GO_PATH} is not a file."


def test_program_executes_and_computes_statistics():
    with open(DATA_PATH, "rb") as f:
        original_csv = f.read()

    original_stats = None
    try:
        # Execute the submitted artifact on the provided dataset before checking
        # the original verifier's assertions.
        data = run_analyzer()
        assert data["filtered_count"] == 4, (
            f"Expected filtered_count to be 4, but got {data['filtered_count']}."
        )
        corr = data["correlation_length_score"]
        assert isinstance(corr, (int, float)), "correlation_length_score must be a number."
        assert abs(corr - 0.169136) < 0.001, (
            f"Expected correlation_length_score around 0.169136, but got {corr}."
        )
        cov = data["covariance_ai_score"]
        assert isinstance(cov, (int, float)), "covariance_ai_score must be a number."
        assert abs(cov - 0.183333) < 0.001, (
            f"Expected covariance_ai_score around 0.183333, but got {cov}."
        )
        with open(JSON_PATH, "rb") as f:
            original_stats = f.read()

        # Use runtime-generated scores so fixed stats.json values cannot pass.
        counts = [2, 6, 7, 4, 8, 9, 5, 10, 3, 6, 7, 8]
        ai_flags = [False, True, False, True, True, False, False, True, False, False, True, False]
        separators = [",", "!!", "---", " / ", "  ", "@@"]
        rows = []
        for i, (count, has_ai) in enumerate(zip(counts, ai_flags), start=1):
            tokens = [f"word{j}" for j in range(count)]
            if has_ai:
                tokens[count // 2] = "AI"
            else:
                tokens[count // 2] = "AIDE"
            if i % 2 == 0:
                tokens[0] = tokens[0].upper()
            text = "###" + separators[(i - 1) % len(separators)].join(tokens) + "???"
            score = 0.03 * count + (0.19 if has_ai else 0.0) + secrets.randbelow(20000) / 100000.0
            rows.append((str(i), text, f"{score:.6f}"))

        with open(DATA_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "text", "engagement_score"])
            writer.writerows(rows)

        expected = oracle(rows)
        challenge_data = run_analyzer()
        assert_matches(challenge_data, expected)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_csv)
        if original_stats is not None:
            with open(JSON_PATH, "wb") as f:
                f.write(original_stats)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
