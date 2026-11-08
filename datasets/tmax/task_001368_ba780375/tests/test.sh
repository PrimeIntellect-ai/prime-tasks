#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import uuid


def test_violations_txt_correct():
    violations_path = "/home/user/violations.txt"
    assert os.path.isfile(violations_path), f"The file {violations_path} does not exist."

    with open(violations_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_violators = ["EMP_01", "EMP_05"]
    assert lines == expected_violators, f"Expected {expected_violators} in {violations_path}, but got {lines}."


def test_cypher_query_exists_and_looks_valid():
    query_path = "/home/user/query.cypher"
    assert os.path.isfile(query_path), f"The file {query_path} does not exist."

    with open(query_path, "r") as f:
        original_query = f.read()
        query = original_query.upper()

    # Preserve the original assertions.
    assert "MATCH" in query, "The Cypher query must contain a MATCH clause."
    assert "MANAGES" in query, "The Cypher query must reference the MANAGES relationship."
    assert "HAS_ACCESS" in query, "The Cypher query must reference the HAS_ACCESS relationship."
    assert "*" in query, "The Cypher query must use variable-length paths (e.g., [:MANAGES*0..]) for transitive management."

    # Reject keyword-only/gibberish files and require the essential query semantics.
    stripped = re.sub(r"/\*.*?\*/", " ", query, flags=re.S)
    stripped = re.sub(r"//[^\n]*", " ", stripped)
    assert re.search(r"\[[^\]]*:\s*MANAGES\s*\*[^\]]*\]", stripped), \
        "MANAGES must be used as a variable-length relationship pattern."
    assert re.search(r"\[[^\]]*:\s*HAS_ACCESS[^\]]*\]", stripped), \
        "HAS_ACCESS must be used as a relationship pattern."
    assert ("FINANCIAL_RECORDS" in stripped or "SYS_001" in stripped), \
        "The query must select the Financial_Records system."
    assert ("AUDIT_LOGS" in stripped or "SYS_002" in stripped), \
        "The query must select the Audit_Logs system."
    assert re.search(r"\bRETURN\b[\s\S]*\.\s*ID\b", stripped), \
        "The query must return employee IDs."
    assert stripped.count("(") == stripped.count(")"), "The Cypher query has unbalanced parentheses."
    assert stripped.count("[") == stripped.count("]"), "The Cypher query has unbalanced relationship brackets."
    # A zero-length management path is needed to include an employee's own access,
    # unless the query separately matches direct HAS_ACCESS relationships.
    zero_length = re.search(r":\s*MANAGES\s*\*\s*0\s*\.\.", stripped)
    direct_access = re.search(r"MATCH\s*\([^)]*\)\s*-\s*\[[^\]]*:\s*HAS_ACCESS[^\]]*\]", stripped)
    assert zero_length or direct_access, \
        "The query must include employees' direct access as well as inherited access."


def derive_violators(nodes, edges):
    employees = {n["id"] for n in nodes if n.get("type") == "Employee"}
    financial = {n["id"] for n in nodes if n.get("type") == "System" and n.get("name") == "Financial_Records"}
    audit = {n["id"] for n in nodes if n.get("type") == "System" and n.get("name") == "Audit_Logs"}
    manages = {employee: [] for employee in employees}
    access = {employee: set() for employee in employees}

    for edge in edges:
        source, target, relation = edge["source"], edge["target"], edge["relation"]
        if relation == "MANAGES" and source in employees and target in employees:
            manages[source].append(target)
        elif relation == "HAS_ACCESS" and source in employees:
            access[source].add(target)

    result = []
    for employee in employees:
        stack = [employee]
        visited = set()
        reachable_systems = set()
        while stack:
            current = stack.pop()
            if current in visited:
                continue
            visited.add(current)
            reachable_systems.update(access.get(current, set()))
            stack.extend(manages.get(current, []))
        if reachable_systems & financial and reachable_systems & audit:
            result.append(employee)
    return sorted(result)


def test_rust_project_exists_builds_and_processes_graph():
    cargo_toml = "/home/user/auditor/Cargo.toml"
    main_rs = "/home/user/auditor/src/main.rs"

    # Preserve the original existence assertions.
    assert os.path.isfile(cargo_toml), f"Rust project file {cargo_toml} does not exist."
    assert os.path.isfile(main_rs), f"Rust source file {main_rs} does not exist."

    build = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", cargo_toml],
        cwd="/home/user/auditor",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, f"The Rust project does not build:\n{build.stdout}\n{build.stderr}"

    nodes_path = "/home/user/audit_data/nodes.json"
    edges_path = "/home/user/audit_data/edges.json"
    violations_path = "/home/user/violations.txt"
    with open(nodes_path, "rb") as f:
        original_nodes = f.read()
    with open(edges_path, "rb") as f:
        original_edges = f.read()
    original_violations = None
    if os.path.isfile(violations_path):
        with open(violations_path, "rb") as f:
            original_violations = f.read()

    suffixes = [uuid.uuid4().hex[:10].upper() for _ in range(6)]
    employee_ids = ["EMP_" + suffix for suffix in suffixes]
    a, b, c, d, e, f = employee_ids
    nodes = [
        {"id": a, "type": "Employee", "name": "Manager A"},
        {"id": b, "type": "Employee", "name": "Manager B"},
        {"id": c, "type": "Employee", "name": "Worker C"},
        {"id": d, "type": "Employee", "name": "Worker D"},
        {"id": e, "type": "Employee", "name": "Worker E"},
        {"id": f, "type": "Employee", "name": "Worker F"},
        {"id": "SYS_001", "type": "System", "name": "Financial_Records"},
        {"id": "SYS_002", "type": "System", "name": "Audit_Logs"},
        {"id": "SYS_003", "type": "System", "name": "General_IT"},
    ]
    edges = [
        {"source": a, "target": b, "relation": "MANAGES"},
        {"source": b, "target": c, "relation": "MANAGES"},
        {"source": c, "target": "SYS_001", "relation": "HAS_ACCESS"},
        {"source": a, "target": d, "relation": "MANAGES"},
        {"source": d, "target": "SYS_002", "relation": "HAS_ACCESS"},
        {"source": e, "target": "SYS_001", "relation": "HAS_ACCESS"},
        {"source": e, "target": "SYS_002", "relation": "HAS_ACCESS"},
        {"source": f, "target": "SYS_003", "relation": "HAS_ACCESS"},
    ]
    expected = derive_violators(nodes, edges)

    try:
        with open(nodes_path, "w") as out:
            json.dump(nodes, out)
        with open(edges_path, "w") as out:
            json.dump(edges, out)
        if os.path.exists(violations_path):
            os.remove(violations_path)

        run = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", cargo_toml],
            cwd="/home/user/auditor",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert run.returncode == 0, f"The Rust program failed on a valid graph:\n{run.stdout}\n{run.stderr}"

        produced_text = run.stdout
        if os.path.isfile(violations_path):
            with open(violations_path, "r") as result_file:
                produced_text += "\n" + result_file.read()
        actual = sorted(emp for emp in employee_ids if re.search(r"(?<![A-Z0-9_])" + re.escape(emp) + r"(?![A-Z0-9_])", produced_text))
        assert actual == expected, \
            f"Rust program produced {actual} for the verification graph; expected {expected}. Output was:\n{produced_text}"
    finally:
        with open(nodes_path, "wb") as fobj:
            fobj.write(original_nodes)
        with open(edges_path, "wb") as fobj:
            fobj.write(original_edges)
        if original_violations is None:
            if os.path.exists(violations_path):
                os.remove(violations_path)
        else:
            with open(violations_path, "wb") as fobj:
                fobj.write(original_violations)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
