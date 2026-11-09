#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import requests
from collections import defaultdict

def compute_expected_states():
    events = []
    with open('/app/config_events.jsonl', 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            # Clean up potential invalid surrogate escapes that break strict JSON parsers
            clean_line = line.replace('\\ud800', '')
            try:
                events.append(json.loads(clean_line))
            except json.JSONDecodeError:
                pass

    nodes = defaultdict(list)
    for ev in events:
        nodes[ev['node_id']].append(ev)

    expected = {}
    for node_id, evs in nodes.items():
        evs.sort(key=lambda x: x['timestamp'])
        state = [0, 0, 0]
        for ev in evs:
            vec = ev['vector']
            if ev['operation'] == 'add':
                state = [state[0] + vec[0], state[1] + vec[1], state[2] + vec[2]]
            elif ev['operation'] == 'multiply':
                state = [state[0] * vec[0], state[1] * vec[1], state[2] * vec[2]]

        sum_sq = state[0]**2 + state[1]**2 + state[2]**2
        if sum_sq <= 1000000:
            expected[node_id] = state

    return expected

def test_api_auth_missing():
    resp = requests.get('http://127.0.0.1:8080/state/A')
    assert resp.status_code == 401, f"Expected 401 Unauthorized when missing X-Auth-Pin header, got {resp.status_code}"

def test_api_auth_incorrect():
    resp = requests.get('http://127.0.0.1:8080/state/A', headers={'X-Auth-Pin': '0000'})
    assert resp.status_code == 401, f"Expected 401 Unauthorized for incorrect PIN, got {resp.status_code}"

def test_api_states():
    expected_states = compute_expected_states()

    # We also want to query a node that was dropped to ensure it returns 404
    all_nodes = set()
    with open('/app/config_events.jsonl', 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            clean_line = line.replace('\\ud800', '')
            try:
                all_nodes.add(json.loads(clean_line)['node_id'])
            except:
                pass

    pin = "4198"
    headers = {'X-Auth-Pin': pin}

    for node_id in all_nodes:
        resp = requests.get(f'http://127.0.0.1:8080/state/{node_id}', headers=headers)

        if node_id in expected_states:
            assert resp.status_code == 200, f"Expected 200 OK for valid node {node_id}, got {resp.status_code}. Response: {resp.text}"
            data = resp.json()
            assert data.get('node_id') == node_id, f"Expected node_id {node_id} in response"
            assert data.get('state') == expected_states[node_id], f"Expected state {expected_states[node_id]} for node {node_id}, got {data.get('state')}"
        else:
            assert resp.status_code == 404, f"Expected 404 Not Found for invalid/dropped node {node_id}, got {resp.status_code}. Response: {resp.text}"

def test_api_nonexistent_node():
    headers = {'X-Auth-Pin': '4198'}
    resp = requests.get('http://127.0.0.1:8080/state/NONEXISTENT_NODE_XYZ', headers=headers)
    assert resp.status_code == 404, f"Expected 404 Not Found for nonexistent node, got {resp.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
