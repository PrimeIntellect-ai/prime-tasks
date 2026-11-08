#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/sparql_instrument
cat << 'HOOK_EOF' > /tmp/sparql_instrument/sitecustomize.py
import json
import os

try:
    import rdflib
    import rdflib.plugins.sparql as sparql_module

    _prepared = {}
    _original_prepare = sparql_module.prepareQuery

    def _wrapped_prepare(queryString, initNs=None, base=None):
        result = _original_prepare(queryString, initNs=initNs, base=base)
        _prepared[id(result)] = {
            "query": str(queryString),
            "initNs": {str(k): str(v) for k, v in (initNs or {}).items()},
        }
        return result

    sparql_module.prepareQuery = _wrapped_prepare

    _original_query = rdflib.graph.Graph.query

    def _wrapped_query(self, query_object, *args, **kwargs):
        record = _prepared.get(id(query_object))
        if record is None:
            init_ns = kwargs.get("initNs")
            if init_ns is None and len(args) >= 3:
                init_ns = args[2]
            record = {
                "query": str(query_object),
                "initNs": {str(k): str(v) for k, v in (init_ns or {}).items()},
            }

        log_path = os.environ.get("SPARQL_AUDIT_LOG")
        if log_path:
            with open(log_path, "a", encoding="utf-8") as log_file:
                log_file.write(json.dumps(record) + "\n")

        return _original_query(self, query_object, *args, **kwargs)

    rdflib.graph.Graph.query = _wrapped_query
except Exception:
    pass
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import uuid
from collections import Counter

from rdflib import Graph, Namespace, RDF, URIRef

SCRIPT_PATH = "/home/user/find_conflicts.py"
REPORT_PATH = "/home/user/conflict_report.csv"
DATA_PATH = "/home/user/audit_data.ttl"
HOOK_DIR = "/tmp/sparql_instrument"
QUERY_LOG = "/tmp/find_conflicts_sparql.jsonl"
AUDIT = Namespace("http://example.org/audit#")


def read_report():
    actual_data = []
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:  # preserve the original verifier's handling of empty lines
                actual_data.append(row)
    return actual_data


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    if os.path.exists(QUERY_LOG):
        os.remove(QUERY_LOG)

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = HOOK_DIR + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["SPARQL_AUDIT_LOG"] = QUERY_LOG

    completed = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "find_conflicts.py did not run successfully.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Expected output file is missing: {REPORT_PATH}"


def assert_a_spql_query_computes(expected_rows):
    assert os.path.isfile(QUERY_LOG), "The script did not execute an rdflib Graph.query SPARQL query."
    with open(QUERY_LOG, "r", encoding="utf-8") as f:
        records = [json.loads(line) for line in f if line.strip()]
    assert records, "The script did not execute a SPARQL query."

    graph = Graph()
    graph.parse(DATA_PATH, format="turtle")
    expected = Counter(frozenset(row) for row in expected_rows)
    errors = []

    for record in records:
        try:
            result = graph.query(record["query"], initNs=record.get("initNs") or {})
            if getattr(result, "type", None) != "SELECT":
                continue
            rows = []
            valid = True
            for result_row in result:
                values = [str(value) for value in result_row if value is not None]
                if len(values) != 3:
                    valid = False
                    break
                rows.append(frozenset(values))
            if valid and Counter(rows) == expected:
                return
        except Exception as exc:
            errors.append(str(exc))

    detail = f" Query errors: {errors}" if errors else ""
    raise AssertionError(
        "No executed SPARQL SELECT query itself produced exactly the expected "
        "employee/vendor/system conflict matches." + detail
    )


def test_conflict_report_exists_and_correct():
    """Run the script and test both the supplied graph and an independently generated graph."""
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    try:
        # First execute against the supplied graph and preserve the original exact assertions.
        run_script()
        expected_data = [
            ["http://example.org/audit#emp3", "http://example.org/audit#vendor3", "http://example.org/audit#sysC"],
            ["http://example.org/audit#emp1", "http://example.org/audit#vendor1", "http://example.org/audit#sysA"],
        ]
        actual_data = read_report()
        assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows, but got {len(actual_data)}."
        for i, (actual_row, expected_row) in enumerate(zip(actual_data, expected_data)):
            assert actual_row == expected_row, f"Row {i+1} mismatch. Expected {expected_row}, got {actual_row}."
        assert_a_spql_query_computes(expected_data)

        # Replace the input with a fresh graph so a hardcoded report cannot pass.
        base = f"http://verification.invalid/{uuid.uuid4().hex}/"
        employees = [URIRef(base + name) for name in ("employee-z", "employee-m", "employee-a", "employee-decoy")]
        vendors = [URIRef(base + name) for name in ("vendor-z", "vendor-m", "vendor-a", "vendor-decoy")]
        systems = [URIRef(base + name) for name in ("system-z", "system-m", "system-a", "system-other")]

        graph = Graph()
        for employee in employees:
            graph.add((employee, RDF.type, AUDIT.Employee))
        for vendor in vendors:
            graph.add((vendor, RDF.type, AUDIT.Vendor))
        for system in systems:
            graph.add((system, RDF.type, AUDIT.System))

        admin_edges = set()
        consult_edges = set()
        service_edges = set()
        for index in range(3):
            admin_edges.add((employees[index], systems[index]))
            consult_edges.add((employees[index], vendors[index]))
            service_edges.add((vendors[index], systems[index]))
        admin_edges.add((employees[3], systems[0]))
        consult_edges.add((employees[3], vendors[3]))
        service_edges.add((vendors[3], systems[3]))

        for employee, system in admin_edges:
            graph.add((employee, AUDIT.hasAdminAccess, system))
        for employee, vendor in consult_edges:
            graph.add((employee, AUDIT.consultsFor, vendor))
        for vendor, system in service_edges:
            graph.add((vendor, AUDIT.providesServiceTo, system))
        graph.serialize(destination=DATA_PATH, format="turtle")

        derived = []
        for employee, system in admin_edges:
            for consulting_employee, vendor in consult_edges:
                if employee == consulting_employee and (vendor, system) in service_edges:
                    derived.append([str(employee), str(vendor), str(system)])
        expected_dynamic = sorted(derived, key=lambda row: row[0], reverse=True)

        run_script()
        actual_dynamic = read_report()
        assert actual_dynamic == expected_dynamic, (
            "The generated report was not the exact, headerless, three-column conflict result "
            "in descending employee_uri order. "
            f"Expected {expected_dynamic}, got {actual_dynamic}."
        )
        assert all(len(row) == 3 for row in actual_dynamic), "Every CSV row must contain exactly three columns."
        assert_a_spql_query_computes(expected_dynamic)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)


def test_find_conflicts_script_exists():
    """Test that the student's script was created."""
    assert os.path.isfile(SCRIPT_PATH), f"Expected script file is missing: {SCRIPT_PATH}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
