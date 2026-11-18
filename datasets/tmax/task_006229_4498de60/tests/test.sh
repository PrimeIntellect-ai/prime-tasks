#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess

import pytest

HOME = "/home/user"
PROGRAM = f"{HOME}/verify_graph"
SOURCE = f"{HOME}/verify_graph.c"
NODES = f"{HOME}/graph_nodes.csv"
EDGES = f"{HOME}/graph_edges.csv"
REPORT_A = f"{HOME}/report_A.csv"
REPORT_B = f"{HOME}/report_B.csv"
REBUILT = "/tmp/verify_graph_rebuilt"


def run_program(path):
    for report in (REPORT_A, REPORT_B):
        try:
            os.remove(report)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [path], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.exists(REPORT_A), f"{path} did not generate {REPORT_A}"
    assert os.path.exists(REPORT_B), f"{path} did not generate {REPORT_B}"


def read_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


@pytest.fixture(scope="session", autouse=True)
def execute_and_rebuild_submission():
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    assert os.path.isfile(PROGRAM), f"Program not found at {PROGRAM}"
    assert os.access(PROGRAM, os.X_OK), f"File at {PROGRAM} is not executable"

    with open(PROGRAM, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PROGRAM} is not a compiled native executable"

    # Remove any prewritten reports and require the submitted executable to recreate them.
    run_program(PROGRAM)

    build = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", REBUILT, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert build.returncode == 0, (
        f"Failed to compile {SOURCE}: stdout={build.stdout!r}, stderr={build.stderr!r}"
    )
    assert os.access(REBUILT, os.X_OK)
    yield


def test_report_a_content():
    report_a_path = REPORT_A
    assert os.path.exists(report_a_path), f"Missing file: {report_a_path}"

    expected_a = [
        "APIGateway,LogDB",
        "APIGateway,UserDB",
        "BackgroundWorker,LogDB",
        "BackgroundWorker,TxDB",
        "BackgroundWorker,UserDB",
        "WebSrv1,TxDB",
        "WebSrv1,UserDB",
        "WebSrv2,UserDB"
    ]

    lines = read_lines(report_a_path)
    assert lines == expected_a, f"Content mismatch in {report_a_path}. Expected {expected_a}, but got {lines}."


def test_report_b_content():
    report_b_path = REPORT_B
    assert os.path.exists(report_b_path), f"Missing file: {report_b_path}"

    expected_b = [
        "1,3,AuthService,5",
        "2,4,PaymentService,4",
        "3,5,UserDB,3",
        "3,8,NotificationService,3",
        "4,1,WebSrv1,2"
    ]

    lines = read_lines(report_b_path)
    assert len(lines) == 5, f"Expected exactly 5 rows in {report_b_path}, but got {len(lines)}."
    assert lines == expected_b, f"Content mismatch in {report_b_path}. Expected {expected_b}, but got {lines}."


def test_c_program_compiled():
    program_path = PROGRAM
    assert os.path.exists(program_path), f"C program executable not found at {program_path}"
    assert os.access(program_path, os.X_OK), f"File at {program_path} is not executable"

    with open(SOURCE, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), "Source does not include sqlite3.h"
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source), "Source does not open an SQLite database"
    assert re.search(r"\bsqlite3_(?:exec|prepare(?:_v2|_v3)?)\s*\(", source), "Source does not execute SQLite SQL"
    assert re.search(r"\bDENSE_RANK\s*\(", source, re.IGNORECASE), "Source does not use DENSE_RANK()"
    assert ":memory:" in source, "Source does not create an in-memory SQLite database"


def derive_expected(nodes, edges):
    by_id = {node_id: (label, name) for node_id, label, name in nodes}

    outgoing_depends = {}
    for source, target, relationship in edges:
        if relationship == "DEPENDS_ON":
            outgoing_depends.setdefault(source, []).append(target)

    paths = set()
    for server_id, (label, server_name) in by_id.items():
        if label != "Server":
            continue
        for service_id in outgoing_depends.get(server_id, []):
            service = by_id.get(service_id)
            if not service or service[0] != "Service":
                continue
            for database_id in outgoing_depends.get(service_id, []):
                database = by_id.get(database_id)
                if database and database[0] == "Database":
                    paths.add((server_name, database[1]))
    expected_a = [f"{server},{database}" for server, database in sorted(paths)]

    degrees = {node_id: 0 for node_id, _, _ in nodes}
    for source, target, _ in edges:
        if source in degrees:
            degrees[source] += 1
        if target in degrees:
            degrees[target] += 1

    distinct_degrees = sorted(set(degrees.values()), reverse=True)
    ranks = {degree: index + 1 for index, degree in enumerate(distinct_degrees)}
    ranked = sorted(
        ((ranks[degrees[node_id]], node_id, name, degrees[node_id])
         for node_id, _, name in nodes),
        key=lambda row: (row[0], row[1])
    )[:5]
    expected_b = [f"{rank},{node_id},{name},{degree}" for rank, node_id, name, degree in ranked]
    return expected_a, expected_b


def test_program_computes_reports_from_changed_csv_inputs():
    original_nodes = open(NODES, "rb").read()
    original_edges = open(EDGES, "rb").read()

    rng = random.SystemRandom()
    token = secrets.token_hex(4)
    ids = rng.sample(range(101, 2000), 13)
    labels = (["Server"] * 3 + ["Service"] * 4 + ["Database"] * 3 +
              ["Worker", "Queue", "Cache"])
    nodes = [(ids[i], labels[i], f"N_{token}_{i}") for i in range(len(ids))]

    edge_set = set()
    # Guarantee several valid two-hop dependency paths.
    for triple in [(0, 3, 7), (0, 4, 8), (1, 3, 9), (2, 5, 7), (2, 6, 8)]:
        a, b, c = triple
        edge_set.add((ids[a], ids[b], "DEPENDS_ON"))
        edge_set.add((ids[b], ids[c], "DEPENDS_ON"))

    relationships = ["DEPENDS_ON", "DEPENDS_ON", "CALLS", "OWNS"]
    while len(edge_set) < 29:
        source, target = rng.sample(ids, 2)
        edge_set.add((source, target, rng.choice(relationships)))
    edges = list(edge_set)
    rng.shuffle(nodes)
    rng.shuffle(edges)

    expected_a, expected_b = derive_expected(nodes, edges)

    try:
        with open(NODES, "w") as f:
            for node_id, label, name in nodes:
                f.write(f"{node_id},{label},{name}\n")
        with open(EDGES, "w") as f:
            for source, target, relationship in edges:
                f.write(f"{source},{target},{relationship}\n")

        # Exercise both the submitted binary and a fresh build of the submitted C source.
        for executable in (PROGRAM, REBUILT):
            run_program(executable)
            actual_a = read_lines(REPORT_A)
            actual_b = read_lines(REPORT_B)
            assert actual_a == expected_a, (
                f"{executable} produced incorrect dependency paths for changed input. "
                f"Expected {expected_a}, got {actual_a}"
            )
            assert actual_b == expected_b, (
                f"{executable} produced incorrect degree ranking for changed input. "
                f"Expected {expected_b}, got {actual_b}"
            )
    finally:
        with open(NODES, "wb") as f:
            f.write(original_nodes)
        with open(EDGES, "wb") as f:
            f.write(original_edges)
        try:
            run_program(PROGRAM)
        except Exception:
            pass
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
