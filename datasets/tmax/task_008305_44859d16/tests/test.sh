#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import shutil
import subprocess
import tempfile


def get_expected_deadlocks(csv_path):
    held_by = {}
    waiting_for = []

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            tx_id = int(row['tx_id'])
            res_id = row['resource_id']
            state = row['lock_state']

            if state == 'HELD':
                held_by[res_id] = tx_id
            elif state == 'WAITING':
                waiting_for.append((tx_id, res_id))

    graph = {}
    nodes = set()
    for w_tx, res_id in waiting_for:
        nodes.add(w_tx)
        if res_id in held_by:
            h_tx = held_by[res_id]
            nodes.add(h_tx)
            if w_tx not in graph:
                graph[w_tx] = set()
            graph[w_tx].add(h_tx)

    deadlocked = set()
    visited = set()
    rec_stack = set()

    def dfs(node, path):
        visited.add(node)
        rec_stack.add(node)
        path.append(node)

        for neighbor in graph.get(node, []):
            if neighbor not in visited:
                dfs(neighbor, path)
            elif neighbor in rec_stack:
                cycle_start_idx = path.index(neighbor)
                for n in path[cycle_start_idx:]:
                    deadlocked.add(n)

        rec_stack.remove(node)
        path.pop()

    for node in list(nodes) + list(held_by.values()):
        if node not in visited:
            dfs(node, [])

    return sorted(list(deadlocked))


def test_detect_deadlocks_c_exists():
    assert os.path.isfile('/home/user/detect_deadlocks.c'), "C source file /home/user/detect_deadlocks.c is missing."


def test_detect_binary_exists():
    assert os.path.isfile('/home/user/detect'), "Compiled binary /home/user/detect is missing."
    assert os.access('/home/user/detect', os.X_OK), "Binary /home/user/detect is not executable."


def test_deadlocks_log_correct():
    log_path = '/home/user/deadlocks.log'
    csv_path = '/home/user/locks.csv'

    assert os.path.isfile(log_path), f"Output file {log_path} is missing."
    assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."

    expected_tx_ids = get_expected_deadlocks(csv_path)

    with open(log_path, 'r') as f:
        lines = f.read().strip().splitlines()

    actual_tx_ids = []
    for line in lines:
        line = line.strip()
        if line:
            try:
                actual_tx_ids.append(int(line))
            except ValueError:
                assert False, f"Invalid non-integer content in {log_path}: '{line}'"

    assert actual_tx_ids == expected_tx_ids, f"Expected deadlocked tx_ids {expected_tx_ids}, but got {actual_tx_ids} in {log_path}."


def robust_expected(csv_path):
    held_by = {}
    waits = []
    nodes = set()
    with open(csv_path, newline='') as f:
        for row in csv.DictReader(f):
            tx = int(row['tx_id'])
            nodes.add(tx)
            if row['lock_state'] == 'HELD':
                held_by[row['resource_id']] = tx
            elif row['lock_state'] == 'WAITING':
                waits.append((tx, row['resource_id']))

    graph = {n: set() for n in nodes}
    for waiter, resource in waits:
        if resource in held_by:
            holder = held_by[resource]
            nodes.add(holder)
            graph.setdefault(waiter, set()).add(holder)
            graph.setdefault(holder, set())

    index = 0
    indices = {}
    lowlink = {}
    stack = []
    on_stack = set()
    deadlocked = set()

    def visit(v):
        nonlocal index
        indices[v] = index
        lowlink[v] = index
        index += 1
        stack.append(v)
        on_stack.add(v)

        for w in graph.get(v, ()):
            if w not in indices:
                visit(w)
                lowlink[v] = min(lowlink[v], lowlink[w])
            elif w in on_stack:
                lowlink[v] = min(lowlink[v], indices[w])

        if lowlink[v] == indices[v]:
            component = []
            while True:
                w = stack.pop()
                on_stack.remove(w)
                component.append(w)
                if w == v:
                    break
            if len(component) > 1 or (len(component) == 1 and v in graph.get(v, ())):
                deadlocked.update(component)

    for node in nodes:
        if node not in indices:
            visit(node)
    return sorted(deadlocked)


