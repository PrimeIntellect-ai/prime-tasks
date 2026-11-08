#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import uuid
from collections import defaultdict

import pytest

SOURCE_PATH = "/home/user/analyze_backups.cpp"
JSON_PATH = "/home/user/backup_query_result.json"
LOG_PATH = "/home/user/critical_backups.log"
BINARY_PATH = f"/tmp/analyze_backups_verifier_{uuid.uuid4().hex}"


def expected_lines(data):
    in_degrees = defaultdict(int)
    for result in data.get("results", []):
        for data_item in result.get("data", []):
            for row in data_item.get("row", []):
                if row.get("type") == "DEPENDS_ON":
                    target = row.get("target")
                    if target:
                        in_degrees[target] += 1

    sorted_dbs = sorted(in_degrees.items(), key=lambda x: (-x[1], x[0]))
    return [
        f"{rank}. {name} - {count} dependencies"
        for rank, (name, count) in enumerate(sorted_dbs[:3], 1)
    ]


def run_and_check(data, label, write_input=True):
    if write_input:
        with open(JSON_PATH, "w") as f:
            json.dump(data, f)

    expected = expected_lines(data)

    if os.path.lexists(LOG_PATH):
        os.unlink(LOG_PATH)

    result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Program failed for {label} with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(LOG_PATH), (
        f"Output file {LOG_PATH} is missing after running the C++ program for {label}."
    )
    with open(LOG_PATH, "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    assert len(actual) == len(expected), (
        f"Expected {len(expected)} lines for {label}, but found {len(actual)}."
    )
    for index, (expected_line, actual_line) in enumerate(zip(expected, actual), 1):
        assert actual_line == expected_line, (
            f"Line {index} mismatch for {label}.\n"
            f"Expected: '{expected_line}'\nActual: '{actual_line}'"
        )


def edge(source, target=None, relationship="DEPENDS_ON"):
    value = {"source": source, "type": relationship}
    if target is not None:
        value["target"] = target
    return {"row": [value]}


def test_cpp_program_generates_critical_backups_log():
    assert os.path.isfile(JSON_PATH), f"Input file {JSON_PATH} is missing."
    with open(JSON_PATH, "r") as f:
        try:
            original_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON")

    assert os.path.exists(SOURCE_PATH), f"C++ source file {SOURCE_PATH} is missing."
    source_mode = os.lstat(SOURCE_PATH).st_mode
    assert stat.S_ISREG(source_mode), f"{SOURCE_PATH} must be a regular C++ source file."

    compile_result = subprocess.run(
        ["/usr/bin/g++", "-std=c++11", SOURCE_PATH, "-o", BINARY_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(BINARY_PATH), "Compilation did not produce an executable."
    assert os.access(BINARY_PATH, os.X_OK), "Compiled artifact is not executable."

    # Preserve the original verifier's dynamic check against the current input.
    run_and_check(original_data, "the supplied input", write_input=False)

    # Exercise the compiled program on unpredictable names, ties, ignored edge
    # types, and more than three candidates so a prewritten log cannot pass.
    token = uuid.uuid4().hex
    alpha = f"{token}_alpha_db"
    beta = f"{token}_beta_db"
    gamma = f"{token}_gamma_db"
    delta = f"{token}_delta_db"
    epsilon = f"{token}_epsilon_db"

    rows = []
    for i in range(6):
        rows.append(edge(f"src_g_{token}_{i}", gamma))
    for i in range(4):
        rows.append(edge(f"src_a_{token}_{i}", alpha))
        rows.append(edge(f"src_b_{token}_{i}", beta))
    for i in range(3):
        rows.append(edge(f"src_d_{token}_{i}", delta))
    rows.append(edge(f"src_e_{token}", epsilon))
    rows.append(edge(f"ignored_{token}", gamma, "OWNS"))
    rows.append(edge(f"missing_target_{token}", None))
    random.SystemRandom().shuffle(rows)

    complex_data = {
        "results": [
            {"data": rows[:len(rows) // 2]},
            {"data": rows[len(rows) // 2:]},
        ]
    }
    run_and_check(complex_data, "randomized centrality and Top 3 case")

    # Also verify pagination when fewer than three target databases exist.
    one = f"{uuid.uuid4().hex}_one_db"
    two = f"{uuid.uuid4().hex}_two_db"
    small_data = {
        "results": [{"data": [
            edge("small_source_1", one),
            edge("small_source_2", one),
            edge("small_source_3", two),
        ]}]
    }
    run_and_check(small_data, "fewer-than-three case")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
