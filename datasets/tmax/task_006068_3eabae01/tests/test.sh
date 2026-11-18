#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
import tempfile

SOURCE = "/home/user/project_graph.c"
EXECUTABLE = "/home/user/project_graph"
DATASET = "/home/user/bipartite.txt"
TOP_FILE = "/home/user/top_user.txt"
COMPILED_FROM_SOURCE = "/tmp/project_graph_from_source"


def expected_projection(edges):
    users = {user for user, _ in edges}
    products_by_user = {user: set() for user in users}
    for user, product in edges:
        products_by_user[user].add(product)

    result = {}
    for user in users:
        degree = sum(
            1
            for other in users
            if other != user and products_by_user[user] & products_by_user[other]
        )
        # Preserve the supplied program's output contract: it prints positive degrees.
        if degree > 0:
            result[user] = degree
    return result


def parse_output(output):
    result = {}
    for line in output.splitlines():
        assert re.fullmatch(r"-?\d+,-?\d+", line), \
            f"Malformed output line: {line!r}; expected UserID,Degree"
        user_text, degree_text = line.split(",")
        user, degree = int(user_text), int(degree_text)
        assert user not in result, f"Duplicate output for user {user}"
        result[user] = degree
    return result


def run_and_check(program, edges):
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as input_file:
        for user, product in edges:
            input_file.write(f"{user} {product}\n")
        input_path = input_file.name

    try:
        completed = subprocess.run(
            [program, input_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
    finally:
        os.unlink(input_path)

    assert completed.returncode == 0, \
        f"{program} exited with {completed.returncode}: {completed.stderr}"
    actual = parse_output(completed.stdout)
    expected = expected_projection(edges)
    assert actual == expected, f"Projection mismatch: expected {expected}, got {actual}"


def read_edges(path):
    edges = []
    with open(path) as f:
        for line in f:
            if line.strip():
                user, product = map(int, line.split())
                edges.append((user, product))
    return edges


def test_project_graph_c_fixed():
    assert os.path.exists(SOURCE), f"File {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."

    with open(SOURCE) as f:
        content = f.read()

    assert "if (edges[i].product == edges[j].product)" in content, \
        "The C file bug was not fixed. Expected `==` instead of `=`."
    assert "if (edges[i].product = edges[j].product)" not in content, \
        "The C file still contains the bug (`=` instead of `==`)."

    compiled = subprocess.run(
        ["gcc", SOURCE, "-o", COMPILED_FROM_SOURCE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert compiled.returncode == 0, f"The submitted C source does not compile: {compiled.stderr}"


def test_project_graph_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file."

    st = os.stat(EXECUTABLE)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), \
        f"{EXECUTABLE} is not executable."

    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", \
            f"{EXECUTABLE} is not a compiled ELF executable."


def test_program_behavior():
    cases = [
        read_edges(DATASET),
        [(1, 10), (2, 10), (2, 10), (2, 11), (3, 11), (1, 12), (3, 12)],
        [(8, 50), (3, 50), (8, 51), (4, 51), (3, 52), (4, 53), (9, 99)],
        [(1, 10), (2, 10), (3, 10), (1, 20), (2, 20), (4, 20),
         (3, 30), (4, 30), (5, 40)],
    ]

    rng = random.SystemRandom()
    for _ in range(8):
        users = sorted(rng.sample(range(1, 91), rng.randint(5, 20)))
        products = rng.sample(range(100, 1000), rng.randint(3, 10))
        edges = [(users[0], products[0]), (users[1], products[0])]
        for user in users:
            for product in products:
                if rng.random() < 0.25:
                    edges.append((user, product))
        cases.append(edges)

    # Exercise both the required submitted executable and a fresh build of the source.
    for program in (EXECUTABLE, COMPILED_FROM_SOURCE):
        for edges in cases:
            run_and_check(program, edges)


def test_top_user_txt_content():
    assert os.path.exists(TOP_FILE), f"Output file {TOP_FILE} does not exist."
    assert os.path.isfile(TOP_FILE), f"{TOP_FILE} is not a file."

    with open(TOP_FILE) as f:
        content = f.read().strip()

    # Retain the original assertion and also derive the answer from the input graph.
    assert content == "1", f"Expected top_user.txt to contain '1', but found {content!r}."
    projection = expected_projection(read_edges(DATASET))
    maximum = max(projection.values())
    expected_top = min(user for user, degree in projection.items() if degree == maximum)
    assert content == str(expected_top), \
        f"Expected recomputed top user {expected_top}, but found {content!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
