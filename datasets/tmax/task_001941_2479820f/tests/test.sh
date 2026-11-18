#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import random
import sqlite3
import subprocess


def expected_edges(node_id):
    conn = sqlite3.connect('/app/network.db')
    try:
        cursor = conn.cursor()
        cursor.execute(
            '''
            SELECT target_id, event_type
            FROM audit_log_edges
            WHERE source_id = ?
            ORDER BY timestamp DESC
            ''',
            (node_id,),
        )
        latest_events = {}
        for target_id, event_type in cursor.fetchall():
            if target_id not in latest_events:
                latest_events[target_id] = event_type
        return sorted(
            target_id
            for target_id, event_type in latest_events.items()
            if event_type == 'LINK_UP'
        )
    finally:
        conn.close()


def test_fuzz_equivalence():
    target_script = '/home/user/etl_extractor.py'
    assert os.path.isfile(target_script), f'Target script not found at {target_script}'

    random.seed(42)
    inputs = [f'NODE_{str(i).zfill(3)}' for i in range(1, 101)]
    fuzz_inputs = random.choices(inputs, k=20)

    for node_id in fuzz_inputs:
        expected_json = expected_edges(node_id)

        target_cmd = [sys.executable, target_script, node_id]
        target_proc = subprocess.run(target_cmd, capture_output=True, text=True)
        assert target_proc.returncode == 0, (
            f'Target failed on input {node_id}:\n{target_proc.stderr}'
        )
        target_out = target_proc.stdout.strip()

        try:
            target_json = json.loads(target_out)
        except json.JSONDecodeError:
            target_json = target_out

        assert target_json == expected_json, (
            f"Mismatch on input '{node_id}'.\n"
            f'Expected output: {json.dumps(expected_json)}\n'
            f'Target output: {target_out}'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
