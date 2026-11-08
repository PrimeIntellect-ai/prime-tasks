#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
from collections import defaultdict
import itertools

def test_go_script_exists():
    script_path = "/home/user/project_graph.go"
    assert os.path.isfile(script_path), f"Expected Go script at {script_path} is missing."

def test_output_file_exists():
    output_path = "/home/user/output/item_item_edges.csv"
    assert os.path.isfile(output_path), f"Expected output file at {output_path} is missing."

def test_output_content():
    input_path = "/home/user/data/user_item.csv"
    output_path = "/home/user/output/item_item_edges.csv"

    assert os.path.isfile(input_path), f"Input file {input_path} is missing."

    # Compute expected output
    user_items = defaultdict(set)
    with open(input_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            user, item = line.split(",")
            user_items[user].add(item)

    item_pairs = defaultdict(int)
    for user, items in user_items.items():
        # Generate all combinations of items for this user
        for item1, item2 in itertools.combinations(sorted(list(items)), 2):
            item_pairs[(item1, item2)] += 1

    expected_edges = []
    for (item1, item2), weight in item_pairs.items():
        if weight >= 2:
            expected_edges.append((item1, item2, weight))

    # Sort by weight (desc), item_1 (asc), item_2 (asc)
    expected_edges.sort(key=lambda x: (-x[2], x[0], x[1]))

    expected_lines = [f"{i1},{i2},{w}" for i1, i2, w in expected_edges]

    # Read actual output
    with open(output_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Output file content is incorrect.\nExpected:\n{chr(10).join(expected_lines)}\n\nActual:\n{chr(10).join(actual_lines)}"
TEST_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
cat << 'TEST_EOF' > /tmp/test_program_behavior.py
import itertools
import os
import secrets
import shutil
import subprocess
from collections import defaultdict

SCRIPT = "/home/user/project_graph.go"
INPUT = "/home/user/data/user_item.csv"
OUTPUT_DIR = "/home/user/output"
OUTPUT = "/home/user/output/item_item_edges.csv"


def expected_lines(rows):
    user_items = defaultdict(set)
    for user, item in rows:
        user_items[user].add(item)

    pair_weights = defaultdict(int)
    for items in user_items.values():
        for item1, item2 in itertools.combinations(sorted(items), 2):
            pair_weights[(item1, item2)] += 1

    edges = [
        (item1, item2, weight)
        for (item1, item2), weight in pair_weights.items()
        if weight >= 2
    ]
    edges.sort(key=lambda edge: (-edge[2], edge[0], edge[1]))
    return [f"{item1},{item2},{weight}" for item1, item2, weight in edges]


def run_case(rows, remove_output_directory=False):
    with open(INPUT, "w") as f:
        for user, item in rows:
            f.write(f"{user},{item}\n")

    if remove_output_directory:
        shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
    elif os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        ["go", "run", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "Go program did not create the required output file."

    with open(OUTPUT, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    expected = expected_lines(rows)
    assert actual == expected, f"Expected {expected}, but program produced {actual}"


def test_program_executes_and_handles_unseen_inputs():
    assert os.path.isfile(SCRIPT), f"Expected Go script at {SCRIPT} is missing."

    with open(INPUT, "rb") as f:
        original_input = f.read()
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

    token = secrets.token_hex(8)
    users = [f"user_{token}_{i}" for i in range(8)]
    items = [f"item_{token}_{c}" for c in "ABCDE"]

    weighted_rows = [
        (users[0], items[0]), (users[0], items[1]), (users[0], items[2]),
        (users[1], items[0]), (users[1], items[1]), (users[1], items[2]),
        (users[2], items[0]), (users[2], items[1]),
        (users[3], items[0]), (users[3], items[2]),
        (users[4], items[1]), (users[4], items[2]),
        (users[5], items[3]), (users[5], items[4]),
    ]
    duplicate_rows = [
        (users[0], items[0]), (users[0], items[0]), (users[0], items[0]),
        (users[0], items[1]), (users[0], items[1]),
        (users[1], items[2]), (users[1], items[2]), (users[1], items[3]),
        (users[2], items[2]), (users[2], items[3]), (users[2], items[3]),
        (users[3], items[0]),
    ]
    no_edges_rows = [
        (users[0], items[0]), (users[0], items[1]),
        (users[1], items[0]), (users[1], items[2]),
        (users[2], items[3]),
    ]

    try:
        run_case(weighted_rows, remove_output_directory=True)
        run_case(duplicate_rows)
        run_case(no_edges_rows)
    finally:
        os.makedirs(os.path.dirname(INPUT), exist_ok=True)
        with open(INPUT, "wb") as f:
            f.write(original_input)
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
TEST_EOF

python3 -m pytest /tmp/test_program_behavior.py -x --tb=short 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
