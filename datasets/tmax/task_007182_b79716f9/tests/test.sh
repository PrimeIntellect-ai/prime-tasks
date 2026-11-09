#!/bin/bash
set -u
mkdir -p /logs/verifier

ORIGINAL_CSV=/tmp/comments.csv.original
cp /home/user/data/comments.csv "$ORIGINAL_CSV"

restore_state() {
    cp "$ORIGINAL_CSV" /home/user/data/comments.csv
    if [ -x /home/user/project_graph ]; then
        rm -f /home/user/metrics.json
        timeout 10s /home/user/project_graph >/dev/null 2>&1 || true
    fi
}
trap restore_state EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import subprocess
from collections import defaultdict

import pytest

CSV_PATH = "/home/user/data/comments.csv"
JSON_PATH = "/home/user/metrics.json"
SOURCE_PATH = "/home/user/project_graph.c"
BINARY_PATH = "/home/user/project_graph"


def expected_metrics(rows):
    thread_to_users = defaultdict(set)
    for user_id, thread_id in rows:
        thread_to_users[thread_id].add(user_id)

    edges = set()
    for users in thread_to_users.values():
        user_list = sorted(users)
        for i in range(len(user_list)):
            for j in range(i + 1, len(user_list)):
                edges.add((user_list[i], user_list[j]))

    degrees = defaultdict(int)
    for u, v in edges:
        degrees[u] += 1
        degrees[v] += 1

    expected_edges = len(edges)
    max_deg = -1
    max_user = -1
    for u in sorted(degrees.keys()):
        if degrees[u] > max_deg:
            max_deg = degrees[u]
            max_user = u

    return expected_edges, max_user


def read_rows():
    rows = []
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append((int(row["user_id"]), int(row["thread_id"])))
    return rows


def write_rows(rows):
    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["user_id", "thread_id"])
        writer.writerows(rows)


def run_and_load_metrics():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"project_graph exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_PATH), (
        "Running the compiled C program did not create /home/user/metrics.json"
    )

    try:
        with open(JSON_PATH, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail("metrics.json is not valid JSON")


def assert_metrics_for_rows(rows):
    expected_edges, expected_user = expected_metrics(rows)
    metrics = run_and_load_metrics()

    assert "total_unique_edges" in metrics, "Missing 'total_unique_edges' in metrics.json"
    assert "max_degree_user_id" in metrics, "Missing 'max_degree_user_id' in metrics.json"

    actual_edges = metrics["total_unique_edges"]
    actual_max_user = metrics["max_degree_user_id"]

    assert actual_edges == expected_edges, (
        f"Incorrect total_unique_edges: expected {expected_edges}, got {actual_edges}"
    )
    assert actual_max_user == expected_user, (
        f"Incorrect max_degree_user_id: expected {expected_user}, got {actual_max_user}"
    )


def test_source_and_compiled_artifact_exist():
    assert os.path.isfile(SOURCE_PATH), f"Missing {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, f"Empty {SOURCE_PATH}"
    assert os.path.isfile(BINARY_PATH), f"Missing compiled binary {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable"


def test_metrics_json_correctness():
    assert os.path.isfile(CSV_PATH), f"Missing {CSV_PATH}"
    rows = read_rows()
    assert_metrics_for_rows(rows)


def test_program_projects_only_shared_threads_and_deduplicates_edges():
    rows = [
        (2147483000, 7001),
        (17, 7001),
        (900000001, 7001),
        (2147483000, 7001),
        (17, 7002),
        (42, 7002),
        (17, 7003),
        (42, 7003),
        (1000000007, 7004),
        (88, 7005),
        (99, 7005),
        (88, 7006),
        (123456789, 7006),
    ]
    write_rows(rows)
    assert_metrics_for_rows(rows)


def test_program_on_runtime_generated_sparse_ids():
    rng = random.SystemRandom()
    users = rng.sample(range(100000000, 2000000000), 70)
    threads = rng.sample(range(10000, 1000000), 24)

    rows = []
    for user in users:
        for thread in rng.sample(threads, rng.randint(1, 4)):
            rows.append((user, thread))

    # Include duplicate comments, which must not duplicate graph edges.
    for row in rng.sample(rows, min(25, len(rows))):
        rows.append(row)
    rng.shuffle(rows)

    write_rows(rows)
    assert_metrics_for_rows(rows)
TEST_EOF

status=0
if ! gcc -O2 /home/user/project_graph.c -o /home/user/project_graph; then
    status=1
elif ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    status=1
fi

restore_state
trap - EXIT

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
