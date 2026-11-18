#!/bin/bash
set -u
mkdir -p /logs/verifier

PROJECT=/home/user/network_analyzer
OUTPUT=/home/user/department_influence.json
TMPDIR_VERIFY=$(mktemp -d)
ok=1

if ! cp /home/user/users.csv "$TMPDIR_VERIFY/users.csv" || \
   ! cp /home/user/interactions.csv "$TMPDIR_VERIFY/interactions.csv"; then
    ok=0
fi

restore_state() {
    if [ -f "$TMPDIR_VERIFY/users.csv" ]; then
        cp "$TMPDIR_VERIFY/users.csv" /home/user/users.csv
    fi
    if [ -f "$TMPDIR_VERIFY/interactions.csv" ]; then
        cp "$TMPDIR_VERIFY/interactions.csv" /home/user/interactions.csv
    fi
    if [ -f "$TMPDIR_VERIFY/department_influence.json" ]; then
        cp "$TMPDIR_VERIFY/department_influence.json" "$OUTPUT"
    fi
    rm -rf "$TMPDIR_VERIFY"
}
trap restore_state EXIT

# Require an actual Cargo project with nonempty Rust source.
if [ "$ok" -eq 1 ]; then
    if [ ! -d "$PROJECT" ] || [ ! -f "$PROJECT/Cargo.toml" ]; then
        ok=0
    elif ! find "$PROJECT" -path "$PROJECT/target" -prune -o -type f -name '*.rs' -size +0c -print -quit | grep -q .; then
        ok=0
    fi
fi

# Remove any prewritten answer and require the Rust application to regenerate it.
if [ "$ok" -eq 1 ]; then
    rm -f "$OUTPUT"
    if ! (cd "$PROJECT" && timeout 180 cargo run --quiet); then
        ok=0
    elif [ ! -f "$OUTPUT" ]; then
        ok=0
    else
        cp "$OUTPUT" "$TMPDIR_VERIFY/department_influence.json" || ok=0
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess
import pytest

PROJECT = "/home/user/network_analyzer"
OUTPUT = "/home/user/department_influence.json"
USERS = "/home/user/users.csv"
INTERACTIONS = "/home/user/interactions.csv"


def test_department_influence_json_exists():
    path = "/home/user/department_influence.json"
    assert os.path.isfile(path), f"Output file {path} is missing."


def test_department_influence_json_content():
    path = "/home/user/department_influence.json"
    assert os.path.isfile(path), f"Output file {path} is missing."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    assert isinstance(data, list), f"JSON data in {path} must be a list (array)."

    expected_data = [
        {"department": "Engineering", "total_in_degree": 9},
        {"department": "HR", "total_in_degree": 0},
        {"department": "Marketing", "total_in_degree": 3},
        {"department": "Sales", "total_in_degree": 2}
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} departments, but got {len(data)}."

    for i, expected_item in enumerate(expected_data):
        actual_item = data[i]
        assert "department" in actual_item, f"Missing 'department' key in item {i}."
        assert "total_in_degree" in actual_item, f"Missing 'total_in_degree' key in item {i}."

        assert actual_item["department"] == expected_item["department"], \
            f"Expected department '{expected_item['department']}' at index {i}, but got '{actual_item['department']}'. Ensure the list is sorted alphabetically."
        assert actual_item["total_in_degree"] == expected_item["total_in_degree"], \
            f"Expected total_in_degree {expected_item['total_in_degree']} for department '{expected_item['department']}', but got {actual_item['total_in_degree']}."


def test_json_formatting():
    path = "/home/user/department_influence.json"
    assert os.path.isfile(path), f"Output file {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Check for basic 2-space indentation formatting as requested
    assert "[\n  {\n" in content or "[\r\n  {\r\n" in content, "JSON file does not appear to be formatted with 2-space indentation."


def test_program_processes_unseen_dataset():
    original_users = open(USERS, "rb").read()
    original_interactions = open(INTERACTIONS, "rb").read()

    token = secrets.token_hex(5)
    departments = [f"Alpha_{token}", f"Delta_{token}", f"Omega_{token}", f"Sigma_{token}"]
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    user_ids = rng.sample(range(101, 5000), 11)
    users = [
        (uid, departments[i % len(departments)], f"Person_{token}_{i}")
        for i, uid in enumerate(user_ids)
    ]

    # Use repeated directed edges and leave the final two users with zero in-degree.
    edges = [(rng.choice(user_ids), rng.choice(user_ids[:-2])) for _ in range(43)]
    edges.extend([(user_ids[0], user_ids[1])] * 4)

    department_for_id = {uid: department for uid, department, _ in users}
    totals = {department: 0 for department in departments}
    for _, target in edges:
        totals[department_for_id[target]] += 1
    expected = [
        {"department": department, "total_in_degree": totals[department]}
        for department in sorted(totals)
    ]

    try:
        with open(USERS, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["user_id", "department", "name"])
            writer.writerows(users)
        with open(INTERACTIONS, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["source_id", "target_id"])
            writer.writerows(edges)

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        result = subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, f"Rust application failed on an unseen dataset:\n{result.stderr}"
        assert os.path.isfile(OUTPUT), "Rust application did not regenerate the output file."

        with open(OUTPUT, "r") as f:
            actual = json.load(f)
        assert actual == expected, f"Incorrect aggregation for unseen input: expected {expected}, got {actual}"

        with open(OUTPUT, "r") as f:
            content = f.read()
        assert "[\n  {\n" in content or "[\r\n  {\r\n" in content, \
            "Generated JSON does not use the requested 2-space indentation."
    finally:
        with open(USERS, "wb") as f:
            f.write(original_users)
        with open(INTERACTIONS, "wb") as f:
            f.write(original_interactions)
TEST_EOF

if [ "$ok" -eq 1 ]; then
    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        ok=1
    else
        ok=0
    fi
fi

echo "$ok" > /logs/verifier/reward.txt
exit 0
