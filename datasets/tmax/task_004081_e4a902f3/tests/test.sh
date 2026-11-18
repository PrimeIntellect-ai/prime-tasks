#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import textwrap
from pathlib import Path

import pytest

SCRIPT_PATH = Path("/home/user/audit_script.py")
REPORT_PATH = Path("/home/user/compliance_audit_report.json")
RDF_PATH = Path("/home/user/org_architecture.ttl")
PROBE_DIR = Path("/tmp/audit_probe")
PROBE_LOG = Path("/tmp/audit_query_log.jsonl")

ORIGINAL_RDF = RDF_PATH.read_bytes()

PROBE_DIR.mkdir(exist_ok=True)
(PROBE_DIR / "sitecustomize.py").write_text(textwrap.dedent(r'''\
import json
import os

try:
    import rdflib

    _original_query = rdflib.graph.Graph.query

    def _logged_query(self, query_object, *args, **kwargs):
        path = os.environ.get("AUDIT_QUERY_LOG")
        if path:
            try:
                with open(path, "a", encoding="utf-8") as f:
                    f.write(json.dumps(str(query_object)) + "\\n")
            except Exception:
                pass
        return _original_query(self, query_object, *args, **kwargs)

    rdflib.graph.Graph.query = _logged_query
except Exception:
    pass
'''), encoding="utf-8")


def assert_required_sparql_queries():
    assert PROBE_LOG.is_file(), "The audit script did not execute RDFLib SPARQL queries."
    queries = []
    for line in PROBE_LOG.read_text(encoding="utf-8").splitlines():
        try:
            queries.append(json.loads(line).lower())
        except json.JSONDecodeError:
            pass

    assert len(queries) >= 2, "The script must run SPARQL queries for both compliance rules."

    sod_query_found = any(
        "hasrole" in q and "developer" in q and "auditor" in q
        for q in queries
    )
    lp_query_found = any(
        all(term in q for term in (
            "hasrole", "developer", "hasaccess", "targetresource",
            "accesstype", "production_db", "write"
        ))
        for q in queries
    )
    assert sod_query_found, "No SPARQL query extracting Developer/Auditor SoD violations was executed."
    assert lp_query_found, "No SPARQL query extracting Developer WRITE access to Production_DB was executed."


def run_audit(ttl_text=None):
    assert SCRIPT_PATH.exists(), f"Audit script {SCRIPT_PATH} does not exist."
    assert SCRIPT_PATH.is_file(), f"Path {SCRIPT_PATH} is not a file."
    assert SCRIPT_PATH.stat().st_size > 0, "The audit script is empty."

    if ttl_text is not None:
        RDF_PATH.write_text(textwrap.dedent(ttl_text), encoding="utf-8")

    REPORT_PATH.unlink(missing_ok=True)
    PROBE_LOG.unlink(missing_ok=True)

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = str(PROBE_DIR) + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["AUDIT_QUERY_LOG"] = str(PROBE_LOG)

    result = subprocess.run(
        ["python3", str(SCRIPT_PATH)],
        cwd="/home/user",
        env=env,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Audit script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert REPORT_PATH.is_file(), "Running the audit script did not create the JSON report."
    assert_required_sparql_queries()

    try:
        with REPORT_PATH.open("r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON report after running the script: {e}")


@pytest.fixture(scope="module", autouse=True)
def execute_original_submission():
    RDF_PATH.write_bytes(ORIGINAL_RDF)
    run_audit()
    yield
    RDF_PATH.write_bytes(ORIGINAL_RDF)


def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"Path {REPORT_PATH} is not a file."


def test_report_format_and_content():
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON report: {e}")

    assert "total_violations" in data, "Key 'total_violations' missing from report."
    assert "high_risk_users" in data, "Key 'high_risk_users' missing from report."

    assert data["total_violations"] == 3, f"Expected 3 total violations, got {data['total_violations']}"

    high_risk_users = data["high_risk_users"]
    assert isinstance(high_risk_users, list), "'high_risk_users' should be a list."
    assert len(high_risk_users) == 2, f"Expected 2 high risk users, got {len(high_risk_users)}"

    user_uris = [u.get("user_uri") for u in high_risk_users]
    assert user_uris == sorted(user_uris), "The 'high_risk_users' list must be sorted alphabetically by 'user_uri'."

    bob = next((u for u in high_risk_users if u.get("user_uri") == "http://example.org/ns#Bob"), None)
    dave = next((u for u in high_risk_users if u.get("user_uri") == "http://example.org/ns#Dave"), None)

    assert bob is not None, "User Bob is missing from high_risk_users."
    assert dave is not None, "User Dave is missing from high_risk_users."

    bob_violations = bob.get("violations", [])
    assert isinstance(bob_violations, list), "Bob's 'violations' should be a list."
    assert bob_violations == sorted(bob_violations), "Bob's violations must be sorted alphabetically."
    assert bob_violations == ["LP_Dev_Write_Prod", "SoD_Dev_Auditor"], f"Bob's violations are incorrect: {bob_violations}"

    dave_violations = dave.get("violations", [])
    assert isinstance(dave_violations, list), "Dave's 'violations' should be a list."
    assert dave_violations == sorted(dave_violations), "Dave's violations must be sorted alphabetically."
    assert dave_violations == ["LP_Dev_Write_Prod"], f"Dave's violations are incorrect: {dave_violations}"


def test_script_analyzes_changed_graph():
    changed_graph = '''
        @prefix org: <http://example.org/ns#> .

        org:Zoe a org:User ;
            org:hasRole org:Developer, org:Auditor ;
            org:hasAccess [
                org:targetResource org:Production_DB ;
                org:accessType "READ"
            ] .

        org:Amy a org:User ;
            org:hasRole org:Developer ;
            org:hasAccess [
                org:targetResource org:Production_DB ;
                org:accessType "WRITE"
            ] .

        org:Mike a org:User ;
            org:hasRole org:Developer, org:Auditor ;
            org:hasAccess [
                org:targetResource org:Production_DB ;
                org:accessType "WRITE"
            ] .

        org:NoRisk a org:User ;
            org:hasRole org:Admin ;
            org:hasAccess [
                org:targetResource org:Production_DB ;
                org:accessType "WRITE"
            ] .
    '''

    try:
        data = run_audit(changed_graph)
        expected = {
            "total_violations": 4,
            "high_risk_users": [
                {
                    "user_uri": "http://example.org/ns#Amy",
                    "violations": ["LP_Dev_Write_Prod"],
                },
                {
                    "user_uri": "http://example.org/ns#Mike",
                    "violations": ["LP_Dev_Write_Prod", "SoD_Dev_Auditor"],
                },
                {
                    "user_uri": "http://example.org/ns#Zoe",
                    "violations": ["SoD_Dev_Auditor"],
                },
            ],
        }
        assert data == expected, f"Incorrect report for a changed RDF graph: {data}"
    finally:
        RDF_PATH.write_bytes(ORIGINAL_RDF)
        run_audit()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
