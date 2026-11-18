#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_audit_behavior.py
import json
import os
import random
import secrets
import shutil
import stat
import subprocess
import sys

AUDIT_PATH = '/home/user/audit.py'
GRAPH_PATH = '/home/user/graph.json'
RESULTS_PATH = '/home/user/audit_results.json'

CANONICAL_GRAPH = {
    "nodes": [
        {"id": "E1", "label": "Employee", "name": "Alice"},
        {"id": "E2", "label": "Employee", "name": "Bob"},
        {"id": "E3", "label": "Employee", "name": "Charlie"},
        {"id": "E4", "label": "Employee", "name": "Diana"},
        {"id": "E5", "label": "Employee", "name": "Eve"},
        {"id": "R1", "label": "Role", "name": "Admin"},
        {"id": "R2", "label": "Role", "name": "User"},
        {"id": "R3", "label": "Role", "name": "Manager"},
        {"id": "R4", "label": "Role", "name": "Auditor"},
        {"id": "S1", "label": "System", "name": "FinancialDB", "sensitivity": "HIGH"},
        {"id": "S2", "label": "System", "name": "HR_Portal", "sensitivity": "HIGH"},
        {"id": "S3", "label": "System", "name": "PublicSite", "sensitivity": "LOW"},
        {"id": "S4", "label": "System", "name": "CustomerData", "sensitivity": "HIGH"},
        {"id": "S5", "label": "System", "name": "LogServer", "sensitivity": "HIGH"}
    ],
    "edges": [
        {"source": "E1", "target": "R1", "type": "HAS_ROLE"},
        {"source": "E1", "target": "R2", "type": "HAS_ROLE"},
        {"source": "E2", "target": "R2", "type": "HAS_ROLE"},
        {"source": "E3", "target": "R3", "type": "HAS_ROLE"},
        {"source": "E4", "target": "R4", "type": "HAS_ROLE"},
        {"source": "E5", "target": "R1", "type": "HAS_ROLE"},
        {"source": "R1", "target": "S1", "type": "HAS_ACCESS"},
        {"source": "R1", "target": "S2", "type": "HAS_ACCESS"},
        {"source": "R1", "target": "S4", "type": "HAS_ACCESS"},
        {"source": "R1", "target": "S5", "type": "HAS_ACCESS"},
        {"source": "R2", "target": "S3", "type": "HAS_ACCESS"},
        {"source": "R3", "target": "S2", "type": "HAS_ACCESS"},
        {"source": "R4", "target": "S5", "type": "HAS_ACCESS"}
    ]
}

def expected_results(data):
    nodes = {n['id']: n for n in data.get('nodes', [])}
    has_role = {}
    has_access = {}
    for edge in data.get('edges', []):
        if edge.get('type') == 'HAS_ROLE':
            has_role.setdefault(edge['source'], []).append(edge['target'])
        elif edge.get('type') == 'HAS_ACCESS':
            has_access.setdefault(edge['source'], []).append(edge['target'])

    results = []
    for emp_id, role_ids in has_role.items():
        employee = nodes.get(emp_id)
        if not employee or employee.get('label') != 'Employee':
            continue
        for role_id in role_ids:
            role = nodes.get(role_id)
            if not role or role.get('label') != 'Role':
                continue
            for system_id in has_access.get(role_id, []):
                system = nodes.get(system_id)
                if not system or system.get('label') != 'System':
                    continue
                if system.get('sensitivity') == 'HIGH':
                    results.append({"employee": employee['name'], "system": system['name']})
    results.sort(key=lambda item: (item['employee'], item['system']))
    return results[:5]

