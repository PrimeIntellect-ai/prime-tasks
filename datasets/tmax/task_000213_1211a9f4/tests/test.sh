#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/backup_graph.py"
OUTPUT_PATH = "/home/user/backup_paths.json"


def run_script(script_path, cwd):
    try:
        return subprocess.run(
            ["python3", script_path],
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("backup_graph.py did not finish within 10 seconds.")


def test_script_exists_and_generates_output():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = run_script(SCRIPT_PATH, "/home/user")
    assert result.returncode == 0, (
        f"backup_graph.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "Running backup_graph.py did not generate backup_paths.json."


def test_backup_paths_json_exists():
    output_path = "/home/user/backup_paths.json"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist. Did you run the script?"
    assert os.path.isfile(output_path), f"{output_path} is not a file."


def test_backup_paths_json_content():
    output_path = "/home/user/backup_paths.json"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} does not contain valid JSON.")

    # Expected paths of length 2: A->B and B->C, sorted.
    # Edges: (1,2), (2,3), (2,4), (4,5), (1,4)
    # Paths:
    # 1->2->3
    # 1->2->4
    # 1->4->5
    # 2->4->5
    expected_data = [
        [1, 2, 3],
        [1, 2, 4],
        [1, 4, 5],
        [2, 4, 5]
    ]

    # Convert tuples to lists if necessary, but json.load already produces lists for JSON arrays.
    data_as_lists = [list(row) for row in data]

    assert data_as_lists == expected_data, f"JSON data does not match the expected paths. Expected {expected_data}, but got {data_as_lists}."


def expected_paths(edges):
    return [
        list(path)
        for path in sorted(
            (source, middle, target)
            for source, middle in edges
            for next_source, target in edges
            if middle == next_source
        )
    ]


def test_script_computes_paths_for_unseen_graphs():
    # Randomized IDs prevent a submission from passing by emitting the known fixture rows.
    for pattern in (
        [(0, 2), (2, 1), (0, 1), (1, 4), (2, 4), (5, 0)],
        [(3, 0), (0, 5), (3, 2), (2, 4), (4, 1), (0, 2)],
    ):
        base = 1000 + secrets.randbelow(1_000_000)
        ids = [base + offset for offset in (71, 13, 89, 37, 5, 53)]
        edges = [(ids[source], ids[target]) for source, target in pattern]
        expected = expected_paths(edges)

        with tempfile.TemporaryDirectory() as workdir:
            copied_script = os.path.join(workdir, "backup_graph.py")
            shutil.copy2(SCRIPT_PATH, copied_script)

            db_path = os.path.join(workdir, "graph.db")
            with sqlite3.connect(db_path) as conn:
                conn.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY)")
                conn.execute("CREATE TABLE edges (source INTEGER, target INTEGER)")
                conn.executemany("INSERT INTO nodes(id) VALUES (?)", [(node,) for node in ids])
                conn.executemany("INSERT INTO edges(source, target) VALUES (?, ?)", edges)

            result = run_script(copied_script, workdir)
            assert result.returncode == 0, (
                f"backup_graph.py failed on an unseen graph.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

            generated_path = os.path.join(workdir, "backup_paths.json")
            assert os.path.isfile(generated_path), "The script did not generate backup_paths.json for an unseen graph."
            try:
                with open(generated_path, "r") as f:
                    actual = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("The script generated invalid JSON for an unseen graph.")

            assert actual == expected, (
                "The script did not compute all sorted length-2 paths for an unseen graph. "
                f"Expected {expected}, but got {actual}."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
