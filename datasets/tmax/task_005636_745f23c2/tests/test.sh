#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess

import pytest

C_FILE = "/home/user/graph_query.c"
DEPS_FILE = "/home/user/dependencies.tsv"
RESULTS_FILE = "/home/user/results.json"
ORIGINAL_DEPS = open(DEPS_FILE, "rb").read()


def test_c_file_exists():
    c_file_path = C_FILE
    assert os.path.exists(c_file_path), f"The required C source file was not found at {c_file_path}"
    assert os.path.isfile(c_file_path), f"The path {c_file_path} is not a file."


@pytest.fixture(scope="module")
def executable():
    output = f"/tmp/graph_query_verified_{os.getpid()}"
    proc = subprocess.run(
        ["gcc", "-std=c11", "-pedantic-errors", C_FILE, "-o", output],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, f"graph_query.c did not compile as standard C:\n{proc.stderr}"
    assert os.path.isfile(output), "Compilation did not produce an executable."
    yield output
    try:
        os.remove(output)
    except FileNotFoundError:
        pass


def run_program(executable, dependency_bytes):
    with open(DEPS_FILE, "wb") as f:
        f.write(dependency_bytes)
    try:
        os.remove(RESULTS_FILE)
    except FileNotFoundError:
        pass

    proc = subprocess.run(
        [executable],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f"The compiled program exited with status {proc.returncode}.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.exists(RESULTS_FILE), f"The results file was not found at {RESULTS_FILE}"
    assert os.path.isfile(RESULTS_FILE), f"The path {RESULTS_FILE} is not a file."

    with open(RESULTS_FILE, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"The file {RESULTS_FILE} does not contain valid JSON: {exc}")

    assert isinstance(data, list), "The JSON result must be a list (array)."
    assert all(isinstance(item, str) for item in data), "Every JSON array element must be a string."
    return data


def expected_from_tsv(dependency_bytes):
    triples = []
    for raw_line in dependency_bytes.decode("utf-8").splitlines():
        if not raw_line:
            continue
        parts = raw_line.split("\t")
        assert len(parts) == 3
        triples.append(tuple(parts))

    table_subjects = {s for s, p, o in triples if p == "type" and o == "table"}
    sequential_nodes = {s for s, p, o in triples if p == "type" and o == "sequential_scan"}
    matches = {
        s for s, p, o in triples
        if p == "scanned_by" and s in table_subjects and o in sequential_nodes
    }
    return sorted(matches)[2:5]


def test_results_json_exists_and_correct(executable):
    data = run_program(executable, ORIGINAL_DEPS)
    expected_data = ["metadata", "products", "sessions"]
    assert data == expected_data, f"The JSON result does not match the expected output. Expected {expected_data}, got {data}."


def test_program_parses_changed_graph(executable):
    token = secrets.token_hex(6)
    triples = []

    for i in range(8):
        table = f"{token}_table_{i:02d}"
        scan = f"{token}_seq_{i:02d}"
        triples.extend([
            (table, "type", "table"),
            (table, "scanned_by", scan),
            (scan, "type", "sequential_scan"),
        ])

    for i in range(3):
        table = f"{token}_index_table_{i:02d}"
        scan = f"{token}_index_{i:02d}"
        triples.extend([
            (table, "type", "table"),
            (table, "scanned_by", scan),
            (scan, "type", "index_scan"),
        ])

    triples.extend([
        (f"{token}_not_a_table", "type", "view"),
        (f"{token}_not_a_table", "scanned_by", f"{token}_extra_seq"),
        (f"{token}_extra_seq", "type", "sequential_scan"),
        (f"{token}_unscanned_table", "type", "table"),
        (f"{token}_orphan_seq", "type", "sequential_scan"),
    ])

    random.SystemRandom().shuffle(triples)
    dependency_bytes = ("\n".join("\t".join(t) for t in triples) + "\n").encode("utf-8")
    expected = expected_from_tsv(dependency_bytes)
    assert expected != ["metadata", "products", "sessions"]

    try:
        data = run_program(executable, dependency_bytes)
        assert data == expected, f"For the changed graph, expected {expected}, got {data}."
    finally:
        with open(DEPS_FILE, "wb") as f:
            f.write(ORIGINAL_DEPS)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