def remove_path(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

def write_graph(data):
    remove_path(GRAPH_PATH)
    temporary = GRAPH_PATH + '.verifier.tmp'
    remove_path(temporary)
    with open(temporary, 'w', encoding='utf-8') as handle:
        json.dump(data, handle)
    os.replace(temporary, GRAPH_PATH)

def run_case(data, description):
    write_graph(data)
    remove_path(RESULTS_PATH)

    completed = subprocess.run(
        [sys.executable, AUDIT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10
    )
    assert completed.returncode == 0, (
        f"audit.py failed for {description} with exit code {completed.returncode}: "
        f"{completed.stderr}"
    )

    assert os.path.isfile(RESULTS_PATH), (
        f"File {RESULTS_PATH} is missing after running audit.py for {description}."
    )
    with open(RESULTS_PATH, 'r', encoding='utf-8') as handle:
        try:
            actual = json.load(handle)
        except json.JSONDecodeError as error:
            raise AssertionError(f"File {RESULTS_PATH} does not contain valid JSON: {error}")

    expected = expected_results(data)
    assert isinstance(actual, list), (
        f"Expected the results to be a JSON array (list), got {type(actual).__name__}"
    )
    assert len(actual) == len(expected), (
        f"For {description}, expected {len(expected)} results, got {len(actual)}"
    )
    for index, (actual_item, expected_item) in enumerate(zip(actual, expected)):
        assert actual_item == expected_item, (
            f"For {description}, mismatch at index {index}. "
            f"Expected {expected_item}, but got {actual_item}"
        )

def randomized_graph():
    token = secrets.token_hex(8)
    employee_ids = [f"emp-{token}-{i}" for i in range(7)]
    role_ids = [f"role-{token}-{i}" for i in range(4)]
    system_ids = [f"sys-{token}-{i}" for i in range(6)]

    employee_names = [f"Employee_{secrets.token_hex(3)}_{i}" for i in range(7)]
    role_names = [f"Role_{secrets.token_hex(3)}_{i}" for i in range(4)]
    system_names = [f"System_{secrets.token_hex(3)}_{i}" for i in range(6)]

    nodes = [
        *[{"id": employee_ids[i], "label": "Employee", "name": employee_names[i]} for i in range(7)],
        *[{"id": role_ids[i], "label": "Role", "name": role_names[i]} for i in range(4)],
        {"id": system_ids[0], "label": "System", "name": system_names[0], "sensitivity": "HIGH"},
        {"id": system_ids[1], "label": "System", "name": system_names[1], "sensitivity": "LOW"},
        {"id": system_ids[2], "label": "System", "name": system_names[2], "sensitivity": "HIGH"},
        {"id": system_ids[3], "label": "System", "name": system_names[3], "sensitivity": "HIGH"},
        {"id": system_ids[4], "label": "System", "name": system_names[4], "sensitivity": "high"},
        {"id": system_ids[5], "label": "System", "name": system_names[5], "sensitivity": "HIGH"},
        {"id": f"decoy-{token}", "label": "Asset", "name": "Decoy", "sensitivity": "HIGH"}
    ]
    edges = [
        {"source": employee_ids[0], "target": role_ids[0], "type": "HAS_ROLE"},
        {"source": employee_ids[0], "target": role_ids[1], "type": "HAS_ROLE"},
        {"source": employee_ids[1], "target": role_ids[1], "type": "HAS_ROLE"},
        {"source": employee_ids[2], "target": role_ids[2], "type": "HAS_ROLE"},
        {"source": employee_ids[3], "target": role_ids[3], "type": "HAS_ROLE"},
        {"source": employee_ids[4], "target": role_ids[0], "type": "HAS_ROLE"},
        {"source": role_ids[0], "target": system_ids[0], "type": "HAS_ACCESS"},
        {"source": role_ids[0], "target": system_ids[1], "type": "HAS_ACCESS"},
        {"source": role_ids[0], "target": system_ids[2], "type": "HAS_ACCESS"},
        {"source": role_ids[1], "target": system_ids[3], "type": "HAS_ACCESS"},
        {"source": role_ids[1], "target": system_ids[4], "type": "HAS_ACCESS"},
        {"source": role_ids[2], "target": system_ids[5], "type": "HAS_ACCESS"},
        {"source": role_ids[3], "target": system_ids[0], "type": "HAS_ACCESS"},
        {"source": employee_ids[5], "target": role_ids[0], "type": "HAS_ACCESS"},
        {"source": role_ids[0], "target": employee_ids[6], "type": "HAS_ROLE"},
        {"source": system_ids[0], "target": role_ids[0], "type": "HAS_ACCESS"}
    ]
    random.SystemRandom().shuffle(nodes)
    random.SystemRandom().shuffle(edges)
    return {"nodes": nodes, "edges": edges}

def empty_result_graph():
    token = secrets.token_hex(8)
    return {
        "nodes": [
            {"id": f"e-{token}", "label": "Employee", "name": f"Nobody_{token}"},
            {"id": f"r-{token}", "label": "Role", "name": f"Role_{token}"},
            {"id": f"s-{token}", "label": "System", "name": f"System_{token}", "sensitivity": "HIGH"},
            {"id": f"l-{token}", "label": "System", "name": f"Low_{token}", "sensitivity": "LOW"}
        ],
        "edges": [
            {"source": f"e-{token}", "target": f"r-{token}", "type": "HAS_ROLE"},
            {"source": f"r-{token}", "target": f"l-{token}", "type": "HAS_ACCESS"},
            {"source": f"s-{token}", "target": f"r-{token}", "type": "HAS_ACCESS"}
        ]
    }

def main():
    assert os.path.lexists(AUDIT_PATH), f"Missing {AUDIT_PATH}"
    mode = os.lstat(AUDIT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{AUDIT_PATH} must be a regular Python script"

    run_case(CANONICAL_GRAPH, 'the original graph')
    run_case(randomized_graph(), 'a randomized graph')
    run_case(empty_result_graph(), 'a graph with no qualifying paths')

    # Leave the requested files in their expected canonical final state.
    run_case(CANONICAL_GRAPH, 'the original graph final run')

if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_audit_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
