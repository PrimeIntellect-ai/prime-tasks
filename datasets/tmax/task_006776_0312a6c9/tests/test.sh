#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import pwd
import random
import secrets
import stat
import subprocess


def test_audit_script_exists():
    script_path = "/home/user/audit_script.py"
    assert os.path.exists(script_path), f"Expected script at {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_compliance_report_correctness():
    graph_path = "/home/user/audit_graph.json"
    report_path = "/home/user/compliance_report.csv"

    assert os.path.exists(graph_path), f"Input graph at {graph_path} is missing."
    assert os.path.exists(report_path), f"Output report at {report_path} was not generated."

    with open(graph_path, "r") as f:
        data = json.load(f)

    nodes = {n["id"]: n for n in data["nodes"]}
    edges = data["edges"]

    # Identify PII databases
    pii_dbs = {n["id"] for n in nodes.values() if n.get("type") == "Database" and n.get("contains_pii") is True}

    # Identify HR and Compliance departments
    allowed_depts = {n["id"] for n in nodes.values() if n.get("type") == "Department" and n.get("name") in ("HR", "Compliance")}

    # Map relationships
    employee_depts = {}
    employee_roles = {}
    role_dbs = {}

    for edge in edges:
        src, tgt, rel = edge["source"], edge["target"], edge["relationship"]
        if rel == "WORKS_IN":
            employee_depts.setdefault(src, set()).add(tgt)
        elif rel == "HAS_ROLE":
            employee_roles.setdefault(src, set()).add(tgt)
        elif rel == "CAN_ACCESS":
            role_dbs.setdefault(src, set()).add(tgt)

    # Calculate violations
    violations = []
    for node_id, node in nodes.items():
        if node.get("type") == "Employee":
            depts = employee_depts.get(node_id, set())
            if not depts.intersection(allowed_depts):
                # Check DB access
                roles = employee_roles.get(node_id, set())
                accessible_dbs = set()
                for r in roles:
                    accessible_dbs.update(role_dbs.get(r, set()))

                unauthorized_pii_dbs = accessible_dbs.intersection(pii_dbs)
                if unauthorized_pii_dbs:
                    violations.append({
                        "employee_id": node_id,
                        "employee_name": node["name"],
                        "unauthorized_db_count": len(unauthorized_pii_dbs)
                    })

    # Sort descending by count, ascending by name
    violations.sort(key=lambda x: (-x["unauthorized_db_count"], x["employee_name"]))
    expected_top_3 = violations[:3]

    # Read output CSV
    with open(report_path, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["employee_id", "employee_name", "unauthorized_db_count"], \
            "CSV header does not match the exact required format."

        rows = list(reader)

    assert len(rows) == len(expected_top_3), f"Expected {len(expected_top_3)} rows in CSV, found {len(rows)}."

    for i, (row, expected) in enumerate(zip(rows, expected_top_3)):
        assert row[0] == expected["employee_id"], f"Row {i+1}: expected employee_id {expected['employee_id']}, got {row[0]}"
        assert row[1] == expected["employee_name"], f"Row {i+1}: expected employee_name {expected['employee_name']}, got {row[1]}"
        assert row[2] == str(expected["unauthorized_db_count"]), f"Row {i+1}: expected unauthorized_db_count {expected['unauthorized_db_count']}, got {row[2]}"


def _expected_rows(data):
    nodes = {node["id"]: node for node in data["nodes"]}
    pii = {node_id for node_id, node in nodes.items()
           if node.get("type") == "Database" and node.get("contains_pii") is True}
    allowed = {node_id for node_id, node in nodes.items()
               if node.get("type") == "Department" and node.get("name") in ("HR", "Compliance")}
    depts, roles, accesses = {}, {}, {}
    for edge in data["edges"]:
        if edge["relationship"] == "WORKS_IN":
            depts.setdefault(edge["source"], set()).add(edge["target"])
        elif edge["relationship"] == "HAS_ROLE":
            roles.setdefault(edge["source"], set()).add(edge["target"])
        elif edge["relationship"] == "CAN_ACCESS":
            accesses.setdefault(edge["source"], set()).add(edge["target"])

    result = []
    for employee_id, node in nodes.items():
        if node.get("type") != "Employee" or depts.get(employee_id, set()) & allowed:
            continue
        databases = set()
        for role_id in roles.get(employee_id, set()):
            databases.update(accesses.get(role_id, set()))
        count = len(databases & pii)
        if count:
            result.append([employee_id, node["name"], str(count)])
    result.sort(key=lambda row: (-int(row[2]), row[1]))
    return result[:3]


def _dynamic_graph():
    token = secrets.token_hex(8)
    ident = lambda kind, n: f"{kind}_{n}_{token}"

    employees = [ident("employee", i) for i in range(6)]
    departments = [ident("department", i) for i in range(3)]
    roles = [ident("role", i) for i in range(7)]
    databases = [ident("database", i) for i in range(5)]

    nodes = [
        {"id": employees[0], "type": "Employee", "name": f"Alpha {token}"},
        {"id": employees[1], "type": "Employee", "name": f"Bravo {token}"},
        {"id": employees[2], "type": "Employee", "name": f"Charlie {token}"},
        {"id": employees[3], "type": "Employee", "name": f"Delta {token}"},
        {"id": employees[4], "type": "Employee", "name": f"Allowed HR {token}"},
        {"id": employees[5], "type": "Employee", "name": f"No PII {token}"},
        {"id": departments[0], "type": "Department", "name": "Engineering"},
        {"id": departments[1], "type": "Department", "name": "HR"},
        {"id": departments[2], "type": "Department", "name": "Compliance"},
    ]
    nodes.extend({"id": role, "type": "Role", "name": f"Role {i} {token}"} for i, role in enumerate(roles))
    nodes.extend(
        {"id": db, "type": "Database", "name": f"DB {i} {token}", "contains_pii": i < 4}
        for i, db in enumerate(databases)
    )

    edges = [
        {"source": employees[0], "target": departments[0], "relationship": "WORKS_IN"},
        {"source": employees[1], "target": departments[0], "relationship": "WORKS_IN"},
        {"source": employees[2], "target": departments[0], "relationship": "WORKS_IN"},
        {"source": employees[4], "target": departments[1], "relationship": "WORKS_IN"},
        {"source": employees[5], "target": departments[0], "relationship": "WORKS_IN"},
        {"source": employees[0], "target": roles[0], "relationship": "HAS_ROLE"},
        {"source": employees[1], "target": roles[1], "relationship": "HAS_ROLE"},
        {"source": employees[2], "target": roles[2], "relationship": "HAS_ROLE"},
        {"source": employees[2], "target": roles[3], "relationship": "HAS_ROLE"},
        {"source": employees[3], "target": roles[4], "relationship": "HAS_ROLE"},
        {"source": employees[4], "target": roles[5], "relationship": "HAS_ROLE"},
        {"source": employees[5], "target": roles[6], "relationship": "HAS_ROLE"},
    ]
    for db in databases[:4]:
        edges.append({"source": roles[0], "target": db, "relationship": "CAN_ACCESS"})
        edges.append({"source": roles[5], "target": db, "relationship": "CAN_ACCESS"})
    edges.extend([
        {"source": roles[0], "target": databases[0], "relationship": "CAN_ACCESS"},
        {"source": roles[1], "target": databases[0], "relationship": "CAN_ACCESS"},
        {"source": roles[1], "target": databases[1], "relationship": "CAN_ACCESS"},
        {"source": roles[2], "target": databases[0], "relationship": "CAN_ACCESS"},
        {"source": roles[3], "target": databases[0], "relationship": "CAN_ACCESS"},
        {"source": roles[3], "target": databases[1], "relationship": "CAN_ACCESS"},
        {"source": roles[4], "target": databases[2], "relationship": "CAN_ACCESS"},
        {"source": roles[6], "target": databases[4], "relationship": "CAN_ACCESS"},
    ])
    random.SystemRandom().shuffle(nodes)
    random.SystemRandom().shuffle(edges)
    return {"nodes": nodes, "edges": edges}


def test_script_executes_on_unseen_graph_and_generates_report():
    script_path = "/home/user/audit_script.py"
    graph_path = "/home/user/audit_graph.json"
    report_path = "/home/user/compliance_report.csv"
    home_path = "/home/user"

    with open(graph_path, "rb") as f:
        original_graph = f.read()
    with open(report_path, "rb") as f:
        original_report = f.read()
    graph_mode = stat.S_IMODE(os.stat(graph_path).st_mode)
    report_mode = stat.S_IMODE(os.stat(report_path).st_mode)
    home_mode = stat.S_IMODE(os.stat(home_path).st_mode)

    data = _dynamic_graph()
    expected = _expected_rows(data)
    assert len(expected) == 3

    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        os.chmod(home_path, 0o777)
        with open(graph_path, "w") as f:
            json.dump(data, f)
        os.chmod(graph_path, 0o666)
        if os.path.lexists(report_path):
            os.remove(report_path)

        completed = subprocess.run(
            ["python3", script_path],
            cwd=home_path,
            env={**os.environ, "HOME": home_path},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
            preexec_fn=demote,
        )
        assert completed.returncode == 0, \
            f"audit_script.py failed on a verifier-provided graph: {completed.stderr}"
        assert os.path.isfile(report_path), "The executed script did not generate compliance_report.csv."

        with open(graph_path, "r") as f:
            assert json.load(f) == data, "audit_script.py must not modify the input graph."
        with open(report_path, newline="") as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ["employee_id", "employee_name", "unauthorized_db_count"], \
            "Executed script produced an incorrect CSV header."
        assert rows[1:] == expected, \
            f"Executed script produced {rows[1:]!r}; expected {expected!r} for the verifier-provided graph."
    finally:
        with open(graph_path, "wb") as f:
            f.write(original_graph)
        os.chmod(graph_path, graph_mode)
        with open(report_path, "wb") as f:
            f.write(original_report)
        os.chmod(report_path, report_mode)
        os.chmod(home_path, home_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
