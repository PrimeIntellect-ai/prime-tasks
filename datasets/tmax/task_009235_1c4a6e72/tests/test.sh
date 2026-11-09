#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import secrets
import subprocess

import pytest

PROGRAM = "/home/user/recommender.go"
DATASET = "/home/user/data/products.csv"
RESULTS_DIR = "/home/user/results"
BINARY = "/tmp/recommender_submission"


def test_recommender_go_exists():
    file_path = "/home/user/recommender.go"
    assert os.path.isfile(file_path), f"The Go program {file_path} does not exist."


def test_results_json_exists_and_correct():
    file_path = "/home/user/results/run_exp_beta_01.json"
    assert os.path.isfile(file_path), f"The results file {file_path} does not exist. Did you run the program with the correct arguments?"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_run_id = "exp_beta_01"
    expected_target_id = 3
    expected_recommended_id = 1
    expected_score = 0.5

    assert "run_id" in data, "Key 'run_id' is missing from the JSON output."
    assert data["run_id"] == expected_run_id, f"Expected run_id '{expected_run_id}', but got '{data['run_id']}'."

    assert "target_id" in data, "Key 'target_id' is missing from the JSON output."
    assert data["target_id"] == expected_target_id, f"Expected target_id {expected_target_id}, but got {data['target_id']}."

    assert "recommended_id" in data, "Key 'recommended_id' is missing from the JSON output."
    assert data["recommended_id"] == expected_recommended_id, f"Expected recommended_id {expected_recommended_id}, but got {data['recommended_id']}."

    assert "similarity_score" in data, "Key 'similarity_score' is missing from the JSON output."
    assert isinstance(data["similarity_score"], (int, float)), "similarity_score must be a number."
    assert math.isclose(data["similarity_score"], expected_score, rel_tol=1e-5), f"Expected similarity_score {expected_score}, but got {data['similarity_score']}."


def valid_products(rows):
    products = []
    for row in rows:
        if len(row) != 3:
            continue
        raw_id, name, tags = row
        try:
            product_id = int(raw_id)
        except ValueError:
            continue
        if name == "" or tags == "":
            continue
        products.append((product_id, set(tags.split())))
    return products


def expected_recommendation(rows, target_id):
    products = valid_products(rows)
    target_tags = next(tags for product_id, tags in products if product_id == target_id)
    candidates = []
    for product_id, tags in products:
        if product_id == target_id:
            continue
        union = target_tags | tags
        score = len(target_tags & tags) / len(union)
        candidates.append((score, product_id))
    best_score = max(score for score, _ in candidates)
    best_id = min(product_id for score, product_id in candidates if score == best_score)
    return best_id, best_score


def test_program_compiles_and_executes_on_dynamic_input():
    build = subprocess.run(
        ["go", "build", "-o", BINARY, PROGRAM],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert build.returncode == 0, f"recommender.go did not compile:\n{build.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    original_dataset = open(DATASET, "rb").read()
    token = secrets.token_hex(6)
    run_id = "verify_" + token
    output_path = os.path.join(RESULTS_DIR, f"run_{run_id}.json")

    ids = random.SystemRandom().sample(range(1000, 9000), 5)
    target_id, candidate_a, candidate_b, unrelated_id, empty_tags_id = ids
    low_candidate, high_candidate = sorted((candidate_a, candidate_b))
    tags = [f"tag_{token}_{i}" for i in range(6)]

    rows = [
        [str(target_id), "Dynamic target", f"{tags[0]} {tags[1]} {tags[2]} {tags[0]}"],
        [str(low_candidate), "Tie candidate low", f"{tags[0]} {tags[1]} {tags[3]}"],
        [str(high_candidate), "Tie candidate high", f"{tags[0]} {tags[2]} {tags[4]}"],
        [str(unrelated_id), "Unrelated", tags[5]],
        [str(min(ids) - 1), "", f"{tags[0]} {tags[1]} {tags[2]}"],
        ["not_an_integer_" + token, "Bad identifier", f"{tags[0]} {tags[1]} {tags[2]}"],
        [str(empty_tags_id), "Empty tags", ""],
    ]
    random.SystemRandom().shuffle(rows)
    expected_id, expected_score = expected_recommendation(rows, target_id)

    try:
        with open(DATASET, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "product_name", "tags"])
            writer.writerows(rows)

        if os.path.exists(output_path):
            os.remove(output_path)

        execution = subprocess.run(
            [BINARY, "-target", str(target_id), "-run", run_id],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert execution.returncode == 0, f"Compiled program failed:\n{execution.stderr}"
        assert os.path.isfile(output_path), f"Program did not create {output_path}"

        with open(output_path) as f:
            result = json.load(f)

        assert set(result) == {"run_id", "target_id", "recommended_id", "similarity_score"}
        assert result["run_id"] == run_id
        assert result["target_id"] == target_id
        assert result["recommended_id"] == expected_id
        assert isinstance(result["similarity_score"], (int, float)) and not isinstance(result["similarity_score"], bool)
        assert math.isclose(result["similarity_score"], expected_score, rel_tol=1e-9, abs_tol=1e-12)
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
        if os.path.exists(output_path):
            os.remove(output_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
