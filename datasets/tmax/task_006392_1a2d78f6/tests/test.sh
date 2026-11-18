#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import sys

SCHEMA_PATH = "/home/user/schema.json"
SCRIPT_PATH = "/home/user/find_deps.py"
OUTPUT_PATH = "/home/user/users_dependencies.txt"


def compute_expected(schema):
    graph = {
        t['name']: [fk['references'] for fk in t.get('fks', [])]
        for t in schema.get('tables', [])
    }
    reverse_graph = {t: [] for t in graph}
    for table, fks in graph.items():
        for referenced in fks:
            reverse_graph.setdefault(referenced, []).append(table)

    deps = set()
    queue = reverse_graph.get('users', [])[:]
    while queue:
        curr = queue.pop(0)
        if curr not in deps:
            deps.add(curr)
            queue.extend(reverse_graph.get(curr, []))
    return sorted(deps)


def run_script():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def read_output():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist. Did you run your script?"
    assert os.path.isfile(OUTPUT_PATH), f"Expected {OUTPUT_PATH} to be a file."
    with open(OUTPUT_PATH, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_users_dependencies_output_and_script():
    assert os.path.exists(SCHEMA_PATH), f"Required file {SCHEMA_PATH} is missing."
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"Expected {SCRIPT_PATH} to be a file."

    with open(SCHEMA_PATH, 'rb') as f:
        original_schema_bytes = f.read()
    original_schema = json.loads(original_schema_bytes)
    expected_deps = compute_expected(original_schema)
    saved_valid_output = None

    try:
        # Execute the submitted artifact on the provided schema, then retain the
        # original verifier's exact comparison against dynamically computed data.
        run_script()
        with open(SCHEMA_PATH, 'rb') as f:
            assert f.read() == original_schema_bytes, "The script must not modify schema.json."
        actual_lines = read_output()
        assert actual_lines == expected_deps, (
            f"Dependencies in {OUTPUT_PATH} do not match expected output.\n"
            f"Expected: {expected_deps}\n"
            f"Actual: {actual_lines}"
        )
        with open(OUTPUT_PATH, 'rb') as f:
            saved_valid_output = f.read()

        # Use unpredictable table names and a different dependency graph so a
        # hardcoded answer for the provided schema cannot pass.
        names = ["tbl_" + secrets.token_hex(8) for _ in range(7)]
        direct, indirect, deep, branch, mixed, unrelated, unrelated_child = names
        tables = [
            {"name": "users", "fks": []},
            {"name": direct, "fks": [{"column": "owner_id", "references": "users"}]},
            {"name": indirect, "fks": [{"column": "parent_id", "references": direct}]},
            {"name": deep, "fks": [{"column": "parent_id", "references": indirect}]},
            {"name": branch, "fks": [{"column": "user_id", "references": "users"}]},
            {"name": mixed, "fks": [
                {"column": "dep_id", "references": branch},
                {"column": "other_id", "references": unrelated}
            ]},
            {"name": unrelated, "fks": []},
            {"name": unrelated_child, "fks": [{"column": "other_id", "references": unrelated}]},
        ]
        random.SystemRandom().shuffle(tables)
        test_schema = {"tables": tables}
        test_schema_bytes = json.dumps(test_schema, indent=2).encode("utf-8")
        with open(SCHEMA_PATH, 'wb') as f:
            f.write(test_schema_bytes)

        dynamic_expected = compute_expected(test_schema)
        run_script()
        with open(SCHEMA_PATH, 'rb') as f:
            assert f.read() == test_schema_bytes, "The script must not modify schema.json."
        dynamic_actual = read_output()
        assert dynamic_actual == dynamic_expected, (
            "The script did not recursively compute dependencies for a changed schema.\n"
            f"Expected: {dynamic_expected}\n"
            f"Actual: {dynamic_actual}"
        )
    finally:
        with open(SCHEMA_PATH, 'wb') as f:
            f.write(original_schema_bytes)
        if saved_valid_output is not None:
            with open(OUTPUT_PATH, 'wb') as f:
                f.write(saved_valid_output)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
