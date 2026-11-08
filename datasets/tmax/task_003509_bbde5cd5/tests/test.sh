#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import stat
import subprocess
import sys

AUDIT = "/home/user/audit.py"
RESULT = "/home/user/audit_result.txt"
EMPLOYEES = "/home/user/employees.csv"
ACCESS = "/home/user/access.json"
NETWORK = "/home/user/network.txt"
INPUTS = (EMPLOYEES, ACCESS, NETWORK)


def run_audit():
    if os.path.lexists(RESULT):
        os.unlink(RESULT)

    completed = subprocess.run(
        [sys.executable, AUDIT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"audit.py exited with {completed.returncode}\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULT) and not os.path.islink(RESULT), (
        f"Missing regular output file: {RESULT}"
    )
    with open(RESULT, "rb") as f:
        return f.read()


def derive_expected():
    managers = {}
    with open(EMPLOYEES, newline="") as f:
        for row in csv.DictReader(f):
            emp_id = int(row["emp_id"])
            manager = row["manager_id"].strip()
            managers[emp_id] = int(manager) if manager else None

    included = {2}
    changed = True
    while changed:
        changed = False
        for emp_id, manager in managers.items():
            if manager in included and emp_id not in included:
                included.add(emp_id)
                changed = True

    with open(ACCESS) as f:
        mappings = json.load(f)
    base = set()
    for mapping in mappings:
        if int(mapping["emp_id"]) in included:
            base.update(mapping["servers"])

    graph = {server: set() for server in base}
    with open(NETWORK) as f:
        for line in f:
            if not line.strip():
                continue
            left, right = line.split()
            graph.setdefault(left, set()).add(right)
            graph.setdefault(right, set()).add(left)

    reachable = set(base)
    stack = list(base)
    while stack:
        node = stack.pop()
        for neighbor in graph.get(node, ()):
            if neighbor not in reachable:
                reachable.add(neighbor)
                stack.append(neighbor)

    assert reachable, "Generated test unexpectedly has no reachable servers"
    degrees = {
        node: sum(neighbor in reachable for neighbor in graph.get(node, ()))
        for node in reachable
    }
    winner = min(reachable, key=lambda node: (-degrees[node], node))
    return f"{winner},{degrees[winner]}".encode()


def write_fixture(employees, access, edges):
    with open(EMPLOYEES, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["emp_id", "manager_id", "name"])
        writer.writerows(employees)
    with open(ACCESS, "w") as f:
        json.dump(access, f)
    with open(NETWORK, "w") as f:
        for left, right in edges:
            f.write(f"{left} {right}\n")


def generated_hierarchy_fixture():
    token = secrets.token_hex(8)
    rng = random.SystemRandom()
    groups = []
    next_index = 0
    for size in (3, 4, 5, 6):
        group = [f"N{token}_{i:02d}" for i in range(next_index, next_index + size)]
        groups.append(group)
        next_index += size

    edges = []
    # Bob's own component is a path.
    edges.extend(zip(groups[0], groups[0][1:]))
    # A direct report's component is a star.
    edges.extend((groups[1][0], node) for node in groups[1][1:])
    # An indirect report's component is a clique and must determine the answer.
    edges.extend(
        (groups[2][i], groups[2][j])
        for i in range(len(groups[2]))
        for j in range(i + 1, len(groups[2]))
    )
    # This higher-degree clique belongs only to an outsider and must be excluded.
    edges.extend(
        (groups[3][i], groups[3][j])
        for i in range(len(groups[3]))
        for j in range(i + 1, len(groups[3]))
    )
    edges = [(b, a) if rng.choice((True, False)) else (a, b) for a, b in edges]
    rng.shuffle(edges)

    employees = [
        (1, "", "Alice"),
        (2, 1, "Bob"),
        (3, 2, "DirectReport"),
        (4, 3, "IndirectReport"),
        (5, 1, "Outsider"),
        (6, 5, "OutsiderReport"),
    ]
    access = [
        {"emp_id": 1, "servers": []},
        {"emp_id": 2, "servers": [groups[0][0]]},
        {"emp_id": 3, "servers": [groups[1][-1]]},
        {"emp_id": 4, "servers": [groups[2][-1]]},
        {"emp_id": 5, "servers": [groups[3][0]]},
        {"emp_id": 6, "servers": [groups[3][1]]},
    ]
    return employees, access, edges


def isolated_base_fixture():
    token = secrets.token_hex(8)
    isolated = f"ISO_{token}"
    outsider_a = f"OUT_{token}_A"
    outsider_b = f"OUT_{token}_B"
    employees = [(1, "", "Alice"), (2, 1, "Bob"), (3, 1, "NotBobsReport")]
    access = [
        {"emp_id": 2, "servers": [isolated]},
        {"emp_id": 3, "servers": [outsider_a]},
    ]
    return employees, access, [(outsider_a, outsider_b)]


def test_audit_result_correct_and_script_is_functional():
    assert os.path.exists(AUDIT), f"Missing required script: {AUDIT}"
    assert not os.path.islink(AUDIT), f"audit.py must be a regular file, not a symlink"
    assert stat.S_ISREG(os.stat(AUDIT).st_mode), f"audit.py is not a regular file"

    saved_inputs = {path: open(path, "rb").read() for path in INPUTS}
    saved_result = open(RESULT, "rb").read() if os.path.isfile(RESULT) else None

    try:
        # Execute the submission on the original task data before checking the
        # original verifier's expected assertion.
        original = run_audit()
        content = original.decode()
        cleaned_content = content.replace('\n', '').replace('\r', '')
        assert cleaned_content == "Database,4", (
            f"Expected 'Database,4' in {RESULT}, but got '{cleaned_content}'"
        )
        assert original == b"Database,4", "Output must contain no extra text or newlines"

        # Replace the inputs with unpredictable fixtures and independently derive
        # each expected answer, proving that audit.py performs the requested work.
        for fixture in (generated_hierarchy_fixture(), isolated_base_fixture()):
            write_fixture(*fixture)
            expected = derive_expected()
            actual = run_audit()
            assert actual == expected, f"Expected {expected!r}, got {actual!r}"
    finally:
        for path, data in saved_inputs.items():
            with open(path, "wb") as f:
                f.write(data)
        if saved_result is None:
            if os.path.lexists(RESULT):
                os.unlink(RESULT)
        else:
            if os.path.lexists(RESULT):
                os.unlink(RESULT)
            with open(RESULT, "wb") as f:
                f.write(saved_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
