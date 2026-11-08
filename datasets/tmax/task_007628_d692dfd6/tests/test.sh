#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
import uuid


def test_c_source_exists():
    path = "/home/user/detect_cycles.c"
    assert os.path.isfile(path), f"Expected C source file {path} does not exist."


def test_executable_exists():
    path = "/home/user/detect_cycles"
    assert os.path.isfile(path), f"Expected executable {path} does not exist. Did you compile the program?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {path} to be a compiled ELF executable."


def test_deadlocks_output():
    path = "/home/user/deadlocks.out"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "JobA,JobB,JobC",
        "JobG,JobH,JobI"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} cycles, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."


def expected_cycles(rows):
    active = {row[0] for row in rows if row[1] != "inactive"}
    graph = {
        row[0]: [dep for dep in row[2:] if dep in active]
        for row in rows if row[1] != "inactive"
    }
    cycles = set()

    def visit(start, node, path, seen):
        for nxt in graph.get(node, []):
            if nxt == start and len(path) >= 2:
                cycles.add(tuple(sorted(path)))
            elif nxt not in seen:
                visit(start, nxt, path + [nxt], seen | {nxt})

    for start in sorted(active):
        visit(start, start, [start], {start})

    return sorted(",".join(cycle) for cycle in cycles)


def write_dataset(rows):
    with open("/home/user/pipeline_export.csv", "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["task_id", "status", "dependencies"])
        writer.writerows(rows)


def run_and_check(executable, rows):
    expected = expected_cycles(rows)
    with open("/home/user/deadlocks.out", "w") as f:
        f.write("STALE_OUTPUT_MUST_BE_REPLACED\n")

    subprocess.run([executable], cwd="/home/user", check=True, timeout=10)
    assert os.path.isfile("/home/user/deadlocks.out"), "Program did not create deadlocks.out"
    with open("/home/user/deadlocks.out", "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"For generated input, expected {expected}, got {actual}"


def test_program_processes_generated_csv():
    source = "/home/user/detect_cycles.c"
    submitted_executable = "/home/user/detect_cycles"
    rebuilt_executable = "/tmp/detect_cycles_from_source"
    subprocess.run(["gcc", source, "-o", rebuilt_executable], check=True, timeout=20)

    csv_path = "/home/user/pipeline_export.csv"
    output_path = "/home/user/deadlocks.out"
    with open(csv_path, "rb") as f:
        original_csv = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    token = uuid.uuid4().hex[:10]
    n = lambda suffix: f"Task_{token}_{suffix}"

    cyclic_rows = [
        [n("A"), "active", n("B"), n("X")],
        [n("B"), "active", n("C")],
        [n("C"), "active", n("A")],
        [n("D"), "active", n("E")],
        [n("E"), "active", n("D")],
        [n("F"), "active", n("G")],
        [n("G"), "active"],
        [n("X"), "inactive", n("Y"), n("A")],
        [n("Y"), "active", n("X")],
    ]
    acyclic_rows = [
        [n("P"), "active", n("Q"), n("R")],
        [n("Q"), "active", n("R")],
        [n("R"), "active"],
        [n("U"), "inactive", n("V")],
        [n("V"), "active", n("U")],
    ]
    random.SystemRandom().shuffle(cyclic_rows)
    random.SystemRandom().shuffle(acyclic_rows)

    try:
        for executable in (submitted_executable, rebuilt_executable):
            for rows in (cyclic_rows, acyclic_rows):
                write_dataset(rows)
                run_and_check(executable, rows)
    finally:
        with open(csv_path, "wb") as f:
            f.write(original_csv)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
