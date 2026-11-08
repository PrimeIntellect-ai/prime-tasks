#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/detect_deadlocks.c"
BINARY = "/tmp/detect_deadlocks_verified"
ORIGINAL_INPUT = "/home/user/etl_dependencies.csv"
ORIGINAL_OUTPUT = "/home/user/deadlocks_found.csv"
EXPECTED_ORIGINAL = """deadlocked_job_id
job_B
job_C
job_D
job_F
job_G
job_H
job_M
job_N
job_O
job_P"""


def test_detect_deadlocks_c_exists():
    assert os.path.isfile(SOURCE), f"The C source file {SOURCE} is missing."


def test_deadlocks_found_csv_exists_and_correct():
    assert os.path.isfile(ORIGINAL_OUTPUT), (
        f"The output file {ORIGINAL_OUTPUT} is missing. Did you compile and run your program?"
    )

    with open(ORIGINAL_OUTPUT, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == EXPECTED_ORIGINAL, (
        f"The content of {ORIGINAL_OUTPUT} is incorrect. Expected:\n{EXPECTED_ORIGINAL}"
        f"\n\nGot:\n{actual_content}"
    )


@pytest.fixture(scope="session")
def compiled_program():
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Failed to compile {SOURCE}:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    return BINARY


def expected_deadlocked_jobs(edges):
    nodes = sorted({node for edge in edges for node in edge})
    adjacency = {node: [] for node in nodes}
    for source, target in edges:
        adjacency[source].append(target)

    deadlocked = []
    for start in nodes:
        stack = list(adjacency[start])
        visited = set()
        while stack:
            current = stack.pop()
            if current == start:
                deadlocked.append(start)
                break
            if current not in visited:
                visited.add(current)
                stack.extend(adjacency[current])
    return sorted(deadlocked)


def run_and_check(program, edges, directory, case_name):
    input_path = os.path.join(directory, case_name + "_input.csv")
    output_path = os.path.join(directory, case_name + "_output.csv")
    with open(input_path, "w", newline="") as f:
        for source, target in edges:
            f.write(f"{source},{target}\n")

    result = subprocess.run(
        [program, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Program failed for parameterized input {input_path}:\n{result.stderr}"
    )
    assert os.path.isfile(output_path), "Program did not create the requested output path"

    with open(output_path, "r", newline="") as f:
        lines = f.read().splitlines()

    expected_jobs = expected_deadlocked_jobs(edges)
    assert lines, "Output is empty and lacks the required header"
    assert lines[0] == "deadlocked_job_id", "Output has an incorrect header"
    assert lines[1:] == expected_jobs, (
        f"Incorrect cycle members for edges {edges}. Expected {expected_jobs}, got {lines[1:]}"
    )


def test_compiles_and_executes_on_required_graph(compiled_program):
    result = subprocess.run(
        [compiled_program, ORIGINAL_INPUT, ORIGINAL_OUTPUT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Program failed on the required graph:\n{result.stderr}"
    assert os.path.isfile(ORIGINAL_OUTPUT), "Program did not create deadlocks_found.csv"
    with open(ORIGINAL_OUTPUT, "r") as f:
        actual_content = f.read().strip()
    assert actual_content == EXPECTED_ORIGINAL, (
        f"Executed program produced incorrect required output. Expected:\n{EXPECTED_ORIGINAL}"
        f"\n\nGot:\n{actual_content}"
    )


def test_parameterized_execution_and_additional_graphs(compiled_program):
    token = secrets.token_hex(6)
    names = [f"task_{token}_{i:02d}" for i in range(14)]

    cases = [
        [
            (names[0], names[1]),
            (names[1], names[2]),
            (names[2], names[3]),
            (names[3], names[4]),
        ],
        [
            (names[0], names[0]),
            (names[1], names[2]),
            (names[2], names[1]),
            (names[2], names[3]),
            (names[4], names[5]),
        ],
        [
            (names[0], names[1]),
            (names[1], names[2]),
            (names[2], names[0]),
            (names[2], names[3]),
            (names[3], names[4]),
            (names[4], names[5]),
            (names[5], names[3]),
            (names[6], names[7]),
            (names[7], names[8]),
            (names[9], names[10]),
            (names[10], names[11]),
            (names[11], names[12]),
            (names[12], names[9]),
            (names[13], names[0]),
        ],
    ]

    with tempfile.TemporaryDirectory(prefix="deadlock_verifier_") as directory:
        for index, edges in enumerate(cases):
            run_and_check(compiled_program, edges, directory, f"case_{index}_{token}")


def test_requires_exactly_two_arguments(compiled_program):
    invocations = [
        [compiled_program],
        [compiled_program, ORIGINAL_INPUT],
        [compiled_program, ORIGINAL_INPUT, "/tmp/extra_args_output.csv", "unexpected"],
    ]
    for command in invocations:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        assert result.returncode != 0, (
            f"Program must reject invocation with {len(command) - 1} command-line arguments"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
