#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
import time

import cv2


def compile_source(output_path):
    c_source = '/home/user/deadlock_detector.c'
    assert os.path.isfile(c_source), f'Missing source file: {c_source}'
    compile_res = subprocess.run(
        ['gcc', '-O3', c_source, '-o', output_path],
        capture_output=True, text=True
    )
    assert compile_res.returncode == 0, f'Compilation failed:\n{compile_res.stderr}'


def run_and_check(binary, csv_path, max_timestamp, expected, timeout=5):
    run_res = subprocess.run(
        [binary, csv_path, max_timestamp],
        capture_output=True, text=True, timeout=timeout
    )
    assert run_res.returncode == 0, f'Program crashed or returned non-zero:\n{run_res.stderr}'
    output = run_res.stdout.strip()
    assert output == expected, f'Expected {expected!r}, got {output!r}'


def oracle(csv_path, max_timestamp):
    holders = {}
    waiting = {}
    with open(csv_path, newline='') as f:
        for row in csv.DictReader(f):
            if float(row['timestamp_sec']) > float(max_timestamp):
                continue
            tx = int(row['tx_id'])
            resource = int(row['resource_id'])
            action = row['action']
            if action == 'ACQUIRE':
                holders[resource] = tx
                waiting.pop(tx, None)
            elif action == 'RELEASE':
                if holders.get(resource) == tx:
                    holders.pop(resource, None)
            elif action == 'WAIT':
                waiting[tx] = resource

    graph = {}
    nodes = set()
    for tx, resource in waiting.items():
        holder = holders.get(resource)
        if holder is not None and holder != tx:
            graph.setdefault(tx, set()).add(holder)
            nodes.add(tx)
            nodes.add(holder)

    index = 0
    indices = {}
    low = {}
    stack = []
    on_stack = set()
    cycle_nodes = set()

    def visit(v):
        nonlocal index
        indices[v] = low[v] = index
        index += 1
        stack.append(v)
        on_stack.add(v)
        for w in graph.get(v, ()):
            if w not in indices:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in on_stack:
                low[v] = min(low[v], indices[w])
        if low[v] == indices[v]:
            component = []
            while True:
                w = stack.pop()
                on_stack.remove(w)
                component.append(w)
                if w == v:
                    break
            if len(component) > 1 or (len(component) == 1 and v in graph.get(v, ())):
                cycle_nodes.update(component)

    for node in nodes:
        if node not in indices:
            visit(node)
    return ','.join(str(x) for x in sorted(cycle_nodes))


def make_random_log(path):
    rng = secrets.SystemRandom()
    cycle_size = rng.randint(2, 7)
    decoy_size = rng.randint(2, 6)
    ids = rng.sample(range(1000, 900000), cycle_size + decoy_size)
    resources = rng.sample(range(1000000, 9000000), cycle_size + decoy_size)
    cycle_ids = ids[:cycle_size]
    decoy_ids = ids[cycle_size:]
    cycle_resources = resources[:cycle_size]
    decoy_resources = resources[cycle_size:]

    rows = []
    tick = 100
    for tx, resource in zip(cycle_ids, cycle_resources):
        rows.append((tick / 100, tx, resource, 'ACQUIRE'))
        tick += 7
    for i, tx in enumerate(cycle_ids):
        rows.append((tick / 100, tx, cycle_resources[(i + 1) % cycle_size], 'WAIT'))
        tick += 7
    max_timestamp = (tick + 10) / 100

    tick += 100
    for tx, resource in zip(decoy_ids, decoy_resources):
        rows.append((tick / 100, tx, resource, 'ACQUIRE'))
        tick += 7
    for i, tx in enumerate(decoy_ids):
        rows.append((tick / 100, tx, decoy_resources[(i + 1) % decoy_size], 'WAIT'))
        tick += 7

    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp_sec', 'tx_id', 'resource_id', 'action'])
        for timestamp, tx, resource, action in rows:
            writer.writerow([f'{timestamp:.2f}', tx, resource, action])
    return f'{max_timestamp:.2f}'


def video_deadlock_timestamp():
    video = '/app/audit_dashboard.mp4'
    assert os.path.isfile(video), f'Missing video: {video}'
    cap = cv2.VideoCapture(video)
    assert cap.isOpened(), f'Could not open video: {video}'
    fps = cap.get(cv2.CAP_PROP_FPS)
    assert fps > 0
    red_frames = []
    frame_index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        b, g, r = frame.mean(axis=(0, 1))
        if r > 200 and g < 50 and b < 50:
            red_frames.append(frame_index)
        frame_index += 1
    cap.release()
    assert len(red_frames) == 1, f'Expected exactly one red frame, found {red_frames}'
    return f'{red_frames[0] / fps:.2f}'


def test_deadlock_detector_performance_and_correctness():
    compiled_bin = '/tmp/deadlock_detector_test'
    compile_source(compiled_bin)

    hidden_log = '/app/hidden_massive_log.csv'
    assert os.path.isfile(hidden_log), f'Hidden log missing: {hidden_log}'

    start_time = time.time()
    run_res = subprocess.run(
        [compiled_bin, hidden_log, '13.73'],
        capture_output=True, text=True
    )
    duration = time.time() - start_time

    assert run_res.returncode == 0, f'Program crashed or returned non-zero:\n{run_res.stderr}'
    output = run_res.stdout.strip()
    expected_output = '8392,10293,44021,99201'
    assert output == expected_output, f'Incorrect deadlock cycle detected. Expected {expected_output!r}, got {output!r}'
    assert duration <= 1.5, f'Execution too slow: {duration:.3f}s (threshold 1.5s)'


def test_randomized_logs_and_required_binary():
    submitted_bin = '/home/user/deadlock_detector'
    assert os.path.isfile(submitted_bin), f'Missing compiled binary: {submitted_bin}'
    assert os.access(submitted_bin, os.X_OK), f'Binary is not executable: {submitted_bin}'
    with open(submitted_bin, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{submitted_bin} is not an ELF binary'

    rebuilt_bin = '/tmp/deadlock_detector_random_test'
    compile_source(rebuilt_bin)
    for case in range(2):
        log_path = f'/tmp/random_deadlock_{case}.csv'
        max_timestamp = make_random_log(log_path)
        expected = oracle(log_path, max_timestamp)
        assert expected, 'Verifier generated a log without a cycle'
        run_and_check(rebuilt_bin, log_path, max_timestamp, expected)
        run_and_check(submitted_bin, log_path, max_timestamp, expected)


def test_public_result_exists():
    result_file = '/home/user/deadlock_result.txt'
    assert os.path.isfile(result_file), f'Missing result file: {result_file}'
    with open(result_file, 'r') as f:
        content = f.read().strip()
    assert len(content) > 0, f'Result file {result_file} is empty'

    timestamp = video_deadlock_timestamp()
    public_log = '/home/user/tx_log.csv'
    expected = oracle(public_log, timestamp)
    assert expected, 'No deadlock found in the public log at the video timestamp'
    assert content == expected, f'Incorrect saved result. Expected {expected!r}, got {content!r}'
    run_and_check('/home/user/deadlock_detector', public_log, timestamp, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
