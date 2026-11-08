#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

import pytest

RAW = "/home/user/raw_costs.csv"
SOURCE = "/home/user/rollup.c"
SCRIPT = "/home/user/pipeline.sh"
OUTPUT = "/home/user/final_output.txt"

ORIGINAL_DATA = """1,0,500,Corporate
2,1,100,Engineering
3,2,50,Engineering
4,1,200,Sales
5,2,75,Engineering
6,3,10,Engineering
7,1,50,Engineering
8,7,300,Engineering
"""


def write_data(records):
    with open(RAW, "w") as f:
        for node_id, parent_id, cost, department in records:
            f.write(f"{node_id},{parent_id},{cost},{department}\n")


def expected_output(records, department, offset, limit):
    costs = {row[0]: row[2] for row in records}
    departments = {row[0]: row[3] for row in records}
    children = {row[0]: [] for row in records}
    for node_id, parent_id, _, _ in records:
        if parent_id != 0:
            children[parent_id].append(node_id)

    totals = {}
    def total(node_id):
        if node_id not in totals:
            totals[node_id] = costs[node_id] + sum(total(child) for child in children[node_id])
        return totals[node_id]

    selected = [(node_id, total(node_id)) for node_id in costs if departments[node_id] == department]
    selected.sort(key=lambda item: (-item[1], item[0]))
    selected = selected[offset:offset + limit]
    return "\n".join(f"{node_id},{value}" for node_id, value in selected)


def run(command):
    return subprocess.run(command, capture_output=True, text=True, timeout=10)


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    assert os.path.isfile(SOURCE), f"C source {SOURCE} does not exist."


def test_pipeline_execution_and_output():
    with open(RAW, "w") as f:
        f.write(ORIGINAL_DATA)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = run([SCRIPT])
    assert result.returncode == 0, f"Pipeline script failed to execute. stderr: {result.stderr}"
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created by the pipeline script."

    expected = "8,300\n2,235"
    with open(OUTPUT) as f:
        content = f.read().strip()
    assert content == expected, f"Content of {OUTPUT} is incorrect.\nExpected:\n{expected}\nGot:\n{content}"
    assert os.path.isfile("/home/user/rollup"), "Pipeline did not create /home/user/rollup."
    assert os.access("/home/user/rollup", os.X_OK), "/home/user/rollup is not executable."


def test_pipeline_uses_program_on_changed_input():
    records = [
        (1, 0, 10, "Corporate"),
        (2, 1, 100, "Engineering"),
        (3, 1, 40, "Engineering"),
        (4, 2, 25, "Engineering"),
        (5, 0, 500, "Engineering"),
        (6, 5, 100, "Sales"),
        (7, 0, 60, "Engineering"),
    ]
    try:
        write_data(records)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        result = run([SCRIPT])
        assert result.returncode == 0, f"Pipeline failed on valid changed input: {result.stderr}"
        assert os.path.isfile(OUTPUT), "Pipeline did not recreate final_output.txt."
        with open(OUTPUT) as f:
            actual = f.read().strip()
        expected = expected_output(records, "Engineering", 1, 2)
        assert actual == expected, f"Pipeline output was not derived from the input. Expected {expected!r}, got {actual!r}"
    finally:
        with open(RAW, "w") as f:
            f.write(ORIGINAL_DATA)


def test_rollup_compiles_and_supports_general_queries():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} does not exist."
    rng = random.SystemRandom()
    departments = ["Engineering", "Sales", "Research", "Ops"]
    records = []
    for node_id in range(1, 41):
        parent_id = 0 if node_id == 1 or rng.randrange(5) == 0 else rng.randrange(1, node_id)
        cost = rng.randrange(1, 1000)
        department = departments[rng.randrange(len(departments))]
        records.append((node_id, parent_id, cost, department))

    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "rollup")
        compiled = run(["gcc", SOURCE, "-o", executable])
        assert compiled.returncode == 0, f"rollup.c did not compile with gcc: {compiled.stderr}"

        try:
            write_data(records)
            queries = [(name, rng.randrange(0, 8), rng.randrange(0, 12)) for name in departments]
            queries += [("MissingDepartment", 0, 10), ("Engineering", 100, 5)]
            for department, offset, limit in queries:
                result = run([executable, department, str(offset), str(limit)])
                assert result.returncode == 0, f"rollup failed for {(department, offset, limit)}: {result.stderr}"
                expected = expected_output(records, department, offset, limit)
                assert result.stdout.strip() == expected, (
                    f"Wrong output for {(department, offset, limit)}. "
                    f"Expected {expected!r}, got {result.stdout.strip()!r}"
                )

            for args in ([], ["Engineering", "0"], ["Engineering", "0", "2", "extra"]):
                result = run([executable] + args)
                assert result.returncode != 0, f"rollup accepted invalid argument count: {args}"
        finally:
            with open(RAW, "w") as f:
                f.write(ORIGINAL_DATA)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
