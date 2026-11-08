#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /home/user/access_graph.ttl /tmp/access_graph.original.ttl
cleanup() {
    cp /tmp/access_graph.original.ttl /home/user/access_graph.ttl
}
trap cleanup EXIT

mkdir -p /tmp/audit_instrument
cat << 'PY_EOF' > /tmp/audit_instrument/sitecustomize.py
import os
import rdflib

_trace_path = os.environ.get("AUDIT_TRACE_PATH")
_trace_token = os.environ.get("AUDIT_TRACE_TOKEN", "")


def _record(event):
    if _trace_path:
        with open(_trace_path, "a", encoding="utf-8") as f:
            f.write(_trace_token + ":" + event + "\n")


_original_parse = rdflib.graph.Graph.parse
_original_query = rdflib.graph.Graph.query


def _traced_parse(self, *args, **kwargs):
    _record("PARSE")
    return _original_parse(self, *args, **kwargs)


def _traced_query(self, *args, **kwargs):
    _record("QUERY")
    return _original_query(self, *args, **kwargs)


rdflib.graph.Graph.parse = _traced_parse
rdflib.graph.Graph.query = _traced_query
PY_EOF
chmod -R a-w /tmp/audit_instrument

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
import tempfile

import pytest
from rdflib import Graph, Literal, Namespace, RDF

SCRIPT = "/home/user/audit.py"
CSV_PATH = "/home/user/violations.csv"
GRAPH_PATH = "/home/user/access_graph.ttl"
INSTRUMENT_DIR = "/tmp/audit_instrument"


def run_audit():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)

    token = secrets.token_hex(16)
    fd, trace_path = tempfile.mkstemp(prefix="audit_trace_")
    os.close(fd)
    os.remove(trace_path)

    env = os.environ.copy()
    env["AUDIT_TRACE_PATH"] = trace_path
    env["AUDIT_TRACE_TOKEN"] = token
    env["PYTHONPATH"] = INSTRUMENT_DIR + os.pathsep + env.get("PYTHONPATH", "")

    try:
        result = subprocess.run(
            ["python3", SCRIPT],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"audit.py exited with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(trace_path), "audit.py did not use the instrumented rdflib API."
        with open(trace_path, encoding="utf-8") as f:
            events = {line.strip() for line in f}
        assert token + ":PARSE" in events, "audit.py must load the RDF graph using rdflib."
        assert token + ":QUERY" in events, "audit.py must execute a SPARQL query using rdflib."
    finally:
        if os.path.exists(trace_path):
            os.remove(trace_path)


def read_csv():
    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        return list(csv.reader(f))


def test_audit_script_exists_and_runs():
    assert os.path.isfile(SCRIPT), f"The required script {SCRIPT} does not exist."
    run_audit()


def test_violations_csv_exists():
    """Check if the violations.csv file exists."""
    file_path = "/home/user/violations.csv"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist. Did you run your script to generate it?"


def test_violations_csv_content():
    """Check if the violations.csv file contains the correct headers and data in the correct order."""
    file_path = "/home/user/violations.csv"
    if not os.path.isfile(file_path):
        pytest.fail(f"The file {file_path} does not exist.")

    expected_rows = [
        ["EmployeeID", "Name", "Department"],
        ["http://example.org/emp1", "Alice Smith", "Engineering"],
        ["http://example.org/emp5", "Eve Brown", "IT"]
    ]

    with open(file_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, "The violations.csv file is empty."
    assert actual_rows[0] == expected_rows[0], f"Headers in violations.csv are incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}"
    assert actual_rows == expected_rows, (
        "The contents of violations.csv do not match the expected output. "
        "Ensure you are finding employees with access to both FinancialSystem and HRSystem "
        "who are not in the Executive department, and that the rows are sorted alphabetically by EmployeeID."
    )


def test_audit_handles_derived_graph():
    ex = Namespace("http://example.org/")
    foaf = Namespace("http://xmlns.com/foaf/0.1/")
    suffix = secrets.token_hex(6)

    records = [
        (f"staff-{suffix}-z", "Zara Mills", "Engineering", True, True),
        (f"staff-{suffix}-a", "Aaron Cole", "Legal", True, True),
        (f"staff-{suffix}-m", "Mina Park", "IT", True, True),
        (f"staff-{suffix}-exec", "Erin Chief", "Executive", True, True),
        (f"staff-{suffix}-finance", "Finn Gray", "Finance", True, False),
        (f"staff-{suffix}-hr", "Hana Reed", "HR", False, True),
    ]

    graph = Graph()
    for employee_id, name, department, financial, hr in records:
        employee = ex[employee_id]
        graph.add((employee, RDF.type, ex.Employee))
        graph.add((employee, foaf.name, Literal(name)))
        graph.add((employee, ex.department, Literal(department)))
        if financial:
            graph.add((employee, ex.hasAccessTo, ex.FinancialSystem))
        if hr:
            graph.add((employee, ex.hasAccessTo, ex.HRSystem))
    graph.add((ex.FinancialSystem, RDF.type, ex.System))
    graph.add((ex.HRSystem, RDF.type, ex.System))
    graph.serialize(destination=GRAPH_PATH, format="turtle")

    expected_data = sorted(
        [[str(ex[employee_id]), name, department]
         for employee_id, name, department, financial, hr in records
         if financial and hr and department != "Executive"],
        key=lambda row: row[0],
    )
    expected_rows = [["EmployeeID", "Name", "Department"]] + expected_data

    run_audit()
    assert os.path.isfile(CSV_PATH), "audit.py did not generate violations.csv for the derived graph."
    assert read_csv() == expected_rows, (
        "audit.py did not derive the correct sorted SoD violations from a changed RDF graph."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
