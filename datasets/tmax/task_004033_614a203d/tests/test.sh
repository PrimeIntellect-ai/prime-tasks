#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
from collections import deque

import pytest

SOURCE = '/home/user/audit.cpp'
BINARY = '/home/user/audit'
OUTPUT = '/home/user/violation_path.txt'
NODES = '/home/user/nodes.csv'
EDGES = '/home/user/edges.csv'
REBUILT = '/tmp/audit_from_source'


@pytest.fixture(scope='session', autouse=True)
def restore_original_files():
    saved = {}
    for path in (NODES, EDGES, OUTPUT):
        if os.path.exists(path):
            with open(path, 'rb') as f:
                saved[path] = f.read()
        else:
            saved[path] = None
    yield
    for path, data in saved.items():
        if data is None:
            if os.path.exists(path):
                os.remove(path)
        else:
            with open(path, 'wb') as f:
                f.write(data)


def test_audit_cpp_exists():
    path = '/home/user/audit.cpp'
    assert os.path.isfile(path), f"Expected C++ source file {path} does not exist."


def test_audit_binary_exists():
    path = '/home/user/audit'
    assert os.path.isfile(path), f"Expected compiled binary {path} does not exist."
    assert os.access(path, os.X_OK), f"The file {path} is not executable."
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"Expected {path} to be a compiled ELF executable."


def test_audit_cpp_compiles_as_cpp17():
    result = subprocess.run(
        ['g++', '-std=c++17', SOURCE, '-o', REBUILT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"audit.cpp failed to compile with C++17:\n{result.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def run_audit(executable):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [executable],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist after running {executable}."
    with open(OUTPUT, 'r') as f:
        return f.read().strip()


def test_violation_path_output():
    run_audit(BINARY)
    path = '/home/user/violation_path.txt'
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_path = "N1,N2,N3,N4,N6"
    assert content == expected_path, f"Output file {path} contains '{content}', but expected '{expected_path}'."


def write_csv(path, header, rows):
    with open(path, 'w', newline='') as f:
        f.write(','.join(header) + '\n')
        for row in rows:
            f.write(','.join(row) + '\n')


def derive_answer(nodes, edges):
    start = next(node_id for node_id, node_type, name in nodes
                 if node_type == 'Employee' and name == 'Intern_Bob')
    target = next(node_id for node_id, node_type, name in nodes
                  if node_type == 'System' and name == 'Financial_DB_Prod')
    graph = {}
    for source, destination, _edge_type in edges:
        graph.setdefault(source, []).append(destination)

    queue = deque([[start]])
    seen = {start}
    while queue:
        path = queue.popleft()
        current = path[-1]
        if current == target:
            return ','.join(path)
        for neighbor in graph.get(current, []):
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append(path + [neighbor])
    return 'NONE'


def make_case(has_path):
    ids = [f'N{i}' for i in range(1, 10)]
    random.SystemRandom(secrets.randbits(64)).shuffle(ids)
    labels = ['emp', 'r1', 'r2', 'r3', 'r4', 'target', 'devsys', 'otheremp', 'admin']
    node_id = dict(zip(labels, ids))

    nodes = [
        (node_id['emp'], 'Employee', 'Intern_Bob'),
        (node_id['r1'], 'Role', 'Intern_Role'),
        (node_id['r2'], 'Role', 'Junior_Dev_Role'),
        (node_id['r3'], 'Role', 'Dev_Ops_Role'),
        (node_id['r4'], 'Role', 'Audit_Role'),
        (node_id['target'], 'System', 'Financial_DB_Prod'),
        (node_id['devsys'], 'System', 'Dev_Server'),
        (node_id['otheremp'], 'Employee', 'Admin_Alice'),
        (node_id['admin'], 'Role', 'Admin_Role'),
    ]
    edges = [
        (node_id['emp'], node_id['r1'], 'HAS_ROLE'),
        (node_id['r1'], node_id['r2'], 'ROLE_INHERITS'),
        (node_id['r1'], node_id['r3'], 'ROLE_INHERITS'),
        (node_id['r3'], node_id['r4'], 'ROLE_INHERITS'),
        (node_id['r2'], node_id['devsys'], 'CAN_ACCESS'),
        (node_id['otheremp'], node_id['admin'], 'HAS_ROLE'),
        (node_id['admin'], node_id['target'], 'CAN_ACCESS'),
    ]
    if has_path:
        # The r2 route is deliberately shorter than the r3/r4 route.
        edges.extend([
            (node_id['r2'], node_id['target'], 'CAN_ACCESS'),
            (node_id['r4'], node_id['target'], 'CAN_ACCESS'),
        ])
    return nodes, edges


def test_program_computes_shortest_path_from_csv_inputs():
    for has_path in (True, False):
        nodes, edges = make_case(has_path)
        expected = derive_answer(nodes, edges)
        write_csv(NODES, ('node_id', 'node_type', 'name'), nodes)
        write_csv(EDGES, ('source_id', 'target_id', 'edge_type'), edges)

        for executable in (BINARY, REBUILT):
            actual = run_audit(executable)
            assert actual == expected, (
                f"{executable} produced '{actual}' for a generated CSV graph; expected '{expected}'."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
