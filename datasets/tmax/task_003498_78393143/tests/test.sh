#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import socket
import subprocess
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import pytest
import redis


def is_port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('localhost', port)) == 0


def test_services_running():
    assert is_port_open(8080), "Nginx is not listening on port 8080"
    assert is_port_open(5000), "Flask API is not listening on port 5000"
    assert is_port_open(6379), "Redis is not listening on port 6379"


def test_c_worker_artifact_and_process():
    source = '/home/user/worker.c'
    assert os.path.isfile(source), f"C worker source {source} was not created"
    result = subprocess.run(
        ['gcc', source, '-o', '/tmp/verifier_worker_build', '-lhiredis', '-lm'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"worker.c does not compile: {result.stderr}"

    found = False
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            exe = os.readlink(f'/proc/{pid}/exe')
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ').decode(errors='ignore')
            if ('worker' in os.path.basename(exe).lower() or
                    'worker' in cmdline.lower() or
                    exe.startswith('/home/user/')):
                with open(f'/proc/{pid}/exe', 'rb') as f:
                    if f.read(4) == b'\x7fELF':
                        found = True
                        break
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            pass
    assert found, "No running native C worker process was found"


def clean_record(raw_values, refs):
    valid = [float(v) for v in raw_values if v != 'NaN']
    mean = sum(valid) / len(valid) if valid else 0.0
    cleaned = []
    for value in raw_values:
        number = mean if value == 'NaN' else float(value)
        cleaned.append(max(-50.0, min(50.0, number)))

    best_id = None
    best_distance = float('inf')
    for ref_id, values in refs:
        distance = math.sqrt(sum((a - b) ** 2 for a, b in zip(cleaned, values)))
        if distance < best_distance:
            best_distance = distance
            best_id = ref_id
    return cleaned, best_id, best_distance


def post_payload(payload):
    request = urllib.request.Request(
        'http://localhost:8080/ingest',
        data=json.dumps({'payload': payload}).encode(),
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.status, response.read()


def test_worker_output_accuracy():
    refs = []
    with open('/app/references.csv', newline='') as f:
        for row in csv.reader(f):
            refs.append((row[0], [float(x) for x in row[1:6]]))
    assert refs, "Reference profiles are missing"

    queue = redis.Redis(host='localhost', port=6379, socket_timeout=5)
    queue.ping()
    queue.delete('sensor_queue')

    output_path = '/tmp/cleaned_output.csv'
    with open(output_path, 'w'):
        pass
    time.sleep(0.25)

    nonce = secrets.token_hex(8)

    # Select reference coordinates that make NaN imputation and each clamp
    # produce accepted records while still exercising those transformations.
    nan_ref_index, nan_coord = min(
        ((ri, ci) for ri, (_, vals) in enumerate(refs) for ci in range(5)),
        key=lambda rc: abs(
            refs[rc[0]][1][rc[1]] -
            sum(v for j, v in enumerate(refs[rc[0]][1]) if j != rc[1]) / 4.0
        ),
    )
    high_ref_index, high_coord = max(
        ((ri, ci) for ri, (_, vals) in enumerate(refs) for ci in range(5)),
        key=lambda rc: refs[rc[0]][1][rc[1]],
    )
    low_ref_index, low_coord = min(
        ((ri, ci) for ri, (_, vals) in enumerate(refs) for ci in range(5)),
        key=lambda rc: refs[rc[0]][1][rc[1]],
    )

    records = []
    expected = {}
    rejected = set()
    rng = secrets.SystemRandom()

    for i in range(2200):
        mode = i % 10
        ref_index = i % len(refs)
        values = refs[ref_index][1]

        if mode <= 5:
            raw = [f'{v + rng.uniform(-2.0, 2.0):.8f}' for v in values]
        elif mode == 6:
            values = refs[nan_ref_index][1]
            raw = [f'{v + rng.uniform(-0.5, 0.5):.8f}' for v in values]
            raw[nan_coord] = 'NaN'
        elif mode == 7:
            values = refs[high_ref_index][1]
            raw = [f'{v + rng.uniform(-0.5, 0.5):.8f}' for v in values]
            raw[high_coord] = f'{75.0 + rng.uniform(0, 20):.8f}'
        elif mode == 8:
            values = refs[low_ref_index][1]
            raw = [f'{v + rng.uniform(-0.5, 0.5):.8f}' for v in values]
            raw[low_coord] = f'{-75.0 - rng.uniform(0, 20):.8f}'
        else:
            raw = [
                'NaN' if rng.random() < 0.15 else f'{rng.uniform(-90, 90):.8f}'
                for _ in range(5)
            ]

        record_id = f'verify_{nonce}_{i}'
        cleaned, closest, distance = clean_record(raw, refs)
        if distance < 20.0:
            expected[record_id] = (cleaned, closest)
        else:
            rejected.add(record_id)
        records.append(','.join([record_id] + raw))

    assert len(expected) >= 1000, "Internal test generation did not create enough accepted records"

    with ThreadPoolExecutor(max_workers=16) as pool:
        results = list(pool.map(post_payload, records))
    assert all(status == 200 for status, _ in results), "The HTTP ingest endpoint rejected records"

    deadline = time.time() + 45
    while time.time() < deadline:
        if queue.llen('sensor_queue') == 0:
            time.sleep(1.0)
            if queue.llen('sensor_queue') == 0:
                break
        time.sleep(0.1)
    assert queue.llen('sensor_queue') == 0, "C worker did not drain sensor_queue in time"

    observed = {}
    malformed = []
    if os.path.exists(output_path):
        with open(output_path, newline='') as f:
            for row in csv.reader(f):
                if not row or not row[0].startswith(f'verify_{nonce}_'):
                    continue
                if len(row) != 7:
                    malformed.append(row)
                    continue
                observed[row[0]] = row

    assert not malformed, "Worker emitted malformed output rows"

    correct = 0
    for record_id, (wanted_values, wanted_ref) in expected.items():
        row = observed.get(record_id)
        if row is None or row[6] != wanted_ref:
            continue
        try:
            differences = [abs(float(row[i + 1]) - wanted_values[i]) for i in range(5)]
        except ValueError:
            continue
        if all(d <= 0.05 for d in differences):
            correct += 1

    accuracy = correct / len(expected)
    assert accuracy >= 0.95, (
        f"Accuracy metric failed: {accuracy:.4f} < 0.95 threshold. "
        "The C worker output does not match the dynamically generated records."
    )

    wrongly_accepted = rejected.intersection(observed)
    assert not wrongly_accepted, "Worker emitted records whose nearest-reference distance was not below 20"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
