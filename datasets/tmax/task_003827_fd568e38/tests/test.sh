#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tempfile

SOURCE = "/home/user/graph_parser.c"
BINARY = "/home/user/graph_parser"
QUERIES = "/home/user/queries.cypher"
INVALID = "/home/user/invalid_rows.log"


def run_parser(binary, dataset, schema):
    for path in (QUERIES, INVALID):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [binary, dataset, schema],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Parser exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def run_original():
    run_parser(BINARY, "/home/user/dataset.csv", "/home/user/schema.txt")


def test_c_source_exists():
    path = SOURCE
    assert os.path.isfile(path), f"Expected C source file {path} does not exist."


def test_compiled_program_exists_and_is_elf():
    assert os.path.isfile(BINARY), f"Expected compiled program {BINARY} does not exist."
    mode = os.stat(BINARY).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."


def test_queries_cypher_content():
    run_original()
    path = QUERIES
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    expected_lines = [
        "MERGE (a:Paper {id: 'P1'})-[:CITES]->(b:Paper {id: 'P2'});",
        "MERGE (a:Author {id: 'A1'})-[:WROTE]->(b:Paper {id: 'P1'});",
        "MERGE (a:Author {id: 'A2'})-[:AFFILIATED_WITH]->(b:Institution {id: 'I1'});",
        "MERGE (a:Author {id: 'A3'})-[:WROTE]->(b:Paper {id: 'P3'});"
    ]

    with open(path, 'r') as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {path} does not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_invalid_rows_log_content():
    run_original()
    path = INVALID
    assert os.path.isfile(path), f"Expected error log file {path} does not exist."

    expected_lines = [
        "P2,Paper,A1,Author,CITES",
        "A1,Author,P2,Paper,READS",
        "I1,Institution,P1,Paper,WROTE"
    ]

    with open(path, 'r') as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {path} does not match expected invalid rows.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_source_compiles_and_both_artifacts_handle_fresh_input():
    token = secrets.token_hex(4).upper()
    node_types = [f"Paper{token}", f"Author{token}", f"Institution{token}"]
    relationships = [f"CITES{token}", f"WROTE{token}", f"AFFILIATED{token}"]
    rules = {
        (node_types[0], relationships[0], node_types[0]),
        (node_types[1], relationships[1], node_types[0]),
        (node_types[1], relationships[2], node_types[2]),
    }

    schema_text = (
        f"Nodes: {', '.join(node_types)}\n"
        "Edges:\n"
        + "\n".join(f"{src} -> {rel} -> {dst}" for src, rel, dst in rules)
        + "\n"
    )

    rows = [
        (f"P{token}1", node_types[0], f"P{token}2", node_types[0], relationships[0]),
        (f"A{token}1", node_types[1], f"P{token}1", node_types[0], relationships[1]),
        (f"P{token}2", node_types[0], f"A{token}1", node_types[1], relationships[0]),
        (f"A{token}2", node_types[1], f"I{token}1", node_types[2], relationships[2]),
        (f"A{token}3", node_types[1], f"P{token}3", node_types[0], f"UNKNOWN{token}"),
        (f"X{token}", f"Unknown{token}", f"P{token}4", node_types[0], relationships[1]),
        (f"A{token}4", node_types[1].lower(), f"P{token}5", node_types[0], relationships[1]),
        (f"A{token}5", node_types[1], f"P{token}6", node_types[0], relationships[1]),
    ]
    raw_rows = [",".join(row) for row in rows]

    expected_queries = []
    expected_invalid = []
    valid_nodes = set(node_types)
    for raw, (source_id, source_type, target_id, target_type, rel_type) in zip(raw_rows, rows):
        if (source_type in valid_nodes and target_type in valid_nodes and
                (source_type, rel_type, target_type) in rules):
            expected_queries.append(
                f"MERGE (a:{source_type} {{id: '{source_id}'}})-[:{rel_type}]->"
                f"(b:{target_type} {{id: '{target_id}'}});"
            )
        else:
            expected_invalid.append(raw)

    with tempfile.TemporaryDirectory() as tmp:
        schema = os.path.join(tmp, "schema.txt")
        dataset = os.path.join(tmp, "dataset.csv")
        rebuilt = os.path.join(tmp, "graph_parser")
        with open(schema, "w") as f:
            f.write(schema_text)
        with open(dataset, "w") as f:
            f.write("\n".join(raw_rows))

        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"graph_parser.c did not compile.\nstdout:\n{compile_result.stdout}\n"
            f"stderr:\n{compile_result.stderr}"
        )

        for executable in (BINARY, rebuilt):
            run_parser(executable, dataset, schema)
            assert os.path.isfile(QUERIES), f"{executable} did not create {QUERIES}."
            assert os.path.isfile(INVALID), f"{executable} did not create {INVALID}."
            with open(QUERIES, "r") as f:
                actual_queries = f.read().splitlines()
            with open(INVALID, "r") as f:
                actual_invalid = f.read().splitlines()
            assert actual_queries == expected_queries, (
                f"{executable} produced incorrect Cypher for fresh input.\n"
                f"Expected: {expected_queries!r}\nActual: {actual_queries!r}"
            )
            assert actual_invalid == expected_invalid, (
                f"{executable} logged incorrect invalid rows for fresh input.\n"
                f"Expected: {expected_invalid!r}\nActual: {actual_invalid!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
