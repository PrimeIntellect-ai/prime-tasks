#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import pytest

SOURCE = "/home/user/audit.cpp"
BINARY = "/home/user/audit"
INPUT = "/home/user/access_log.csv"
OUTPUT = "/home/user/compliance_violations.txt"

ORIGINAL_CSV = """Alice,App1
App1,DataLake
DataLake,SecureVault
Bob,App2
App2,App1
Charlie,SecureVault
Dave,ServiceA
ServiceA,ServiceB
ServiceB,ServiceC
ServiceC,SecureVault
Eve,ServiceB
Frank,Frank
"""


def run_submission(csv_text):
    with open(INPUT, "w") as f:
        f.write(csv_text)

    if os.path.lexists(OUTPUT):
        if os.path.isdir(OUTPUT) and not os.path.islink(OUTPUT):
            raise AssertionError(f"{OUTPUT} is a directory")
        os.unlink(OUTPUT)

    result = subprocess.run(
        [BINARY], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"Program did not create {OUTPUT}."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."

    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    return [line.strip() for line in content.splitlines() if line.strip()]


def expected_for(edges):
    nodes = {name for edge in edges for name in edge}
    adjacency = {name: set() for name in nodes}
    for source, target in edges:
        adjacency[source].add(target)

    matches = []
    for start in nodes:
        frontier = {start}
        found = False
        for _ in range(3):
            frontier = {
                target
                for node in frontier
                for target in adjacency.get(node, ())
            }
            if "SecureVault" in frontier:
                found = True
                break
        if found:
            matches.append(start)
    return sorted(matches)


@pytest.fixture(scope="session", autouse=True)
def compile_and_execute_submission():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."

    if os.path.lexists(BINARY):
        if os.path.isdir(BINARY) and not os.path.islink(BINARY):
            raise AssertionError(f"{BINARY} is a directory and cannot be replaced")
        os.unlink(BINARY)

    result = subprocess.run(
        ["g++", "-std=c++17", "-O3", SOURCE, "-o", BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Compilation failed with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(BINARY), f"Compilation did not create {BINARY}."

    run_submission(ORIGINAL_CSV)
    yield

    # Leave the task's original input and its freshly generated output in place.
    run_submission(ORIGINAL_CSV)


def test_compliance_violations_output():
    output_file = "/home/user/compliance_violations.txt"

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    expected_entities = [
        "Alice",
        "App1",
        "App2",
        "Charlie",
        "DataLake",
        "Eve",
        "ServiceA",
        "ServiceB",
        "ServiceC"
    ]

    with open(output_file, "r") as f:
        content = f.read().strip()

    actual_entities = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_entities == expected_entities, (
        f"The contents of {output_file} do not match the expected output.\n"
        f"Expected: {expected_entities}\n"
        f"Actual: {actual_entities}"
    )


def test_cpp_file_exists():
    cpp_file = "/home/user/audit.cpp"
    assert os.path.exists(cpp_file), f"Source file {cpp_file} does not exist."
    assert os.path.isfile(cpp_file), f"{cpp_file} is not a file."


def test_program_on_unseen_graphs():
    rng = random.SystemRandom()

    for case_number in range(5):
        token = secrets.token_hex(8)
        names = [f"Entity_{token}_{i:02d}" for i in range(16)]
        vault = "SecureVault"

        # Guaranteed paths at distances 1, 2, 3, and 4, plus cycles,
        # duplicate rows, and randomized additional topology.
        edges = [
            (names[0], vault),
            (names[1], names[0]),
            (names[2], names[1]),
            (names[3], names[2]),
            (names[4], names[5]),
            (names[5], names[4]),
            (names[6], names[7]),
            (names[7], names[8]),
            (names[8], names[9]),
            (names[9], vault),
            (names[10], names[10]),
            (names[0], vault),
        ]

        all_nodes = names + [vault]
        for source in names:
            for target in all_nodes:
                if rng.random() < 0.07:
                    edges.append((source, target))

        rng.shuffle(edges)
        csv_text = "".join(f"{source},{target}\n" for source, target in edges)
        actual = run_submission(csv_text)
        expected = expected_for(edges)

        assert actual == expected, (
            f"Incorrect result for unseen graph {case_number}.\n"
            f"Expected: {expected}\nActual: {actual}\nEdges: {edges}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
