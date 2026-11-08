#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import pytest

SOURCE_PATH = "/home/user/build_paths.c"
EXEC_PATH = "/home/user/build_paths"
INPUT_PATH = "/home/user/input_graph.csv"
OUTPUT_PATH = "/home/user/output_docs.jsonl"


def run_program(program):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [program], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"{program} did not create {OUTPUT_PATH}."


def read_output():
    actual_data = []
    with open(OUTPUT_PATH, "r") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_data.append(json.loads(line))
            except json.JSONDecodeError as e:
                pytest.fail(f"Line {line_num} in {OUTPUT_PATH} is not valid JSON: {e}")
    return actual_data


def expected_for(records):
    nodes = {node_id: (parent_id, name) for node_id, parent_id, name in records}

    def path_for(node_id, active=None):
        if active is None:
            active = set()
        assert node_id not in active, "Verifier test data unexpectedly contains a cycle"
        parent_id, name = nodes[node_id]
        if parent_id == 0:
            return [name]
        assert parent_id in nodes, "Verifier test data has a missing parent"
        return path_for(parent_id, active | {node_id}) + [name]

    return [
        {"id": node_id, "name": nodes[node_id][1], "path": path_for(node_id)}
        for node_id in sorted(nodes)
    ]


def write_input(records):
    with open(INPUT_PATH, "w") as f:
        f.write("node_id,parent_id,node_name\n")
        for node_id, parent_id, name in records:
            f.write(f"{node_id},{parent_id},{name}\n")


def test_c_source_and_executable_exist():
    """Verify that the C source code and the compiled executable exist."""
    assert os.path.isfile(SOURCE_PATH), f"C source file {SOURCE_PATH} is missing."
    assert os.path.isfile(EXEC_PATH), f"Compiled executable {EXEC_PATH} is missing."
    assert os.access(EXEC_PATH, os.X_OK), f"File {EXEC_PATH} is not executable."
    with open(EXEC_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXEC_PATH} is not a compiled ELF executable."


def test_output_jsonl_exists_and_correct():
    """Execute the submitted program and verify the required original mapping."""
    run_program(EXEC_PATH)

    expected_data = [
        {"id": 1, "name": "Electronics", "path": ["Electronics"]},
        {"id": 2, "name": "Computers", "path": ["Electronics", "Computers"]},
        {"id": 3, "name": "Laptops", "path": ["Electronics", "Computers", "Laptops"]},
        {"id": 4, "name": "Desktops", "path": ["Electronics", "Computers", "Desktops"]},
        {"id": 5, "name": "Home", "path": ["Home"]},
        {"id": 6, "name": "Furniture", "path": ["Home", "Furniture"]},
        {"id": 7, "name": "Chairs", "path": ["Home", "Furniture", "Chairs"]},
        {"id": 8, "name": "Tables", "path": ["Home", "Furniture", "Tables"]},
        {"id": 9, "name": "Audio", "path": ["Electronics", "Audio"]},
        {"id": 10, "name": "Headphones", "path": ["Electronics", "Audio", "Headphones"]}
    ]

    actual_data = read_output()
    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} lines in {OUTPUT_PATH}, found {len(actual_data)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Mismatch at line {i+1}: expected {expected}, got {actual}."


def test_executable_and_source_process_changed_csv_recursively():
    """Exercise both the submitted executable and a fresh build on derived cases."""
    rebuilt = "/tmp/build_paths_from_source"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE_PATH, "-o", rebuilt],
        capture_output=True, text=True, timeout=15
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}. stdout={compile_result.stdout!r}, "
        f"stderr={compile_result.stderr!r}"
    )

    cases = [
        [
            (7, 6, "Final"),
            (3, 2, "East"),
            (1, 0, "World"),
            (6, 5, "Deep"),
            (2, 1, "Region"),
            (5, 3, "Branch"),
            (4, 1, "West"),
        ],
        [
            (6, 4, "Sparrows"),
            (2, 0, "Plants"),
            (5, 3, "Mammals"),
            (1, 0, "Animals"),
            (4, 3, "Birds"),
            (3, 1, "Vertebrates"),
            (7, 2, "Trees"),
            (8, 7, "Pines"),
        ],
    ]

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    try:
        for records in cases:
            expected = expected_for(records)
            for program in (EXEC_PATH, rebuilt):
                write_input(records)
                run_program(program)
                actual = read_output()
                assert len(actual) == len(expected), (
                    f"{program} produced {len(actual)} objects; expected {len(expected)}"
                )
                assert actual == expected, (
                    f"{program} did not parse and resolve the changed hierarchy correctly. "
                    f"Expected {expected}, got {actual}"
                )
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
