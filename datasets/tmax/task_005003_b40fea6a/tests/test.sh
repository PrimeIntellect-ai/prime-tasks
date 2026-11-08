#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_executable_exists_and_is_executable():
    path = "/home/user/graph_query"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you move it to the correct location?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_makefile_builds_and_executables_are_correct():
    toolkit = "/app/csv-graph-toolkit"
    csv_path = os.path.join(toolkit, "edges.csv")
    built_exe = os.path.join(toolkit, "graph_query")
    agent_exe = "/home/user/graph_query"

    assert os.path.isfile(os.path.join(toolkit, "Makefile")), "Makefile is missing."
    assert os.path.isfile(os.path.join(toolkit, "graph_query.c")), "graph_query.c is missing."
    assert os.path.isfile(csv_path), "edges.csv is missing."

    # Force a rebuild from graph_query.c so a prebuilt replacement cannot hide a
    # still-broken source file or Makefile.
    for path in (built_exe, os.path.join(toolkit, "graph_query.o")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["make"], cwd=toolkit, capture_output=True, text=True, timeout=120
    )
    assert build.returncode == 0, (
        f"make failed with return code {build.returncode}\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert os.path.isfile(built_exe), "make did not produce graph_query."
    assert os.access(built_exe, os.X_OK), "The graph_query produced by make is not executable."

    original_csv = open(csv_path, "rb").read()
    token = secrets.token_hex(6)
    nodes = [f"n_{token}_{i:02d}" for i in range(12)]
    missing = f"missing_{secrets.token_hex(8)}"

    # Branches, merging paths, cycles, disconnected components, and leaves.
    edges = [
        (nodes[0], nodes[1]),
        (nodes[0], nodes[2]),
        (nodes[1], nodes[3]),
        (nodes[2], nodes[3]),
        (nodes[3], nodes[4]),
        (nodes[4], nodes[1]),
        (nodes[2], nodes[5]),
        (nodes[6], nodes[7]),
        (nodes[7], nodes[8]),
        (nodes[9], nodes[10]),
        (nodes[9], nodes[11]),
    ]

    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, set()).add(target)

    def expected_output(start):
        reached = set()
        pending = list(adjacency.get(start, ()))
        while pending:
            node = pending.pop()
            if node in reached:
                continue
            reached.add(node)
            pending.extend(adjacency.get(node, ()))
        ordered = sorted(reached)
        return "" if not ordered else "\n".join(ordered) + "\n"

    try:
        with open(csv_path, "w", encoding="utf-8", newline="") as f:
            for source, target in edges:
                f.write(f"{source},{target}\n")

        for executable in (agent_exe, built_exe):
            assert os.path.isfile(executable), f"Executable {executable} is missing."
            assert os.access(executable, os.X_OK), f"Executable {executable} is not executable."

            for start in nodes + [missing]:
                proc = subprocess.run(
                    [executable, start],
                    cwd=toolkit,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                assert proc.returncode == 0, (
                    f"{executable} returned {proc.returncode} for input {start}.\n"
                    f"stderr:\n{proc.stderr}"
                )
                expected = expected_output(start)
                assert proc.stdout == expected, (
                    f"Output mismatch from {executable} for input {start}.\n"
                    f"Expected:\n{expected}\nActual:\n{proc.stdout}"
                )
    finally:
        with open(csv_path, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
