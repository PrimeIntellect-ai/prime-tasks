#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

C_SOURCE = "/home/user/find_paths.c"
EXECUTABLE = "/home/user/find_paths"
NODES = "/home/user/nodes.csv"
EDGES = "/home/user/edges.csv"


def run_program(path, start_type, end_type, limit):
    result = subprocess.run(
        [path, start_type, end_type, str(limit)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout


def test_find_paths_compiled():
    assert os.path.isfile(C_SOURCE), f"Source file {C_SOURCE} is missing."
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."

    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            f"{EXECUTABLE} is not a compiled ELF executable."
        )


def test_results_txt_content():
    results_file = "/home/user/results.txt"
    assert os.path.isfile(results_file), f"Results file {results_file} is missing."

    with open(results_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Alice -> Hello -> Widget",
        "Alice -> World -> Gadget",
        "Bob -> World -> Gadget",
        "Charlie -> News -> Widget"
    ]

    assert lines == expected_lines, (
        f"Contents of {results_file} do not match the expected sorted 2-hop paths "
        f"from 'User' to 'Product' with limit 5.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {lines}"
    )


def test_executable_on_original_data():
    expected = (
        "Alice -> Hello -> Widget\n"
        "Alice -> World -> Gadget\n"
        "Bob -> World -> Gadget\n"
        "Charlie -> News -> Widget\n"
    )
    actual = run_program(EXECUTABLE, "User", "Product", 5)
    assert actual == expected, f"Unexpected program output.\nExpected: {expected!r}\nGot: {actual!r}"


def test_connectivity_filtering_sorting_and_limit():
    token = secrets.token_hex(6)
    start_type = "Start_" + token
    end_type = "End_" + token
    other_start = "OtherStart_" + token
    other_end = "OtherEnd_" + token
    middle_type = "Middle_" + token

    nodes = [
        (1, start_type, "Zulu_" + token),
        (2, start_type, "Alpha_" + token),
        (3, other_start, "Origin_" + token),
        (4, middle_type, "BridgeB_" + token),
        (5, middle_type, "BridgeA_" + token),
        (6, end_type, "EndB_" + token),
        (7, end_type, "EndA_" + token),
        (8, other_end, "Alternate_" + token),
        (9, middle_type, "Isolated_" + token),
    ]
    edges = [
        (1, 4, "R1"),
        (4, 6, "R2"),
        (2, 5, "R3"),
        (5, 7, "R4"),
        (1, 5, "R5"),
        (3, 4, "R6"),
        (4, 8, "R7"),
        (9, 7, "R8"),
        (2, 9, "R9"),
        (9, 6, "R10"),
    ]

    node_by_id = {node_id: (node_type, name) for node_id, node_type, name in nodes}

    def expected_output(requested_start, requested_end, limit):
        paths = []
        for source1, target1, _ in edges:
            for source2, target2, _ in edges:
                if target1 != source2:
                    continue
                a = node_by_id[source1]
                b = node_by_id[target1]
                c = node_by_id[target2]
                if a[0] == requested_start and c[0] == requested_end:
                    paths.append(f"{a[1]} -> {b[1]} -> {c[1]}")
        paths.sort()
        paths = paths[:limit]
        return "".join(path + "\n" for path in paths)

    original_nodes = open(NODES, "rb").read()
    original_edges = open(EDGES, "rb").read()
    rebuilt = "/tmp/find_paths_from_submitted_source"

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert compile_result.returncode == 0, (
        f"Submitted C source does not compile: {compile_result.stderr}"
    )

    try:
        with open(NODES, "w") as f:
            for node_id, node_type, name in nodes:
                f.write(f"{node_id},{node_type},{name}\n")
        with open(EDGES, "w") as f:
            for source, target, relation in edges:
                f.write(f"{source},{target},{relation}\n")

        queries = [
            (start_type, end_type, 99),
            (start_type, end_type, 2),
            (start_type, end_type, 1),
            (other_start, end_type, 99),
            (start_type, other_end, 99),
            (other_start, other_end, 99),
            (start_type, other_start, 99),
        ]
        for program in (EXECUTABLE, rebuilt):
            for requested_start, requested_end, limit in queries:
                expected = expected_output(requested_start, requested_end, limit)
                actual = run_program(program, requested_start, requested_end, limit)
                assert actual == expected, (
                    f"{program} failed for arguments "
                    f"{requested_start!r} {requested_end!r} {limit}.\n"
                    f"Expected: {expected!r}\nGot: {actual!r}"
                )
    finally:
        with open(NODES, "wb") as f:
            f.write(original_nodes)
        with open(EDGES, "wb") as f:
            f.write(original_edges)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
