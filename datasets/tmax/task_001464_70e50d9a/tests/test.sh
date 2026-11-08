#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
import pytest

GO_PATH = "/home/user/optimizer.go"
PLAN_PATH = "/home/user/optimal_plan.txt"
DB_PATH = "/home/user/backup_meta.db"
EVAL_BIN = "/app/restore_eval"
BUILD_PATH = "/tmp/submitted_optimizer"


@pytest.fixture(scope="session", autouse=True)
def build_and_run_optimizer():
    """Compile and execute the submitted Go source, requiring it to create the plan."""
    assert os.path.isfile(GO_PATH), f"Go source code missing at {GO_PATH}"
    assert os.path.getsize(GO_PATH) > 0, f"Go source code is empty at {GO_PATH}"

    if os.path.lexists(PLAN_PATH):
        os.remove(PLAN_PATH)
    if os.path.lexists(BUILD_PATH):
        os.remove(BUILD_PATH)

    build = subprocess.run(
        ["go", "build", "-o", BUILD_PATH, "optimizer.go"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build.returncode == 0, (
        f"optimizer.go failed to compile. Output: {build.stdout}\nError: {build.stderr}"
    )
    assert os.path.isfile(BUILD_PATH) and os.access(BUILD_PATH, os.X_OK), (
        "Compiled optimizer executable was not created"
    )

    run = subprocess.run(
        [BUILD_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert run.returncode == 0, (
        f"Compiled optimizer failed with exit code {run.returncode}. "
        f"Output: {run.stdout}\nError: {run.stderr}"
    )
    assert os.path.isfile(PLAN_PATH), (
        f"Running optimizer.go did not create the plan at {PLAN_PATH}"
    )

    yield

    if os.path.lexists(BUILD_PATH):
        os.remove(BUILD_PATH)


def read_plan():
    with open(PLAN_PATH, "r", encoding="utf-8") as plan_file:
        lines = plan_file.read().splitlines()

    assert all(line.strip() for line in lines), "Plan contains a blank line"
    assert all(re.fullmatch(r"[+-]?\d+", line.strip()) for line in lines), (
        "Every plan line must contain exactly one integer chunk ID"
    )
    return [int(line.strip()) for line in lines]


def test_optimizer_go_exists():
    """Check if the Go source code was created."""
    assert os.path.isfile(GO_PATH), f"Go source code missing at {GO_PATH}"


def test_optimal_plan_exists():
    """Check if the optimal plan output file was created."""
    assert os.path.isfile(PLAN_PATH), f"Optimal plan missing at {PLAN_PATH}"


def test_plan_contains_each_database_chunk_exactly_once():
    sequence = read_plan()
    with sqlite3.connect(DB_PATH) as db:
        expected_ids = {row[0] for row in db.execute("SELECT id FROM chunks")}

    assert len(sequence) == len(expected_ids), (
        f"Plan has {len(sequence)} entries but the database has {len(expected_ids)} chunks"
    )
    assert len(set(sequence)) == len(sequence), "Plan contains duplicate chunk IDs"
    assert set(sequence) == expected_ids, (
        "Plan must contain exactly all chunk IDs from the chunks table"
    )


def test_plan_is_topological_sort():
    sequence = read_plan()
    positions = {chunk_id: index for index, chunk_id in enumerate(sequence)}

    with sqlite3.connect(DB_PATH) as db:
        dependencies = list(db.execute(
            "SELECT chunk_id, depends_on_id FROM dependencies"
        ))

    for chunk_id, depends_on_id in dependencies:
        assert depends_on_id in positions and chunk_id in positions, (
            f"Dependency references missing chunk: {chunk_id} depends on {depends_on_id}"
        )
        assert positions[depends_on_id] < positions[chunk_id], (
            f"Dependency violation: chunk {chunk_id} appears before dependency {depends_on_id}"
        )


def test_optimal_plan_cost():
    """Evaluate the optimal plan using the restore_eval binary and check the cost."""
    assert os.path.isfile(PLAN_PATH), f"Plan file missing at {PLAN_PATH}"
    assert os.path.isfile(EVAL_BIN), f"Evaluator binary missing at {EVAL_BIN}"

    try:
        result = subprocess.run(
            [EVAL_BIN, PLAN_PATH],
            capture_output=True,
            text=True,
            check=True,
            timeout=180,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Evaluator binary failed with exit code {e.returncode}. "
            f"Output: {e.stdout}\nError: {e.stderr}"
        )

    output = result.stdout.strip()
    try:
        cost = float(output)
    except ValueError:
        pytest.fail(f"Evaluator did not output a valid float. Output was: {output}")

    threshold = 150000.0
    assert cost <= threshold, f"Cost {cost} is too high. It must be <= {threshold}"
    assert cost < threshold, f"Cost {cost} must be strictly less than {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
