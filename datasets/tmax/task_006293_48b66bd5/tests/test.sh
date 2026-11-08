#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import secrets

SCRIPT_PATH = "/home/user/pipeline.sh"
RATINGS_PATH = "/home/user/ratings.csv"
TRAIN_OUT = "/home/user/train_features.csv"
TEST_OUT = "/home/user/test_features.csv"


def remove_outputs():
    for path in (TRAIN_OUT, TEST_OUT):
        if os.path.lexists(path):
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)
            else:
                raise AssertionError(f"Output path {path} is not a regular file.")


def execute_pipeline():
    remove_outputs()
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Execution of {SCRIPT_PATH} failed:\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def validate_outputs():
    assert os.path.exists(RATINGS_PATH), f"Input file {RATINGS_PATH} is missing."
    assert os.path.exists(TRAIN_OUT), f"Output file {TRAIN_OUT} was not created."
    assert os.path.exists(TEST_OUT), f"Output file {TEST_OUT} was not created."
    assert os.path.isfile(TRAIN_OUT), f"{TRAIN_OUT} is not a file."
    assert os.path.isfile(TEST_OUT), f"{TEST_OUT} is not a file."

    with open(RATINGS_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    header = lines[0]
    assert header == "user_id,item_id,rating,timestamp", "Unexpected header in ratings.csv"

    train_rows = []
    test_rows = []
    for line in lines[1:]:
        parts = line.split(",")
        if len(parts) != 4:
            continue
        user_id, item_id, rating_str, timestamp_str = parts
        rating = float(rating_str)
        timestamp = int(timestamp_str)
        row = (user_id, item_id, rating, timestamp, line)
        if timestamp <= 1620000000:
            train_rows.append(row)
        else:
            test_rows.append(row)

    train_ratings = [r[2] for r in train_rows]
    global_mean = sum(train_ratings) / len(train_ratings) if train_ratings else 0.0

    item_stats = {}
    for row in train_rows:
        item_stats.setdefault(row[1], []).append(row[2])
    item_means = {
        item: sum(ratings) / len(ratings)
        for item, ratings in item_stats.items()
    }

    expected_header = header + ",item_mean"
    expected_train_lines = [
        f"{row[4]},{item_means[row[1]]:.2f}" for row in train_rows
    ]
    expected_test_lines = [
        f"{row[4]},{item_means.get(row[1], global_mean):.2f}" for row in test_rows
    ]

    with open(TRAIN_OUT, "r") as f:
        actual_train = [line.strip() for line in f if line.strip()]
    with open(TEST_OUT, "r") as f:
        actual_test = [line.strip() for line in f if line.strip()]

    assert len(actual_train) > 0, f"{TRAIN_OUT} is empty."
    assert actual_train[0] == expected_header, (
        f"Header in {TRAIN_OUT} is incorrect. Expected: {expected_header}, "
        f"Got: {actual_train[0]}"
    )
    assert len(actual_test) > 0, f"{TEST_OUT} is empty."
    assert actual_test[0] == expected_header, (
        f"Header in {TEST_OUT} is incorrect. Expected: {expected_header}, "
        f"Got: {actual_test[0]}"
    )

    actual_train_set = set(actual_train[1:])
    expected_train_set = set(expected_train_lines)
    assert actual_train_set == expected_train_set, (
        f"Content of {TRAIN_OUT} does not match expected train features."
    )
    actual_test_set = set(actual_test[1:])
    expected_test_set = set(expected_test_lines)
    assert actual_test_set == expected_test_set, (
        f"Content of {TEST_OUT} does not match expected test features."
    )

    assert len(actual_train[1:]) == len(expected_train_lines), (
        f"{TRAIN_OUT} has an incorrect number of data rows."
    )
    assert len(actual_test[1:]) == len(expected_test_lines), (
        f"{TEST_OUT} has an incorrect number of data rows."
    )


def test_pipeline_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_pipeline_output_files_and_changed_input():
    assert os.path.exists(RATINGS_PATH), f"Input file {RATINGS_PATH} is missing."

    with open(RATINGS_PATH, "rb") as f:
        original_ratings = f.read()

    try:
        # Always execute the submitted artifact, even if the agent pre-created outputs.
        execute_pipeline()
        validate_outputs()

        # Replace the fixed fixture with an unpredictable valid dataset and execute again.
        # This exercises the timestamp boundary, train-only item means, existing test
        # items, and cold-start fallback to the global training mean.
        suffix = secrets.token_hex(6)
        users = [f"user_{suffix}_{n}" for n in range(1, 9)]
        item_a = f"item_A_{suffix}"
        item_b = f"item_B_{suffix}"
        cold_item = f"cold_{suffix}"
        ratings = secrets.SystemRandom().sample([1, 2, 3, 4, 5], 4)

        changed_rows = [
            f"{users[0]},{item_a},{ratings[0]},1611111111",
            f"{users[1]},{item_b},{ratings[1]},1620000000",
            f"{users[2]},{item_a},{ratings[2]},1617777777",
            f"{users[3]},{item_b},{ratings[3]},1618888888",
            f"{users[4]},{item_a},5,1620000001",
            f"{users[5]},{cold_item},1,1623456789",
            f"{users[6]},{item_b},2,1630000000",
        ]
        changed_csv = (
            "user_id,item_id,rating,timestamp\n"
            + "\n".join(changed_rows)
            + "\n"
        )
        with open(RATINGS_PATH, "w") as f:
            f.write(changed_csv)

        execute_pipeline()
        validate_outputs()
    finally:
        with open(RATINGS_PATH, "wb") as f:
            f.write(original_ratings)
        # Restore outputs for the original input as a courtesy to the final state.
        try:
            execute_pipeline()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
