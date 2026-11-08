#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import runpy
import subprocess

import pytest
import rdflib

REPORT = "/home/user/report.py"
DATA = "/home/user/data.ttl"
SUMMARY = "/home/user/summary.csv"


@pytest.fixture(scope="session", autouse=True)
def execute_report():
    """The submitted artifact must itself generate the checked output."""
    if os.path.exists(SUMMARY):
        os.remove(SUMMARY)
    subprocess.run(
        ["python3", REPORT],
        cwd="/home/user",
        check=True,
        timeout=30,
    )


def read_csv(path):
    rows = []
    with open(path, "r", newline="") as f:
        for row in csv.reader(f):
            if row:
                rows.append(row)
    return rows


def test_summary_csv_exists():
    """Check that summary.csv was generated."""
    assert os.path.isfile(SUMMARY), "/home/user/summary.csv does not exist."


def test_summary_csv_content():
    """Check the required result for the supplied dataset."""
    expected = [
        ["Marketing", "110000"],
        ["Sales", "100000"],
    ]
    actual = read_csv(SUMMARY)
    assert actual == expected, f"Expected {expected}, but got {actual}. Ensure correct aggregation, filtering (>50000), sorting, and limits."


def test_report_py_parameterization():
    """Retain the original source-level parameterization assertions."""
    with open(REPORT, "r") as f:
        content = f.read()

    assert "initBindings" in content or "initBindings=" in content, "The script must use initBindings to pass the MIN_SALARY parameter securely."
    assert "MIN_SALARY" in content, "The script must still define and use MIN_SALARY."


def test_query_and_script_on_independent_dataset():
    """Exercise the script and the SPARQL it actually submits on non-oracle data."""
    dynamic_ttl = '''
@prefix ex: <http://example.org/> .

ex:A1 ex:salary 50000 ; ex:worksIn ex:AlphaDept .
ex:A2 ex:salary 150000 ; ex:worksIn ex:AlphaDept .
ex:B1 ex:salary 120000 ; ex:worksIn ex:BetaDept .
ex:B2 ex:salary 40000 ; ex:worksIn ex:BetaDept .
ex:C1 ex:salary 110000 ; ex:worksIn ex:GammaDept .
ex:D1 ex:salary 70000 ; ex:worksIn ex:DeltaDept .
ex:Unlinked ex:salary 999999 .

ex:AlphaDept ex:deptName "Alpha" .
ex:BetaDept ex:deptName "Beta" .
ex:GammaDept ex:deptName "Gamma" .
ex:DeltaDept ex:deptName "Delta" .
ex:EmptyDept ex:deptName "Empty" .
'''
    expected = [["Alpha", "150000"], ["Beta", "120000"]]

    with open(DATA, "rb") as f:
        original_data = f.read()
    original_summary = None
    if os.path.exists(SUMMARY):
        with open(SUMMARY, "rb") as f:
            original_summary = f.read()

    calls = []
    real_query = rdflib.Graph.query

    def recording_query(self, query_object, *args, **kwargs):
        calls.append((query_object, args, dict(kwargs)))
        return real_query(self, query_object, *args, **kwargs)

    try:
        with open(DATA, "w") as f:
            f.write(dynamic_ttl)
        if os.path.exists(SUMMARY):
            os.remove(SUMMARY)

        rdflib.Graph.query = recording_query
        runpy.run_path(REPORT, run_name="__main__")
        rdflib.Graph.query = real_query

        assert os.path.isfile(SUMMARY), "report.py did not generate summary.csv when executed."
        assert read_csv(SUMMARY) == expected, "report.py does not compute the result from a changed RDF graph."
        assert calls, "report.py did not execute an rdflib SPARQL query."

        matching_query = False
        for query_object, args, kwargs in calls:
            query_text = str(query_object)
            bindings = kwargs.get("initBindings")
            if not isinstance(bindings, dict) or not bindings:
                continue

            bound_threshold = False
            bound_names = []
            for key, value in bindings.items():
                bound_names.append(str(key).lstrip("?$"))
                python_value = value.toPython() if hasattr(value, "toPython") else value
                try:
                    if int(python_value) == 50000:
                        bound_threshold = True
                except (TypeError, ValueError):
                    pass
            if not bound_threshold:
                continue
            if not any(re.search(r"[?$]" + re.escape(name) + r"\b", query_text) for name in bound_names):
                continue

            required_patterns = [
                r"\bworksIn\b",
                r"\bAVG\s*\(",
                r"\bGROUP\s+BY\b",
                r"\bFILTER\s*\(",
                r">",
                r"\bORDER\s+BY\s+DESC\s*\(",
                r"\bLIMIT\s+2\b",
            ]
            if not all(re.search(pattern, query_text, re.IGNORECASE) for pattern in required_patterns):
                continue

            graph = rdflib.Graph()
            graph.parse(data=dynamic_ttl, format="turtle")
            try:
                query_rows = [[str(value) for value in row] for row in real_query(graph, query_object, *args, **kwargs)]
            except Exception:
                continue
            if query_rows == expected:
                matching_query = True
                break

        assert matching_query, "The executed SPARQL query must perform the relationship join, strict bound filter, AVG/GROUP BY, descending ordering, and LIMIT 2 using initBindings."
    finally:
        rdflib.Graph.query = real_query
        with open(DATA, "wb") as f:
            f.write(original_data)
        if original_summary is None:
            if os.path.exists(SUMMARY):
                os.remove(SUMMARY)
        else:
            with open(SUMMARY, "wb") as f:
                f.write(original_summary)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
