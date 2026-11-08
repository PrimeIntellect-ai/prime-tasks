#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import subprocess

EVALUATE = "/home/user/evaluate.go"
MATCHES = "/home/user/matches.json"
BASELINE = "/home/user/artifacts/baseline.csv"
EXPERIMENTS = "/home/user/artifacts/experiments.csv"


def run_evaluator():
    result = subprocess.run(
        ["go", "run", EVALUATE],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"evaluate.go failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(MATCHES), f"{MATCHES} output file not found."


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    assert norm_a != 0 and norm_b != 0
    return dot / (norm_a * norm_b)


def standard_round_4(value):
    # Generated similarities are positive and deliberately avoid half-way cases.
    return math.floor(value * 10000.0 + 0.5) / 10000.0


def expected_results(baselines, experiments):
    results = []
    for exp_id, exp_vector in experiments:
        best_id = None
        best_similarity = -math.inf
        for baseline_id, baseline_vector in baselines:
            similarity = cosine(exp_vector, baseline_vector)
            if similarity > best_similarity:
                best_id = baseline_id
                best_similarity = similarity
        results.append({
            "exp_id": exp_id,
            "closest_baseline_id": best_id,
            "similarity": standard_round_4(best_similarity),
        })
    return sorted(results, key=lambda item: item["exp_id"])


def load_matches():
    assert os.path.isfile(MATCHES), f"{MATCHES} does not exist."
    with open(MATCHES, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            assert False, f"{MATCHES} contains invalid JSON: {exc}"
    assert isinstance(data, list), "JSON output must be an array."
    return data


def verify_results(data, expected):
    assert len(data) == len(expected), (
        f"Expected {len(expected)} items in JSON array, but got {len(data)}."
    )

    exp_ids = [item.get("exp_id") for item in data]
    assert exp_ids == sorted(exp_ids), "JSON array is not sorted alphabetically by exp_id."

    for item in data:
        assert isinstance(item, dict), "Each JSON array item must be an object."
        assert set(item.keys()) == {"exp_id", "closest_baseline_id", "similarity"}, (
            "Each result object must contain exactly exp_id, closest_baseline_id, and similarity."
        )

    for expected_item in expected:
        actual_item = next(
            (item for item in data if item.get("exp_id") == expected_item["exp_id"]),
            None,
        )
        assert actual_item is not None, (
            f"Missing result for experiment {expected_item['exp_id']}."
        )
        assert actual_item.get("closest_baseline_id") == expected_item["closest_baseline_id"], (
            f"Incorrect closest_baseline_id for {expected_item['exp_id']}. "
            f"Expected {expected_item['closest_baseline_id']}, "
            f"got {actual_item.get('closest_baseline_id')}."
        )
        actual_similarity = actual_item.get("similarity")
        assert isinstance(actual_similarity, (int, float)) and not isinstance(actual_similarity, bool), (
            f"Similarity for {expected_item['exp_id']} must be a number."
        )
        assert math.isclose(
            actual_similarity,
            expected_item["similarity"],
            rel_tol=0.0,
            abs_tol=1e-12,
        ), (
            f"Incorrect similarity for {expected_item['exp_id']}. "
            f"Expected {expected_item['similarity']}, got {actual_similarity}."
        )


def write_fixture(path, header, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        for row_id, vector in rows:
            writer.writerow([row_id] + [format(value, ".12g") for value in vector])


def test_evaluate_go_exists():
    assert os.path.isfile(EVALUATE), "/home/user/evaluate.go script not found."


def test_matches_json_exists():
    assert os.path.isfile(MATCHES), "/home/user/matches.json output file not found."


def test_matches_json_content_and_program_behavior():
    original_baseline = open(BASELINE, "rb").read()
    original_experiments = open(EXPERIMENTS, "rb").read()

    original_baselines = [
        ("base1", [1.0, 0.0, 0.0, 0.0]),
        ("base2", [0.0, 1.0, 0.0, 0.0]),
        ("base3", [0.7071, 0.7071, 0.0, 0.0]),
        ("base4", [0.5, 0.5, 0.5, 0.5]),
    ]
    original_experiments = [
        ("expA", [0.99, 0.05, 0.0, 0.0]),
        ("expB", [0.0, 0.95, 0.1, 0.0]),
        ("expC", [0.70, 0.71, 0.05, 0.0]),
        ("expD", [0.48, 0.51, 0.49, 0.52]),
    ]

    # Execute the submitted Go source rather than trusting a pre-created JSON file.
    run_evaluator()
    original_data = load_matches()
    verify_results(original_data, expected_results(original_baselines, original_experiments))

    # Preserve the original verifier's explicit assertions, correcting expD's value.
    fixed_expected = [
        {"exp_id": "expA", "closest_baseline_id": "base1", "similarity": 0.9987},
        {"exp_id": "expB", "closest_baseline_id": "base2", "similarity": 0.9945},
        {"exp_id": "expC", "closest_baseline_id": "base3", "similarity": 0.9988},
        {"exp_id": "expD", "closest_baseline_id": "base4", "similarity": 0.9995},
    ]
    for expected_item in fixed_expected:
        actual_item = next(
            item for item in original_data if item.get("exp_id") == expected_item["exp_id"]
        )
        assert actual_item.get("closest_baseline_id") == expected_item["closest_baseline_id"]
        assert math.isclose(
            actual_item.get("similarity"),
            expected_item["similarity"],
            abs_tol=1e-4,
        )

    rng = random.SystemRandom()
    nonce = os.urandom(6).hex()

    baselines = []
    while len(baselines) < 6:
        vector = [rng.uniform(-1.0, 1.0) for _ in range(4)]
        norm = math.sqrt(sum(value * value for value in vector))
        if norm < 0.3:
            continue
        vector = [value / norm for value in vector]
        if any(abs(cosine(vector, prior)) > 0.82 for _, prior in baselines):
            continue
        baselines.append((f"b_{nonce}_{len(baselines)}", vector))

    experiments = []
    for index in range(9):
        target = baselines[index % len(baselines)][1]
        vector = [value + rng.uniform(-0.06, 0.06) for value in target]
        experiments.append((f"x_{nonce}_{8-index:02d}", vector))

    rng.shuffle(baselines)
    rng.shuffle(experiments)
    dynamic_expected = expected_results(baselines, experiments)

    try:
        write_fixture(BASELINE, ["id", "val1", "val2", "val3", "val4"], baselines)
        write_fixture(EXPERIMENTS, ["exp_id", "val1", "val2", "val3", "val4"], experiments)
        # Recompute expectations from the exact decimal values written to CSV.
        def reparsed(rows):
            return [(row_id, [float(format(v, ".12g")) for v in vector]) for row_id, vector in rows]
        dynamic_expected = expected_results(reparsed(baselines), reparsed(experiments))
        if os.path.exists(MATCHES):
            os.remove(MATCHES)
        run_evaluator()
        verify_results(load_matches(), dynamic_expected)
    finally:
        with open(BASELINE, "wb") as f:
            f.write(original_baseline)
        with open(EXPERIMENTS, "wb") as f:
            f.write(original_experiments)
        # Leave matches.json generated from the instructed, original artifacts.
        run_evaluator()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
