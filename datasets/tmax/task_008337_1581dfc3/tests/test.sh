#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from rdflib import Graph, Literal, Namespace, RDF
from rdflib.namespace import FOAF

SCRIPT_PATH = Path("/home/user/etl_script.py")
DATA_PATH = Path("/home/user/company_data.ttl")
OUTPUT_PATH = Path("/home/user/top_employees.json")
QUERY_LOG = Path("/tmp/etl_query.log")
HOOK_DIR = Path("/tmp/etl_verifier_hook")


def _install_query_hook():
    HOOK_DIR.mkdir(exist_ok=True)
    (HOOK_DIR / "sitecustomize.py").write_text(
        '''import os
from rdflib import Graph

_original_query = Graph.query

def _logged_query(self, query_object, *args, **kwargs):
    log_path = os.environ.get("ETL_QUERY_LOG")
    if log_path:
        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(str(query_object).replace("\\x00", ""))
            handle.write("\\n---QUERY---\\n")
    return _original_query(self, query_object, *args, **kwargs)

Graph.query = _logged_query
''',
        encoding="utf-8",
    )


def _run_script():
    _install_query_hook()
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    if QUERY_LOG.exists():
        QUERY_LOG.unlink()

    env = os.environ.copy()
    env["ETL_QUERY_LOG"] = str(QUERY_LOG)
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = str(HOOK_DIR) + (os.pathsep + old_pythonpath if old_pythonpath else "")

    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Running {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT_PATH.exists(), f"Running {SCRIPT_PATH} did not create {OUTPUT_PATH}."
    assert OUTPUT_PATH.is_file(), f"The path {OUTPUT_PATH} is not a file."


def _load_output():
    with OUTPUT_PATH.open("r", encoding="utf-8") as handle:
        try:
            return json.load(handle)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"The file {OUTPUT_PATH} does not contain valid JSON: {exc}")


def _assert_exact_output(actual_data, expected_data):
    assert isinstance(actual_data, list), f"The JSON output must be a list of objects, got {type(actual_data).__name__}."
    assert len(actual_data) == len(expected_data), f"Expected exactly {len(expected_data)} results, but got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert "name" in actual, f"Item at index {i} is missing the 'name' key."
        assert "project_count" in actual, f"Item at index {i} is missing the 'project_count' key."
        assert isinstance(actual["name"], str), f"The 'name' at index {i} should be a string."
        assert isinstance(actual["project_count"], int), f"The 'project_count' at index {i} should be an integer."
        assert actual["name"] == expected["name"], f"Expected name '{expected['name']}' at index {i}, but got '{actual['name']}'."
        assert actual["project_count"] == expected["project_count"], f"Expected project_count {expected['project_count']} for {expected['name']}, but got {actual['project_count']}."

    assert actual_data == expected_data, f"The JSON output does not exactly match the expected list of objects. Expected: {expected_data}, Got: {actual_data}"


def _write_dataset(specs, outsider_count=0):
    graph = Graph()
    ex = Namespace("http://verification.example/")
    for employee_index, (name, project_count) in enumerate(specs):
        employee = ex[f"employee-{employee_index}"]
        graph.add((employee, RDF.type, ex.Employee))
        graph.add((employee, FOAF.name, Literal(name)))
        for project_index in range(project_count):
            graph.add((employee, ex.worksOn, ex[f"project-{employee_index}-{project_index}"]))

    if outsider_count:
        outsider = ex.outsider
        graph.add((outsider, FOAF.name, Literal("Not An Employee")))
        for project_index in range(outsider_count):
            graph.add((outsider, ex.worksOn, ex[f"outsider-project-{project_index}"]))

    graph.serialize(destination=str(DATA_PATH), format="turtle")


def _expected_for(specs):
    eligible = [
        {"name": name, "project_count": count}
        for name, count in specs
        if count >= 2
    ]
    return sorted(eligible, key=lambda item: (-item["project_count"], item["name"]))[:3]


