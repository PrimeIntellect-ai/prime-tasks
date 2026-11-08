#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
from fractions import Fraction

CPP_FILE = "/home/user/prepare_data.cpp"
INPUT_FILE = "/home/user/interactions.csv"
OUTPUT_FILE = "/home/user/training_pairs.csv"
EXECUTABLE = "/tmp/prepare_data_test"

ORIGINAL_INPUT = """user_id,item_category,clicks,impressions
1,CatA,5,10
1,CatB,1,5
2,CatA,6,10
2,CatC,1,2
3,CatB,10,20
3,CatC,5,10
4,CatA,0,0
"""


def write_input(text):
    with open(INPUT_FILE, "w", newline="") as f:
        f.write(text)


def run_program():
    subprocess.run([EXECUTABLE], check=True, timeout=10)


def setup_module():
    assert os.path.isfile(CPP_FILE), f"Expected C++ source file missing at {CPP_FILE}"
    subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_FILE, "-o", EXECUTABLE],
        check=True,
        timeout=30,
    )
    write_input(ORIGINAL_INPUT)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    run_program()


def test_prepare_data_cpp_exists():
    cpp_file = "/home/user/prepare_data.cpp"
    assert os.path.isfile(cpp_file), f"Expected C++ source file missing at {cpp_file}"


def test_training_pairs_csv_content():
    output_file = "/home/user/training_pairs.csv"
    assert os.path.isfile(output_file), f"Expected output file missing at {output_file}"

    expected_pairs = [
        {"user_id": "1", "similar_user_id": "2"},
        {"user_id": "2", "similar_user_id": "1"},
        {"user_id": "3", "similar_user_id": "4"},
        {"user_id": "4", "similar_user_id": "1"},
    ]

    with open(output_file, "r") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["user_id", "similar_user_id"], "CSV header is incorrect"
        actual_pairs = list(reader)

    assert len(actual_pairs) == len(expected_pairs), f"Expected {len(expected_pairs)} rows, but got {len(actual_pairs)}"

    for i, (actual, expected) in enumerate(zip(actual_pairs, expected_pairs)):
        assert actual["user_id"] == expected["user_id"], f"Row {i+1} user_id mismatch: expected {expected['user_id']}, got {actual['user_id']}"
        assert actual["similar_user_id"] == expected["similar_user_id"], f"Row {i+1} similar_user_id mismatch for user {actual['user_id']}: expected {expected['similar_user_id']}, got {actual['similar_user_id']}"


def oracle(rows):
    categories = ("CatA", "CatB", "CatC")
    users = sorted({row[0] for row in rows})
    values = {(uid, category): (0, 0) for uid in users for category in categories}
    for uid, category, clicks, impressions in rows:
        values[(uid, category)] = (clicks, impressions)

    vectors = {}
    for uid in users:
        vectors[uid] = [
            Fraction(2 + values[(uid, category)][0], 12 + values[(uid, category)][1])
            for category in categories
        ]

    result = []
    for uid in users:
        candidates = []
        for other in users:
            if other == uid:
                continue
            distance_squared = sum(
                (a - b) * (a - b) for a, b in zip(vectors[uid], vectors[other])
            )
            candidates.append((distance_squared, other))
        result.append((uid, min(candidates)[1]))
    return result


def execute_case(rows):
    lines = ["user_id,item_category,clicks,impressions"]
    lines.extend(f"{uid},{category},{clicks},{impressions}" for uid, category, clicks, impressions in rows)
    write_input("\n".join(lines) + "\n")
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    run_program()
    assert os.path.isfile(OUTPUT_FILE), f"Expected output file missing at {OUTPUT_FILE}"

    with open(OUTPUT_FILE, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["user_id", "similar_user_id"], "CSV header is incorrect"
        actual = list(reader)

    expected = oracle(rows)
    assert len(actual) == len(expected)
    assert [(int(row["user_id"]), int(row["similar_user_id"])) for row in actual] == expected


def test_compiled_program_handles_ties_missing_categories_and_numeric_sorting():
    rows = [
        (901, "CatC", 0, 0),
        (17, "CatA", 0, 0),
        (105, "CatB", 0, 0),
    ]
    execute_case(rows)


def test_compiled_program_on_unseen_inputs():
    rng = secrets.SystemRandom()
    categories = ("CatA", "CatB", "CatC")

    for _ in range(5):
        user_count = rng.randint(4, 8)
        user_ids = sorted(rng.sample(range(20, 10000), user_count))
        rows = []
        for uid in user_ids:
            present = [category for category in categories if rng.random() < 0.7]
            if not present:
                present = [rng.choice(categories)]
            for category in present:
                impressions = rng.randint(0, 60)
                clicks = rng.randint(0, impressions) if impressions else 0
                rows.append((uid, category, clicks, impressions))
        rng.shuffle(rows)
        execute_case(rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
