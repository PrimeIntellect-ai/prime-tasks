#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from pathlib import Path

SOURCE = "/home/user/graph_etl.c"
BINARY = "/home/user/graph_etl"
REBUILT = "/tmp/graph_etl_from_source"
NODES = "/home/user/nodes.csv"
EDGES = "/home/user/edges.csv"
RESULTS = "/home/user/results.csv"


def replace_file(path, contents):
    if os.path.lexists(path):
        os.unlink(path)
    Path(path).write_text(contents, encoding="utf-8")


def install_graph(nodes, edges):
    node_text = "id,type\n" + "".join(f"{node_id},{node_type}\n" for node_id, node_type in nodes)
    edge_text = "source_id,target_id,relation\n" + "".join(
        f"{source},{target},{relation}\n" for source, target, relation in edges
    )
    replace_file(NODES, node_text)
    replace_file(EDGES, edge_text)


def expected_output(nodes, edges):
    node_types = dict(nodes)
    matches = []
    for user_id, order_id, first_relation in edges:
        if first_relation != "BUYS":
            continue
        if node_types.get(user_id) != "User" or node_types.get(order_id) != "Order":
            continue
        for source_id, product_id, second_relation in edges:
            if source_id != order_id or second_relation != "CONTAINS":
                continue
            if node_types.get(product_id) == "Product":
                matches.append((user_id, product_id))
    return [f"{user_id},{product_id}" for user_id, product_id in sorted(matches)]


def run_and_read(executable, nodes, edges):
    install_graph(nodes, edges)
    if os.path.lexists(RESULTS):
        os.unlink(RESULTS)
    completed = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=5
    )
    assert completed.returncode == 0, (
        f"{executable} exited with {completed.returncode}.\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist after running {executable}."
    with open(RESULTS, "r", encoding="utf-8") as result_file:
        return [line.strip() for line in result_file if line.strip()]


def make_random_case():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    ids = rng.sample(range(1000, 900000), 15)
    users = ids[0:4]
    orders = ids[4:8]
    products = ids[8:12]
    others = ids[12:14]
    missing = ids[14]

    nodes = (
        [(value, "User") for value in users]
        + [(value, "Order") for value in orders]
        + [(value, "Product") for value in products]
        + [(value, "Category") for value in others]
    )

    edges = [
        (users[0], orders[0], "BUYS"),
        (users[1], orders[0], "BUYS"),
        (users[2], orders[1], "BUYS"),
        (users[3], orders[2], "BUYS"),
        (users[0], orders[3], "BUYS"),
        (orders[0], products[0], "CONTAINS"),
        (orders[0], products[1], "CONTAINS"),
        (orders[1], products[2], "CONTAINS"),
        (orders[2], products[3], "CONTAINS"),
        (orders[3], products[2], "CONTAINS"),
        (orders[3], products[0], "CONTAINS"),
        # Distractors exercising labels, direction, relation names, and missing nodes.
        (users[0], products[0], "BUYS"),
        (orders[0], products[3], "HAS"),
        (users[1], orders[1], "CONTAINS"),
        (products[0], orders[2], "BUYS"),
        (users[2], others[0], "BUYS"),
        (others[0], products[1], "CONTAINS"),
        (others[1], orders[3], "BUYS"),
        (orders[1], users[0], "CONTAINS"),
        (missing, orders[0], "BUYS"),
        (users[3], missing, "BUYS"),
        (missing, products[1], "CONTAINS"),
        (products[2], orders[0], "CONTAINS"),
    ]
    rng.shuffle(nodes)
    rng.shuffle(edges)
    return nodes, edges


def test_source_file_exists():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as binary_file:
        assert binary_file.read(4) == b"\x7fELF", f"Binary {BINARY} is not an ELF executable."


def test_source_compiles():
    completed = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", REBUILT],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert completed.returncode == 0, (
        f"Source did not compile.\nstdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def test_results_file_exists_and_correct():
    nodes = [
        (10, "User"), (11, "Order"), (12, "Product"),
        (13, "User"), (14, "Order"), (15, "Product"),
        (16, "Order"), (17, "Product"), (18, "User"),
    ]
    edges = [
        (10, 11, "BUYS"), (11, 12, "CONTAINS"),
        (13, 14, "BUYS"), (14, 15, "CONTAINS"),
        (13, 16, "BUYS"), (16, 17, "CONTAINS"),
        (18, 16, "BUYS"),
    ]
    expected = ["10,12", "13,15", "13,17", "18,17"]
    actual = run_and_read(BINARY, nodes, edges)
    assert actual == expected, (
        f"Content of {RESULTS} does not match expected output.\n"
        f"Expected: {expected}\nActual: {actual}"
    )


def test_executables_process_changed_graphs():
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK), "Rebuilt source executable is unavailable."
    cases = [make_random_case() for _ in range(3)]
    for executable in (BINARY, REBUILT):
        for nodes, edges in cases:
            expected = expected_output(nodes, edges)
            actual = run_and_read(executable, nodes, edges)
            assert actual == expected, (
                f"{executable} produced incorrect output for a changed graph.\n"
                f"Expected: {expected}\nActual: {actual}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
