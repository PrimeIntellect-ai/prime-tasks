#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /tmp/pipeline_instrument

cat << 'PY_EOF' > /tmp/pipeline_instrument/sitecustomize.py
import os
import rdflib.graph

_original_query = rdflib.graph.Graph.query

def _audited_query(self, query_object, *args, **kwargs):
    marker = os.environ.get("SPARQL_MARKER")
    if marker:
        with open(marker, "a", encoding="utf-8") as f:
            f.write("query executed\n")
    return _original_query(self, query_object, *args, **kwargs)

rdflib.graph.Graph.query = _audited_query
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import pytest

RESULT_FILE = "/home/user/result.json"
PIPELINE_FILE = "/home/user/pipeline.py"
ORG_FILE = "/home/user/org.ttl"
INSTRUMENT_DIR = "/tmp/pipeline_instrument"
INITIAL_MARKER = None
ORIGINAL_ORG = None


def run_pipeline():
    marker = f"/tmp/sparql-marker-{secrets.token_hex(12)}"
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)

    env = os.environ.copy()
    env["SPARQL_MARKER"] = marker
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = INSTRUMENT_DIR + (os.pathsep + old_pythonpath if old_pythonpath else "")

    completed = subprocess.run(
        ["python3", PIPELINE_FILE],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "pipeline.py failed when executed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULT_FILE), f"The executed pipeline did not generate {RESULT_FILE}."

    queried = os.path.isfile(marker) and os.path.getsize(marker) > 0
    if os.path.exists(marker):
        os.remove(marker)
    return queried


@pytest.fixture(scope="module", autouse=True)
def execute_pipeline_on_original_graph():
    global INITIAL_MARKER, ORIGINAL_ORG
    assert os.path.isfile(PIPELINE_FILE), f"The script {PIPELINE_FILE} was not found."
    with open(ORG_FILE, "rb") as f:
        ORIGINAL_ORG = f.read()
    INITIAL_MARKER = run_pipeline()
    yield


def test_pipeline_script_exists():
    """Ensure the user created the pipeline script."""
    assert os.path.isfile(PIPELINE_FILE), f"The script {PIPELINE_FILE} was not found."


def test_result_json_exists():
    """Ensure the result.json file was generated."""
    assert os.path.isfile(RESULT_FILE), f"The output file {RESULT_FILE} was not found."


def test_result_json_content():
    """Verify that the result.json contains the correct aggregated and paginated data."""
    with open(RESULT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULT_FILE} does not contain valid JSON.")

    assert isinstance(data, list), f"Expected the JSON root to be a list, but got {type(data).__name__}."
    assert len(data) == 2, f"Expected exactly 2 records in the output (pagination limit 2), but got {len(data)}."

    expected_data = [
        {"department": "HR", "avg_tenure": 15.0},
        {"department": "Analytics", "avg_tenure": 12.0},
    ]

    for i, expected_record in enumerate(expected_data):
        assert data[i].get("department") == expected_record["department"], \
            f"Record {i+1} department mismatch. Expected '{expected_record['department']}', got '{data[i].get('department')}'."
        assert abs(float(data[i].get("avg_tenure", 0)) - expected_record["avg_tenure"]) < 1e-5, \
            f"Record {i+1} avg_tenure mismatch. Expected {expected_record['avg_tenure']}, got {data[i].get('avg_tenure')}."


def test_pipeline_executes_sparql():
    assert INITIAL_MARKER, "pipeline.py did not execute an rdflib SPARQL Graph.query call."


def test_pipeline_processes_changed_graph_and_derives_results():
    token = secrets.token_hex(5)
    high = 30 + secrets.randbelow(20)
    tied = high - 5
    low = high - 11

    departments = {
        "z": f"Zulu-{token}",
        "h": f"Gamma-{token}",
        "a": f"Alpha-{token}",
        "l": f"Omega-{token}",
    }
    managers = [
        ("z", tied - 2, 2),
        ("z", tied + 2, 3),
        ("h", high, 2),
        ("h", 999, 1),  # Not a Key Manager and must not affect the average.
        ("a", tied, 2),
        ("l", low, 2),
    ]

    lines = [
        "@prefix ex: <http://example.org/> .",
        "@prefix foaf: <http://xmlns.com/foaf/0.1/> .",
        "",
    ]
    for key, label in departments.items():
        lines.append(f'ex:Dept_{key}_{token} a ex:Department ; foaf:name "{label}" .')

    grouped_tenures = {}
    for index, (dept_key, tenure, report_count) in enumerate(managers):
        manager = f"Manager_{index}_{token}"
        reports = [f"Report_{index}_{j}_{token}" for j in range(report_count)]
        report_list = ", ".join(f"ex:{name}" for name in reports)
        lines.append(
            f'ex:{manager} a ex:Employee ; foaf:name "Manager {index} {token}" ; '
            f'ex:worksIn ex:Dept_{dept_key}_{token} ; ex:tenure {tenure} ; ex:manages {report_list} .'
        )
        for j, report in enumerate(reports):
            lines.append(
                f'ex:{report} a ex:Employee ; foaf:name "Report {index}-{j} {token}" ; '
                f'ex:worksIn ex:Dept_{dept_key}_{token} ; ex:tenure 1 .'
            )
        if report_count >= 2:
            grouped_tenures.setdefault(departments[dept_key], []).append(tenure)

    expected = [
        {"department": department, "avg_tenure": sum(values) / len(values)}
        for department, values in grouped_tenures.items()
    ]
    expected.sort(key=lambda row: (-row["avg_tenure"], row["department"]))
    expected = expected[:2]

    try:
        with open(ORG_FILE, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

        queried = run_pipeline()
        assert queried, "pipeline.py did not execute SPARQL while processing the changed graph."

        with open(RESULT_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        assert isinstance(data, list), "Expected the changed-graph output to be a JSON list."
        assert len(data) == 2, f"Expected exactly 2 paginated records, got {len(data)}."
        for i, expected_record in enumerate(expected):
            assert data[i].get("department") == expected_record["department"], (
                f"Changed-graph record {i+1} has the wrong department."
            )
            assert abs(float(data[i].get("avg_tenure", 0)) - expected_record["avg_tenure"]) < 1e-5, (
                f"Changed-graph record {i+1} has the wrong average tenure."
            )
    finally:
        with open(ORG_FILE, "wb") as f:
            f.write(ORIGINAL_ORG)
        run_pipeline()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
