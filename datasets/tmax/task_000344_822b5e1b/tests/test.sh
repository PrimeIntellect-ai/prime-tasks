#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import stat
import re
import secrets
import subprocess
from collections import defaultdict


def get_deadlocked(edges):
    adj = defaultdict(list)
    nodes = set()
    for u, v in edges:
        adj[u].append(v)
        nodes.add(u)
        nodes.add(v)

    index = 0
    indices = {}
    lowlink = {}
    on_stack = set()
    stack = []
    deadlocked = set()

    def strongconnect(v):
        nonlocal index
        indices[v] = index
        lowlink[v] = index
        index += 1
        stack.append(v)
        on_stack.add(v)

        for w in adj[v]:
            if w not in indices:
                strongconnect(w)
                lowlink[v] = min(lowlink[v], lowlink[w])
            elif w in on_stack:
                lowlink[v] = min(lowlink[v], indices[w])

        if lowlink[v] == indices[v]:
            scc = []
            while True:
                w = stack.pop()
                on_stack.remove(w)
                scc.append(w)
                if w == v:
                    break
            if len(scc) > 1 or (len(scc) == 1 and v in adj[v]):
                deadlocked.update(scc)

    for v in nodes:
        if v not in indices:
            strongconnect(v)

    return deadlocked


def get_expected_audit_report(csv_path):
    edges = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get('Status') == 'WAITING':
                try:
                    edges.append((int(row['WaitingTxID']), int(row['HoldingTxID'])))
                except ValueError:
                    continue
    return sorted(get_deadlocked(edges), reverse=True)[:4]


def run_pipeline():
    result = subprocess.run(
        ['/home/user/build_and_run.sh'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"build_and_run.sh failed with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def read_report():
    with open('/home/user/audit_report.txt', 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_build_and_run_script_exists_and_executable():
    script_path = '/home/user/build_and_run.sh'
    assert os.path.exists(script_path), f'Script {script_path} does not exist.'
    assert os.path.isfile(script_path), f'{script_path} is not a file.'

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'{script_path} is not executable by the user.'


def test_c_program_exists():
    c_path = '/home/user/detect_cycles.c'
    assert os.path.exists(c_path), f'C program source {c_path} does not exist.'
    assert os.path.isfile(c_path), f'{c_path} is not a file.'


def test_audit_report_content_after_running_pipeline():
    report_path = '/home/user/audit_report.txt'
    csv_path = '/home/user/lock_events.csv'

    run_pipeline()

    assert os.path.exists(report_path), f'Audit report {report_path} does not exist.'
    assert os.path.isfile(report_path), f'{report_path} is not a file.'

    expected_top_4 = get_expected_audit_report(csv_path)
    expected_lines = [str(x) for x in expected_top_4]
    actual_lines = read_report()

    assert actual_lines == expected_lines, (
        f'Audit report contents mismatch. Expected: {expected_lines}, Got: {actual_lines}'
    )

    binary = '/home/user/detect_cycles'
    assert os.path.isfile(binary), 'The pipeline did not compile /home/user/detect_cycles.'
    assert os.access(binary, os.X_OK), '/home/user/detect_cycles is not executable.'


def test_pipeline_on_fresh_input_and_exact_status_filtering():
    csv_path = '/home/user/lock_events.csv'
    with open(csv_path, 'rb') as f:
        original_csv = f.read()

    base = 10000 + secrets.randbelow(500000)
    waiting_edges = [
        (base + 1, base + 2),
        (base + 2, base + 3),
        (base + 3, base + 1),
        (base + 10, base + 11),
        (base + 11, base + 10),
        (base + 20, base + 20),
        (base + 30, base + 31),
        (base + 31, base + 32),
    ]
    decoy = base + 1000000

    rows = [('2026-01-01T00:00:%02d' % i, 'WAITING', u, v, 'R%d' % i)
            for i, (u, v) in enumerate(waiting_edges, 1)]
    rows.extend([
        ('2026-01-01T01:00:01', 'GRANTED', decoy, decoy + 1, 'DecoyA'),
        ('2026-01-01T01:00:02', 'GRANTED', decoy + 1, decoy, 'DecoyB'),
        ('2026-01-01T01:00:03', 'WAITINGX', decoy + 2, decoy + 2, 'DecoyC'),
        ('2026-01-01T01:00:04', ' WAITING', decoy + 3, decoy + 3, 'DecoyD'),
    ])

    try:
        with open(csv_path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Timestamp', 'Status', 'WaitingTxID', 'HoldingTxID', 'ResourceName'])
            writer.writerows(rows)

        run_pipeline()
        expected = [str(x) for x in sorted(get_deadlocked(waiting_edges), reverse=True)[:4]]
        actual = read_report()
        assert actual == expected, (
            'The executed pipeline did not filter exact WAITING rows, detect cycles, '
            f'and retain the four highest IDs. Expected {expected}, got {actual}'
        )
    finally:
        with open(csv_path, 'wb') as f:
            f.write(original_csv)
        try:
            run_pipeline()
        except Exception:
            pass


def test_compiled_c_detector_on_derived_graph():
    run_pipeline()
    binary = '/home/user/detect_cycles'
    assert os.path.isfile(binary), 'The pipeline did not produce detect_cycles.'
    assert os.access(binary, os.X_OK), 'The produced detect_cycles is not executable.'

    base = 2000000 + secrets.randbelow(500000)
    edges = [
        (base + 1, base + 2),
        (base + 2, base + 3),
        (base + 3, base + 1),
        (base + 4, base + 4),
        (base + 5, base + 6),
        (base + 6, base + 5),
        (base + 3, base + 7),
        (base + 7, base + 8),
        (base + 9, base + 10),
    ]
    input_text = ''.join(f'{u} {v}\n' for u, v in edges)
    result = subprocess.run(
        [binary], input=input_text, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f'detect_cycles failed with status {result.returncode}: {result.stderr!r}'
    )

    lines = result.stdout.splitlines()
    assert all(re.fullmatch(r'[+-]?\d+', line.strip()) for line in lines), (
        f'detect_cycles emitted non-integer output: {result.stdout!r}'
    )
    actual = [int(line.strip()) for line in lines]
    expected = get_deadlocked(edges)
    assert len(actual) == len(set(actual)), 'detect_cycles printed a transaction ID more than once.'
    assert set(actual) == expected, (
        f'detect_cycles returned the wrong cycle members. Expected {sorted(expected)}, '
        f'got {sorted(actual)}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
