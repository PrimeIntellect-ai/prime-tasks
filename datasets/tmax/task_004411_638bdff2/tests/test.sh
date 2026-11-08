#!/bin/bash
set -e
mkdir -p /logs/verifier

SCRIPT=/home/user/restore_plan.py
OUTPUT=/home/user/restore_order.json

# The submitted artifact itself must generate the output.
if [ ! -f "$SCRIPT" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
rm -f "$OUTPUT"
if ! timeout 15s python3 "$SCRIPT"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import heapq
import random
import secrets
import subprocess
import pytest

SCRIPT_PATH = '/home/user/restore_plan.py'
DB_PATH = '/home/user/backups.sqlite'
JSON_PATH = '/home/user/services.json'
OUTPUT_PATH = '/home/user/restore_order.json'


def get_expected_restore_order():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} is missing."
    assert os.path.isfile(JSON_PATH), f"JSON file {JSON_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT service_id FROM backups WHERE status = 'FAILED'")
    failed_services = set(row[0] for row in c.fetchall())
    conn.close()

    with open(JSON_PATH, 'r') as f:
        services_data = json.load(f)

    adj = {svc: [] for svc in failed_services}
    in_degree = {svc: 0 for svc in failed_services}

    for item in services_data:
        svc = item['service_id']
        if svc not in failed_services:
            continue
        for dep in item['depends_on']:
            if dep in failed_services:
                adj[dep].append(svc)
                in_degree[svc] += 1

    pq = []
    for svc in failed_services:
        if in_degree[svc] == 0:
            heapq.heappush(pq, svc)

    restore_order = []
    while pq:
        curr = heapq.heappop(pq)
        restore_order.append(curr)
        for neighbor in adj[curr]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                heapq.heappush(pq, neighbor)

    return restore_order


def test_restore_order_json_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_restore_order_json_content():
    expected_order = get_expected_restore_order()

    with open(OUTPUT_PATH, 'r') as f:
        try:
            actual_order = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")

    assert isinstance(actual_order, list), "The output JSON must be a list of strings."
    assert actual_order == expected_order, (
        f"Restoration order is incorrect.\n"
        f"Expected: {expected_order}\n"
        f"Actual:   {actual_order}"
    )


def test_restore_plan_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."


def test_script_computes_runtime_generated_inputs():
    with open(DB_PATH, 'rb') as f:
        original_db = f.read()
    with open(JSON_PATH, 'rb') as f:
        original_json = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, 'rb') as f:
            original_output = f.read()

    try:
        for case in range(3):
            rng = random.Random(int.from_bytes(secrets.token_bytes(16), 'big'))
            tag = secrets.token_hex(6)
            names = [f"svc_{tag}_{i}_{secrets.token_hex(2)}" for i in range(10)]
            rng.shuffle(names)

            failed = set(rng.sample(names, 7))
            rows = [
                (name, 'FAILED' if name in failed else 'SUCCESS',
                 f'2026-01-{i + 1:02d}T00:00:00Z')
                for i, name in enumerate(names)
            ]
            rng.shuffle(rows)

            services = []
            for i, name in enumerate(names):
                possible = names[:i]
                count = rng.randint(0, min(3, len(possible)))
                deps = rng.sample(possible, count)
                services.append({'service_id': name, 'depends_on': deps})
            rng.shuffle(services)

            if os.path.exists(DB_PATH):
                os.remove(DB_PATH)
            conn = sqlite3.connect(DB_PATH)
            conn.execute(
                'CREATE TABLE backups '
                '(service_id TEXT PRIMARY KEY, status TEXT, last_backup_time TEXT)'
            )
            conn.executemany('INSERT INTO backups VALUES (?, ?, ?)', rows)
            conn.commit()
            conn.close()

            with open(JSON_PATH, 'w') as f:
                json.dump(services, f)

            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)

            result = subprocess.run(
                ['python3', SCRIPT_PATH],
                cwd='/home/user',
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"restore_plan.py failed on generated case {case}:\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
            assert os.path.isfile(OUTPUT_PATH), (
                "restore_plan.py did not create restore_order.json"
            )

            expected = get_expected_restore_order()
            try:
                with open(OUTPUT_PATH, 'r') as f:
                    actual = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f"Generated output is not valid JSON: {exc}")

            assert isinstance(actual, list), "The output JSON must be a list of strings."
            assert actual == expected, (
                f"Incorrect generated-case restoration order.\n"
                f"Expected: {expected}\nActual:   {actual}"
            )
    finally:
        with open(DB_PATH, 'wb') as f:
            f.write(original_db)
        with open(JSON_PATH, 'wb') as f:
            f.write(original_json)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
