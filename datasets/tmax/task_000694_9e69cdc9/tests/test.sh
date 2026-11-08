#!/bin/bash
set -u
mkdir -p /logs/verifier

mkdir -p /tmp/rdflib_instrumentation
cat << 'PY_EOF' > /tmp/rdflib_instrumentation/sitecustomize.py
import os
import rdflib

_original_query = rdflib.Graph.query

def _recording_query(self, *args, **kwargs):
    marker = os.environ.get("RDFLIB_QUERY_MARKER")
    if marker:
        with open(marker, "a", encoding="utf-8") as f:
            f.write("query\n")
    return _original_query(self, *args, **kwargs)

rdflib.Graph.query = _recording_query
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/detect_deadlocks.py"
LOCKS_PATH = "/home/user/locks.ttl"
JSON_PATH = "/home/user/deadlocks.json"
MARKER_PATH = "/tmp/rdflib_query_called"


def run_submission():
    if os.path.exists(MARKER_PATH):
        os.remove(MARKER_PATH)
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/rdflib_instrumentation" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    env["RDFLIB_QUERY_MARKER"] = MARKER_PATH

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"detect_deadlocks.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(MARKER_PATH), (
        "The script did not execute an rdflib Graph.query SPARQL query."
    )
    assert os.path.isfile(JSON_PATH), f"The script did not create {JSON_PATH}."

    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON: {exc}")


@pytest.fixture(scope="session", autouse=True)
def execute_script_and_restore_files():
    with open(LOCKS_PATH, "rb") as f:
        original_locks = f.read()

    initial_data = run_submission()
    with open(JSON_PATH, "rb") as f:
        original_result = f.read()

    yield initial_data

    with open(LOCKS_PATH, "wb") as f:
        f.write(original_locks)
    with open(JSON_PATH, "wb") as f:
        f.write(original_result)


def test_detect_deadlocks_script_exists():
    script_path = "/home/user/detect_deadlocks.py"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."


def test_deadlocks_json_exists_and_correct():
    json_path = "/home/user/deadlocks.json"
    assert os.path.exists(json_path), f"The output file {json_path} does not exist."
    assert os.path.isfile(json_path), f"The path {json_path} is not a file."

    with open(json_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    expected_deadlocks = ["T1", "T2", "T3", "T4", "T5"]

    assert isinstance(data, list), f"Expected the JSON output to be a list, but got {type(data).__name__}."
    assert data == expected_deadlocks, f"The deadlocks list is incorrect. Expected {expected_deadlocks}, but got {data}."


def write_graph(transactions):
    lines = ["@prefix ex: <http://example.org/> .", ""]
    for transaction, held, waited in transactions:
        lines.append(f"ex:{transaction} a ex:Transaction ;")
        if waited is None:
            lines.append(f"    ex:holds ex:{held} .")
        else:
            lines.append(f"    ex:holds ex:{held} ;")
            lines.append(f"    ex:waitsFor ex:{waited} .")
        lines.append("")
    with open(LOCKS_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def test_script_computes_randomized_two_and_three_transaction_cycles():
    token = secrets.token_hex(6)
    ids = {name: f"X{token}{name}" for name in "ABCDEFGHIJKL"}
    resources = {name: f"R{token}{name}" for name in "ABCDEFGHIJKL"}

    transactions = [
        # A-B is a two-transaction cycle.
        (ids["A"], resources["A"], resources["B"]),
        (ids["B"], resources["B"], resources["A"]),
        # C-D-E is a three-transaction cycle.
        (ids["C"], resources["C"], resources["D"]),
        (ids["D"], resources["D"], resources["E"]),
        (ids["E"], resources["E"], resources["C"]),
        # F-G-H is acyclic.
        (ids["F"], resources["F"], resources["G"]),
        (ids["G"], resources["G"], resources["H"]),
        (ids["H"], resources["H"], None),
        # I-J-K-L is a cycle of length four and must not be reported.
        (ids["I"], resources["I"], resources["J"]),
        (ids["J"], resources["J"], resources["K"]),
        (ids["K"], resources["K"], resources["L"]),
        (ids["L"], resources["L"], resources["I"]),
    ]
    write_graph(transactions)

    actual = run_submission()
    expected = sorted(ids[name] for name in "ABCDE")
    assert isinstance(actual, list), f"Expected a JSON list, got {type(actual).__name__}."
    assert actual == expected, f"Expected randomized deadlocks {expected}, but got {actual}."


def test_script_reports_empty_list_for_randomized_acyclic_graph():
    token = secrets.token_hex(6)
    a, b, c = (f"Y{token}{suffix}" for suffix in "ABC")
    ra, rb, rc = (f"Q{token}{suffix}" for suffix in "ABC")
    write_graph([
        (a, ra, rb),
        (b, rb, rc),
        (c, rc, None),
    ])

    actual = run_submission()
    assert isinstance(actual, list), f"Expected a JSON list, got {type(actual).__name__}."
    assert actual == [], f"Expected no deadlocks in an acyclic graph, but got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
