#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /home/user/data/train.csv /tmp/original_train.csv
cp /home/user/data/test.csv /tmp/original_test.csv
restore_data() {
    cp /tmp/original_train.csv /home/user/data/train.csv
    cp /tmp/original_test.csv /home/user/data/test.csv
}
trap restore_data EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import secrets
import subprocess
from collections import Counter
from fractions import Fraction

import pytest

PROGRAM = "/home/user/organizer.go"
BINARY = "/tmp/organizer_submission"
RECOMMENDATIONS = "/home/user/recommendations.csv"
LOG = "/home/user/experiment_log.jsonl"


def run_program():
    for path in (RECOMMENDATIONS, LOG):
        if os.path.exists(path):
            os.remove(path)
    subprocess.run([BINARY], cwd="/home/user", check=True, timeout=20)


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_original():
    assert os.path.isfile(PROGRAM), "The Go program /home/user/organizer.go is missing."
    subprocess.run(
        ["go", "build", "-o", BINARY, PROGRAM],
        cwd="/home/user",
        check=True,
        timeout=30,
    )
    assert os.path.isfile(BINARY), "organizer.go did not compile to an executable."
    run_program()


def test_go_file_exists():
    assert os.path.isfile("/home/user/organizer.go"), "The Go program /home/user/organizer.go is missing."


def test_recommendations_csv():
    file_path = "/home/user/recommendations.csv"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 3, "recommendations.csv does not have enough rows."

    header = lines[0]
    assert header == "test_id,sim_1,sim_2,sim_3", f"Incorrect header in recommendations.csv: {header}"

    q1_row = lines[1]
    q2_row = lines[2]

    assert q1_row == "q1,t2,t1,t5", f"Incorrect recommendations for q1: {q1_row}"
    assert q2_row == "q2,t3,t4,t2", f"Incorrect recommendations for q2: {q2_row}"


def test_experiment_log_jsonl():
    file_path = "/home/user/experiment_log.jsonl"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 1, "experiment_log.jsonl is empty."

    last_log = lines[-1]
    try:
        data = json.loads(last_log)
    except json.JSONDecodeError:
        pytest.fail("The last line of experiment_log.jsonl is not valid JSON.")

    assert "k" in data, "Key 'k' is missing in experiment_log.jsonl."
    assert data["k"] == 3, f"Expected k=3, got {data['k']}"

    assert "accuracy" in data, "Key 'accuracy' is missing in experiment_log.jsonl."
    assert float(data["accuracy"]) == 1.0, f"Expected accuracy=1.0, got {data['accuracy']}"

    assert "throughput_qps" in data, "Key 'throughput_qps' is missing in experiment_log.jsonl."
    assert isinstance(data["throughput_qps"], (int, float)), "throughput_qps must be a number."
    assert data["throughput_qps"] > 0, "throughput_qps must be greater than 0."


def tokenize(text):
    return set(text.lower().replace(",", "").replace(".", "").split(" "))


def expected_results(train_rows, test_rows):
    expected_recs = {}
    correct = 0
    prepared = [(row[0], row[1], tokenize(row[2])) for row in train_rows]

    for test_id, true_category, abstract in test_rows:
        words = tokenize(abstract)
        scored = []
        for train_id, category, train_words in prepared:
            intersection = len(words & train_words)
            union = len(words | train_words)
            similarity = Fraction(intersection, union) if union else Fraction(0, 1)
            scored.append((train_id, category, similarity))

        scored.sort(key=lambda item: (-item[2], item[0]))
        neighbors = scored[:3]
        expected_recs[test_id] = [item[0] for item in neighbors]

        counts = Counter(item[1] for item in neighbors)
        max_count = max(counts.values())
        tied_categories = {category for category, count in counts.items() if count == max_count}
        predicted = next(item[1] for item in neighbors if item[1] in tied_categories)
        if predicted == true_category:
            correct += 1

    return expected_recs, correct / len(test_rows)


def decorated(words):
    rendered = []
    for index, word in enumerate(words):
        value = word.upper() if index % 2 == 0 else word
        if index % 3 == 0:
            value += ","
        elif index % 3 == 1:
            value += "."
        rendered.append(value)
    return " ".join(rendered)


def read_dynamic_outputs(expected_recs, expected_accuracy):
    assert os.path.isfile(RECOMMENDATIONS), "Program did not generate recommendations.csv."
    with open(RECOMMENDATIONS, newline="") as handle:
        rows = list(csv.reader(handle))
    assert rows and rows[0] == ["test_id", "sim_1", "sim_2", "sim_3"]
    assert len(rows) == len(expected_recs) + 1
    actual = {}
    for row in rows[1:]:
        assert len(row) == 4
        assert row[0] not in actual, f"Duplicate recommendation row for {row[0]}"
        actual[row[0]] = row[1:]
    assert actual == expected_recs

    assert os.path.isfile(LOG), "Program did not generate experiment_log.jsonl."
    with open(LOG) as handle:
        lines = [line.strip() for line in handle if line.strip()]
    assert lines, "experiment_log.jsonl is empty after execution."
    data = json.loads(lines[-1])
    assert data.get("k") == 3
    assert isinstance(data.get("accuracy"), (int, float))
    assert math.isclose(float(data["accuracy"]), expected_accuracy, rel_tol=0, abs_tol=1e-9)
    assert isinstance(data.get("throughput_qps"), (int, float))
    assert math.isfinite(float(data["throughput_qps"]))
    assert float(data["throughput_qps"]) > 0


def test_z_program_on_unseen_datasets():
    for _ in range(3):
        nonce = secrets.token_hex(6)
        word = {name: f"{name}{nonce}" for name in "abcdmnopqrstuvxyz"}
        category_a = f"alpha_{nonce}"
        category_b = f"beta_{nonce}"
        category_c = f"gamma_{nonce}"
        prefix = f"r{nonce}"

        train_specs = [
            (prefix + "01", category_a, [word["a"], word["b"], word["c"], word["d"]]),
            (prefix + "02", category_b, [word["a"], word["b"], word["c"], word["x"]]),
            (prefix + "03", category_b, [word["a"], word["b"], word["y"], word["z"]]),
            (prefix + "04", category_a, [word["m"], word["n"], word["o"], word["p"]]),
            (prefix + "05", category_b, [word["m"], word["n"], word["x"], word["q"]]),
            (prefix + "06", category_c, [word["m"], word["y"], word["r"], word["s"]]),
            (prefix + "07", category_c, [word["a"], word["m"], word["u"], word["v"]]),
        ]
        random.SystemRandom().shuffle(train_specs)
        train_rows = [(paper_id, category, decorated(words)) for paper_id, category, words in train_specs]

        test_specs = [
            (f"q{nonce}1", [word["a"], word["b"], word["c"]]),
            (f"q{nonce}2", [word["m"], word["n"], word["o"]]),
            (f"q{nonce}3", [word["a"], word["m"]]),
        ]
        categories = [category_a, category_b, category_c]
        test_rows = [
            (paper_id, secrets.choice(categories), decorated(words))
            for paper_id, words in test_specs
        ]
        random.SystemRandom().shuffle(test_rows)

        with open("/home/user/data/train.csv", "w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["id", "category", "abstract"])
            writer.writerows(train_rows)
        with open("/home/user/data/test.csv", "w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["id", "category", "abstract"])
            writer.writerows(test_rows)

        expected_recs, expected_accuracy = expected_results(train_rows, test_rows)
        run_program()
        read_dynamic_outputs(expected_recs, expected_accuracy)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
