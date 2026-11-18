#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hook
cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os
import rdflib

_trace = os.environ.get("VERIFIER_TRACE")
_original_parse = rdflib.Graph.parse
_original_query = rdflib.Graph.query

def _write(event, value):
    if _trace:
        with open(_trace, "a", encoding="utf-8") as f:
            f.write(json.dumps({"event": event, "value": value}) + "\n")

def traced_parse(self, *args, **kwargs):
    _write("parse", {"args": [str(x) for x in args], "kwargs": {str(k): str(v) for k, v in kwargs.items()}})
    return _original_parse(self, *args, **kwargs)

def traced_query(self, query_object, *args, **kwargs):
    _write("query", str(query_object))
    return _original_query(self, query_object, *args, **kwargs)

rdflib.Graph.parse = traced_parse
rdflib.Graph.query = traced_query
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import subprocess
import uuid

SCRIPT = "/home/user/etl_graph.py"
INPUT = "/home/user/org_chart.ttl"
OUTPUT = "/home/user/projected.nt"
TRACE = "/tmp/etl_verifier_trace.jsonl"
HOOK_DIR = "/tmp/verifier_hook"


def run_etl():
    if os.path.exists(TRACE):
        os.remove(TRACE)

    env = os.environ.copy()
    env["VERIFIER_TRACE"] = TRACE
    env["PYTHONPATH"] = HOOK_DIR + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"ETL script failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    events = []
    if os.path.isfile(TRACE):
        with open(TRACE, encoding="utf-8") as f:
            events = [json.loads(line) for line in f if line.strip()]

    parse_events = [e["value"] for e in events if e.get("event") == "parse"]
    assert parse_events, "The ETL script did not load an RDF graph with rdflib.Graph.parse()."
    assert any("org_chart.ttl" in json.dumps(e) for e in parse_events), \
        "The ETL script did not load /home/user/org_chart.ttl with rdflib."

    queries = [e["value"] for e in events if e.get("event") == "query"]
    assert queries, "The ETL script did not execute an rdflib SPARQL query."
    assert any(
        q.count("reportsTo") >= 2 and ("+" in q or "*" in q)
        for q in queries
    ), "The executed SPARQL must recursively traverse reportsTo and require a chain of at least two edges."


def read_projected_subjects():
    with open(OUTPUT, "r") as f:
        lines = f.readlines()

    actual_subjects = set()
    for line in lines:
        line = line.strip()
        if not line:
            continue

        match = re.match(r'^(<[^>]+>)\s+(<[^>]+>)\s+(<[^>]+>)\s*\.$', line)
        assert match, f"Line does not match N-Triples format: '{line}'"
        subj, pred, obj = match.groups()
        expected_pred = "<http://example.org/org#deepReportsTo>"
        expected_obj = "<http://example.org/CEO>"
        assert pred == expected_pred, f"Unexpected predicate '{pred}' found. Expected '{expected_pred}'."
        assert obj == expected_obj, f"Unexpected object '{obj}' found. Expected '{expected_obj}'."
        actual_subjects.add(subj)
    return actual_subjects


def test_etl_script_exists_and_uses_rdflib_query():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist."
    with open(SCRIPT, encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    imports_rdflib = any(
        (isinstance(node, ast.Import) and any(alias.name == "rdflib" or alias.name.startswith("rdflib.") for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module and (node.module == "rdflib" or node.module.startswith("rdflib.")))
        for node in ast.walk(tree)
    )
    assert imports_rdflib, "etl_graph.py must use the rdflib library."
    assert any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "query" for node in ast.walk(tree)), \
        "etl_graph.py must execute a SPARQL query using rdflib.Graph.query()."


def test_script_executes_on_supplied_graph():
    run_etl()


def test_projected_nt_exists():
    path = "/home/user/projected.nt"
    assert os.path.isfile(path), f"File {path} does not exist. The script did not generate the output file."


def test_projected_nt_contents():
    path = "/home/user/projected.nt"
    with open(path, "r") as f:
        lines = f.readlines()

    actual_subjects = set()

    for line in lines:
        line = line.strip()
        if not line:
            continue

        # Match N-Triples format: <subject> <predicate> <object> .
        match = re.match(r'^(<[^>]+>)\s+(<[^>]+>)\s+(<[^>]+>)\s*\.$', line)
        assert match, f"Line does not match N-Triples format: '{line}'"

        subj, pred, obj = match.groups()

        expected_pred = "<http://example.org/org#deepReportsTo>"
        expected_obj = "<http://example.org/CEO>"

        assert pred == expected_pred, f"Unexpected predicate '{pred}' found. Expected '{expected_pred}'."
        assert obj == expected_obj, f"Unexpected object '{obj}' found. Expected '{expected_obj}'."

        actual_subjects.add(subj)

    expected_subjects = {
        "<http://example.org/Bob>",
        "<http://example.org/Charlie>",
        "<http://example.org/Dave>",
        "<http://example.org/Frank>",
        "<http://example.org/Grace>"
    }

    missing = expected_subjects - actual_subjects
    extra = actual_subjects - expected_subjects

    assert not missing, f"Missing deep reports in output: {missing}"
    assert not extra, f"Extra incorrect reports found in output: {extra}"
    assert actual_subjects == expected_subjects


def test_pipeline_on_unseen_graph():
    with open(INPUT, "rb") as f:
        original_input = f.read()

    token = uuid.uuid4().hex
    base = "http://example.org/verify_" + token + "_"
    ceo = "http://example.org/CEO"
    reports = "http://example.org/org#reportsTo"

    direct1 = base + "direct1"
    direct2 = base + "direct2"
    depth2a = base + "depth2a"
    depth2b = base + "depth2b"
    depth3 = base + "depth3"
    depth4 = base + "depth4"
    detached1 = base + "detached1"
    detached2 = base + "detached2"
    cycle1 = base + "cycle1"
    cycle2 = base + "cycle2"

    edges = [
        (direct1, ceo),
        (direct2, ceo),
        (depth2a, direct1),
        (depth2b, direct2),
        (depth3, depth2a),
        (depth4, depth3),
        (detached1, detached2),
        (cycle1, cycle2),
        (cycle2, cycle1),
    ]

    # Derive the expected answer from the generated topology rather than trusting
    # a fixed list of employee names.
    parent = dict(edges)
    expected = set()
    for employee in parent:
        current = employee
        visited = set()
        distance = 0
        while current in parent and current not in visited:
            visited.add(current)
            current = parent[current]
            distance += 1
            if current == ceo:
                if distance >= 2:
                    expected.add(f"<{employee}>")
                break

    turtle = "\n".join(f"<{s}> <{reports}> <{o}> ." for s, o in edges) + "\n"

    try:
        with open(INPUT, "w", encoding="utf-8") as f:
            f.write(turtle)
        run_etl()
        assert os.path.isfile(OUTPUT), "The executed ETL script did not create projected.nt for an unseen input graph."
        actual = read_projected_subjects()
        assert actual == expected, f"Incorrect deep reports for unseen input. Expected {expected}, got {actual}."
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