def write_case(path, edges, node_count, include_missing=False):
    ids = random.sample(range(1000, 900000), node_count + (1 if include_missing else 0))
    resources = [f"R{i:08d}" for i in range(node_count)]
    rows = []
    for i in range(node_count):
        rows.append((ids[i], resources[i], 'HELD'))
    for source, target in edges:
        rows.append((ids[source], resources[target], 'WAITING'))
    if include_missing:
        rows.append((ids[-1], 'NOHOLDER', 'WAITING'))
    random.shuffle(rows)
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['tx_id', 'resource_id', 'lock_state'])
        writer.writerows(rows)


def assert_exact_log(expected):
    path = '/home/user/deadlocks.log'
    assert os.path.isfile(path), "Program did not create /home/user/deadlocks.log"
    with open(path, 'rb') as f:
        data = f.read()
    expected_body = '\n'.join(str(x) for x in expected).encode()
    allowed = {expected_body}
    if expected_body:
        allowed.add(expected_body + b'\n')
    assert data in allowed, f"Output must contain only sorted deadlocked IDs, one per line; expected {expected}, got {data!r}"


def exercise(program, cases):
    for edges, count, missing in cases:
        write_case('/home/user/locks.csv', edges, count, missing)
        expected = robust_expected('/home/user/locks.csv')
        try:
            os.remove('/home/user/deadlocks.log')
        except FileNotFoundError:
            pass
        result = subprocess.run([program], cwd='/home/user', stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=5)
        assert result.returncode == 0, (
            f"{program} exited with {result.returncode}; stderr={result.stderr.decode(errors='replace')}"
        )
        assert_exact_log(expected)


def test_source_and_binary_execute_on_changed_inputs():
    source = '/home/user/detect_deadlocks.c'
    binary = '/home/user/detect'
    csv_path = '/home/user/locks.csv'
    log_path = '/home/user/deadlocks.log'
    original_csv = open(csv_path, 'rb').read()
    original_log = open(log_path, 'rb').read() if os.path.exists(log_path) else None
    workdir = tempfile.mkdtemp(prefix='deadlock_verify_')
    rebuilt = os.path.join(workdir, 'rebuilt_detect')
    saved_binary = os.path.join(workdir, 'submitted_detect')
    moved = False

    cases = [
        ([(0, 1), (1, 2), (3, 2)], 4, True),
        ([(0, 1), (1, 2), (2, 0), (3, 0), (4, 5), (5, 4)], 6, True),
        ([(0, 0), (1, 0), (2, 3), (3, 4)], 5, False),
        ([(0, 1), (1, 2), (2, 0), (2, 3), (3, 4), (4, 3), (5, 4)], 6, True),
    ]

    try:
        compile_result = subprocess.run(['gcc', source, '-o', rebuilt], stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, timeout=15)
        assert compile_result.returncode == 0, (
            "detect_deadlocks.c does not compile with gcc: " +
            compile_result.stderr.decode(errors='replace')
        )
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

        os.replace(binary, saved_binary)
        moved = True
        exercise(rebuilt, cases)

        if os.path.exists(binary):
            os.remove(binary)
        os.replace(saved_binary, binary)
        moved = False
        exercise(binary, cases)
    finally:
        if moved and os.path.exists(saved_binary):
            if os.path.exists(binary):
                os.remove(binary)
            os.replace(saved_binary, binary)
        with open(csv_path, 'wb') as f:
            f.write(original_csv)
        if original_log is None:
            try:
                os.remove(log_path)
            except FileNotFoundError:
                pass
        else:
            with open(log_path, 'wb') as f:
                f.write(original_log)
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
