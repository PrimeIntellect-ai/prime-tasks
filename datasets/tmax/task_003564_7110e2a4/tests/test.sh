#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_c_source_exists():
    """Test that the C source file exists."""
    assert os.path.isfile("/home/user/fast_match.c"), "The C source file /home/user/fast_match.c is missing."


def test_c_executable_exists():
    """Test that the compiled executable exists."""
    assert os.path.isfile("/home/user/fast_match"), "The executable /home/user/fast_match is missing."
    assert os.access("/home/user/fast_match", os.X_OK), "/home/user/fast_match is not executable."


def test_recommendations_csv_correct():
    """Test that the recommendations.csv file contains the correct aggregated output."""
    output_file = "/home/user/recommendations.csv"
    assert os.path.isfile(output_file), f"The output file {output_file} is missing."

    expected_output = [
        "U001,3",
        "U002,2",
        "U003,1",
        "U005,2"
    ]

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_output, (
        f"The content of {output_file} does not match the expected output.\n"
        f"Expected: {expected_output}\n"
        f"Got: {lines}"
    )


def test_source_compiles_and_program_computes_fresh_graph():
    """Compile the submitted source and exercise it on a fresh graph."""
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/fast_match.c", "-o", "/home/user/fast_match"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"
    assert os.access("/home/user/fast_match", os.X_OK), "/home/user/fast_match is not executable after compilation."

    tag = secrets.token_hex(3).upper()
    users = [f"A{tag}", f"B{tag}", f"C{tag}", f"D{tag}"]
    cats = [f"K1{tag}", f"K2{tag}", f"K3{tag}"]
    items = [f"I1{tag}", f"I2{tag}", f"I3{tag}", f"I4{tag}"]
    triples = [
        (users[0], "VIEWS", cats[0]),
        (users[0], "VIEWS", cats[1]),
        (users[0], "VIEWS", cats[0]),
        (users[1], "VIEWS", cats[1]),
        (users[2], "VIEWS", cats[2]),
        (users[3], "VIEWS", f"EMPTY{tag}"),
        (cats[0], "INCLUDES", items[0]),
        (cats[0], "INCLUDES", items[1]),
        (cats[0], "INCLUDES", items[1]),
        (cats[1], "INCLUDES", items[1]),
        (cats[1], "INCLUDES", items[2]),
        (cats[2], "INCLUDES", items[3]),
        (users[0], "FOLLOWS", users[1]),
        (f"OTHER{tag}", "INCLUDES", items[0]),
    ]

    views = {}
    includes = {}
    for subject, predicate, obj in triples:
        if predicate == "VIEWS":
            views.setdefault(subject, set()).add(obj)
        elif predicate == "INCLUDES":
            includes.setdefault(subject, set()).add(obj)

    expected = []
    for user in sorted(views):
        reached = set()
        for category in views[user]:
            reached.update(includes.get(category, set()))
        if reached:
            expected.append(f"{user},{len(reached)}")

    graph_path = "/home/user/graph.csv"
    with open(graph_path, "rb") as f:
        original_graph = f.read()

    try:
        with open(graph_path, "w", newline="") as f:
            for triple in triples:
                f.write(",".join(triple) + "\n")

        run_result = subprocess.run(
            ["/home/user/fast_match"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            cwd="/home/user",
        )
        assert run_result.returncode == 0, (
            f"Program exited with status {run_result.returncode}.\n"
            f"stderr:\n{run_result.stderr}"
        )
        actual = [line.strip() for line in run_result.stdout.splitlines() if line.strip()]
        assert actual == expected, f"Expected fresh-graph output {expected}, got {actual}"
    finally:
        with open(graph_path, "wb") as f:
            f.write(original_graph)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