def _assert_sparql_query_was_used():
    assert QUERY_LOG.exists(), "The script did not execute rdflib.Graph.query()."
    queries = [part.strip() for part in QUERY_LOG.read_text(encoding="utf-8").split("---QUERY---") if part.strip()]
    assert queries, "No SPARQL query was captured while running the script."

    def is_required_query(query):
        normalized = re.sub(r"\s+", " ", query).lower()
        if not all(token in normalized for token in ("select", "workson", "name", "count", "group by", "order by")):
            return False
        if not re.search(r"\blimit\s+3\b", normalized):
            return False
        if not re.search(r"(?:>=\s*2|2\s*<=|>\s*1|1\s*<)", normalized):
            return False
        order_match = re.search(r"order\s+by\s+(.+?)(?:\blimit\b|\boffset\b|$)", normalized)
        if not order_match or "desc" not in order_match.group(1):
            return False
        order_clause = order_match.group(1)
        if "asc" not in order_clause and not re.search(r"desc\s*\(.*\)\s+[?$][a-z_]\w*", order_clause):
            return False
        return True

    assert any(is_required_query(query) for query in queries), (
        "The executed SPARQL query must perform the worksOn/name matching, COUNT aggregation, "
        "GROUP BY, at-least-2 filtering, descending count and ascending name ordering, and LIMIT 3."
    )


def test_etl_script_exists():
    script_path = "/home/user/etl_script.py"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."


def test_top_employees_json_output():
    _run_script()
    json_path = "/home/user/top_employees.json"
    assert os.path.exists(json_path), f"The output file {json_path} does not exist. Did you run your script?"
    assert os.path.isfile(json_path), f"The path {json_path} is not a file."

    with open(json_path, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {json_path} does not contain valid JSON."

    expected_data = [
        {"name": "Diana Prince", "project_count": 4},
        {"name": "Alice Smith", "project_count": 3},
        {"name": "Frank Miller", "project_count": 3}
    ]

    assert isinstance(actual_data, list), f"The JSON output must be a list of objects, got {type(actual_data).__name__}."
    assert len(actual_data) == 3, f"Expected exactly 3 results, but got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert "name" in actual, f"Item at index {i} is missing the 'name' key."
        assert "project_count" in actual, f"Item at index {i} is missing the 'project_count' key."
        assert isinstance(actual["name"], str), f"The 'name' at index {i} should be a string."
        assert isinstance(actual["project_count"], int), f"The 'project_count' at index {i} should be an integer."
        assert actual["name"] == expected["name"], f"Expected name '{expected['name']}' at index {i}, but got '{actual['name']}'."
        assert actual["project_count"] == expected["project_count"], f"Expected project_count {expected['project_count']} for {expected['name']}, but got {actual['project_count']}."

    assert actual_data == expected_data, f"The JSON output does not exactly match the expected list of objects. Expected: {expected_data}, Got: {actual_data}"


def test_script_executes_sparql_etl_on_changed_graphs():
    original_data = DATA_PATH.read_bytes()
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None
    try:
        datasets = [
            [("Zoe Zebra", 5), ("Aaron Able", 4), ("Bella Baker", 4), ("Mike Moon", 3), ("Amy Ash", 2), ("Solo Person", 1)],
            [("Nia North", 2), ("Omar Oak", 6), ("Pia Pine", 3), ("Quinn Quartz", 3), ("Below Threshold", 1)],
        ]
        for specs in datasets:
            _write_dataset(specs, outsider_count=9)
            _run_script()
            _assert_exact_output(_load_output(), _expected_for(specs))
            _assert_sparql_query_was_used()
    finally:
        DATA_PATH.write_bytes(original_data)
        if original_output is None:
            if OUTPUT_PATH.exists():
                OUTPUT_PATH.unlink()
        else:
            OUTPUT_PATH.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
