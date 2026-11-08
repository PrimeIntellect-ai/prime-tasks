#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_deadlock_file_exists():
    file_path = "/home/user/deadlock.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist. You must create it to store the result."
    assert os.path.isfile(file_path), f"Path {file_path} must be a regular file."

def test_deadlock_content():
    held_locks_path = "/home/user/held_locks.csv"
    waiting_locks_path = "/home/user/waiting_locks.csv"

    assert os.path.exists(held_locks_path), "Original held_locks.csv is missing."
    assert os.path.exists(waiting_locks_path), "Original waiting_locks.csv is missing."

    # Parse held locks: table_name -> pid
    held_by = {}
    with open(held_locks_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            held_by[row["table_name"]] = row["pid"]

    # Parse waiting locks: pid -> table_name -> holding pid
    wait_for = {}
    with open(waiting_locks_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["table_name"] in held_by:
                wait_for[row["pid"]] = held_by[row["table_name"]]

    # Find the cycle
    visited = set()
    cycle = []
    for node in wait_for:
        if node in visited:
            continue

        curr = node
        curr_path = []

        while curr and curr not in visited:
            visited.add(curr)
            curr_path.append(curr)
            curr = wait_for.get(curr)

        if curr in curr_path:
            # Cycle detected
            idx = curr_path.index(curr)
            cycle = curr_path[idx:]
            break

    assert cycle, "Could not find a cycle in the provided CSV data. The test setup might be corrupted."

    # Format the cycle according to rules
    min_pid = min(cycle, key=int)
    min_idx = cycle.index(min_pid)
    ordered_cycle = cycle[min_idx:] + cycle[:min_idx]
    expected_result = ",".join(ordered_cycle)

    # Read user output
    with open("/home/user/deadlock.txt", "r") as f:
        actual_result = f.read().strip()

    assert actual_result == expected_result, (
        f"The deadlock sequence is incorrect.\n"
        f"Expected: {expected_result}\n"
        f"Actual:   {actual_result}\n"
        "Ensure you start with the lowest PID, follow the wait-for edges, and do not repeat the starting PID."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
