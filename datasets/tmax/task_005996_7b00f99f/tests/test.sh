#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifyhook
cat << 'HOOK_EOF' > /tmp/verifyhook/sitecustomize.py
import json
import os

try:
    import rdflib

    _log_path = os.environ.get("ORG_VERIFY_LOG")

    def _log(event):
        if not _log_path:
            return
        try:
            with open(_log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(event, sort_keys=True) + "\n")
        except Exception:
            pass

    _original_init = rdflib.Graph.__init__
    _original_add = rdflib.Graph.add
    _original_query = rdflib.Graph.query

    def _verified_init(self, *args, **kwargs):
        result = _original_init(self, *args, **kwargs)
        _log({"event": "graph_init"})
        return result

    def _verified_add(self, triple):
        try:
            _log({"event": "add", "predicate": str(triple[1])})
        except Exception:
            pass
        return _original_add(self, triple)

    def _verified_query(self, query_object, *args, **kwargs):
        init_bindings = kwargs.get("initBindings")
        if init_bindings is None and len(args) >= 4:
            init_bindings = args[3]

        bindings = {}
        if init_bindings:
            try:
                bindings = {str(k): str(v) for k, v in init_bindings.items()}
            except Exception:
                bindings = {"unreadable": repr(init_bindings)}

        if isinstance(query_object, str):
            query_text = query_object
        else:
            query_text = getattr(query_object, "_originalString", None) or str(query_object)

        _log({"event": "query", "query": query_text, "bindings": bindings})
        return _original_query(self, query_object, *args, **kwargs)

    rdflib.Graph.__init__ = _verified_init
    rdflib.Graph.add = _verified_add
    rdflib.Graph.query = _verified_query
except Exception:
    pass
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import stat
import subprocess
import uuid
from pathlib import Path

SCRIPT = Path("/home/user/analyze_org.py")
EMPLOYEES = Path("/home/user/employees.csv")
PROJECTS = Path("/home/user/projects.csv")
OUTPUT = Path("/home/user/subordinate_projects.csv")

ORIGINAL_EMPLOYEES = """emp_id,name,manager_id
E001,Alice CEO,
E002,Bob VP,E001
E003,Charlie Director,E002
E004,Diana Manager,E003
E005,Eve IC,E004
E006,Frank IC,E004
E007,Grace VP,E001
E008,Heidi IC,E007
E009,Ivan IC,E003
"""

ORIGINAL_PROJECTS = """project_id,project_name,emp_id
P1,Alpha,E005
P2,Beta,E005
P3,Gamma,E006
P4,Delta,E008
P5,Epsilon,E009
P6,Zeta,E002
P7,Eta,E003
"""

ORIGINAL_EXPECTED = [
    ["employee_name", "project_name"],
    ["Charlie Director", "Eta"],
    ["Eve IC", "Alpha"],
    ["Eve IC", "Beta"],
    ["Frank IC", "Gamma"],
    ["Ivan IC", "Epsilon"],
]


def replace_file(path, content):
    try:
        path.unlink()
    except FileNotFoundError:
        pass
    path.write_text(content, encoding="utf-8")


def install_fixture(employees, projects):
    replace_file(EMPLOYEES, employees)
    replace_file(PROJECTS, projects)


def read_output():
    assert OUTPUT.is_file(), f"The output file {OUTPUT} was not found."
    with OUTPUT.open("r", newline="", encoding="utf-8") as f:
        return list(csv.reader(f))


def run_script(target, label):
    try:
        OUTPUT.unlink()
    except FileNotFoundError:
        pass

    log_path = Path(f"/tmp/org_verify_{label}.jsonl")
    try:
        log_path.unlink()
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verifyhook" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    env["ORG_VERIFY_LOG"] = str(log_path)

    completed = subprocess.run(
        ["python3", str(SCRIPT), target],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"Script failed for target {target}.\nstdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )

    events = []
    if log_path.is_file():
        for line in log_path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                events.append(json.loads(line))
    return events


def assert_rdf_and_parameterized_recursive_query(events, target):
    assert any(e.get("event") == "graph_init" for e in events), (
        "The executed script did not construct an rdflib Graph."
    )

    predicates = {e.get("predicate") for e in events if e.get("event") == "add"}
    assert "http://example.org/reportsTo" in predicates, (
        "The RDF graph did not contain reportsTo triples in the required namespace."
    )
    assert "http://example.org/worksOn" in predicates, (
        "The RDF graph did not contain worksOn triples in the required namespace."
    )

    queries = [e for e in events if e.get("event") == "query"]
    assert queries, "The executed script did not call rdflib.Graph.query."

    recursive_queries = [
        e for e in queries
        if "reportsTo" in e.get("query", "")
        and re.search(r"reportsTo\s*>?\s*\+", e.get("query", ""), re.IGNORECASE)
    ]
    assert recursive_queries, (
        "No executed SPARQL query used a '+' property path over reportsTo."
    )

    assert any(
        target in value
        for event in recursive_queries
        for value in event.get("bindings", {}).values()
    ), "The target employee was not supplied to the recursive query as a parameter binding."


def check_invalid_argument_count():
    env = os.environ.copy()
    completed = subprocess.run(
        ["python3", str(SCRIPT)], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert completed.returncode != 0, "The script accepted zero command-line arguments."

    completed = subprocess.run(
        ["python3", str(SCRIPT), "E002", "EXTRA"], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert completed.returncode != 0, "The script accepted more than one command-line argument."


def test_complete_solution():
    # Preserve the original existence assertion and additionally ensure it is Python code.
    assert SCRIPT.is_file(), f"The script {SCRIPT} was not found."
    assert stat.S_ISREG(SCRIPT.stat().st_mode), f"{SCRIPT} is not a regular file."
    source = SCRIPT.read_text(encoding="utf-8")
    compile(source, str(SCRIPT), "exec")

    install_fixture(ORIGINAL_EMPLOYEES, ORIGINAL_PROJECTS)
    check_invalid_argument_count()

    # Execute the submitted artifact on the required fixed target and preserve the
    # original exact output assertion.
    install_fixture(ORIGINAL_EMPLOYEES, ORIGINAL_PROJECTS)
    original_events = run_script("E002", "original")
    actual = read_output()
    assert actual == ORIGINAL_EXPECTED, (
        f"The content of {OUTPUT} does not match the expected output.\n"
        f"Expected: {ORIGINAL_EXPECTED}\nActual: {actual}"
    )
    assert_rdf_and_parameterized_recursive_query(original_events, "E002")

    # Use fresh identifiers and names so a precomputed E002 CSV cannot pass.
    token = uuid.uuid4().hex[:10]
    root = f"R{token}"
    target = f"T{token}"
    direct_one = f"A{token}"
    child_without_project = f"B{token}"
    grandchild = f"C{token}"
    direct_without_project = f"D{token}"
    deep_child = f"F{token}"
    outsider = f"O{token}"
    outsider_child = f"Q{token}"

    dynamic_employees = f"""emp_id,name,manager_id
{root},Root {token},
{target},Target {token},{root}
{direct_one},Zelda {token},{target}
{child_without_project},Unused {token},{direct_one}
{grandchild},Aaron {token},{child_without_project}
{direct_without_project},NoProject {token},{target}
{deep_child},Mira {token},{direct_without_project}
{outsider},Outside {token},{root}
{outsider_child},Excluded {token},{outsider}
"""
    dynamic_projects = f"""project_id,project_name,emp_id
P{token}1,Omega {token},{direct_one}
P{token}2,Alpha {token},{direct_one}
P{token}3,Kappa {token},{grandchild}
P{token}4,Beta {token},{deep_child}
P{token}5,WrongBranch {token},{outsider_child}
P{token}6,TargetOwn {token},{target}
"""
    dynamic_expected = [
        ["employee_name", "project_name"],
        [f"Aaron {token}", f"Kappa {token}"],
        [f"Mira {token}", f"Beta {token}"],
        [f"Zelda {token}", f"Alpha {token}"],
        [f"Zelda {token}", f"Omega {token}"],
    ]

    install_fixture(dynamic_employees, dynamic_projects)
    dynamic_events = run_script(target, "dynamic")
    assert read_output() == dynamic_expected, (
        "The script did not correctly compute recursive, project-filtered, sorted "
        "results for a non-precomputed target and dataset."
    )
    assert_rdf_and_parameterized_recursive_query(dynamic_events, target)

    # Restore the supplied data and required final E002 output.
    install_fixture(ORIGINAL_EMPLOYEES, ORIGINAL_PROJECTS)
    final_events = run_script("E002", "final")
    assert read_output() == ORIGINAL_EXPECTED
    assert_rdf_and_parameterized_recursive_query(final_events, "E002")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
