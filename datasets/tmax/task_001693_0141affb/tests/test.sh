#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import secrets
import stat
import subprocess
import sys
import uuid

import networkx as nx

ANALYZE = '/home/user/analyze.py'
DATA = '/home/user/data/messages.jsonl'
REPORT = '/home/user/report.json'

CANONICAL_EVENTS = [
    {"msg_id": 1, "sender": "Alice", "receiver": "Bob", "timestamp": "2023-10-01T10:00:00", "bytes": 100},
    {"msg_id": 2, "sender": "Bob", "receiver": "Charlie", "timestamp": "2023-10-01T10:05:00", "bytes": 200},
    {"msg_id": 3, "sender": "Alice", "receiver": "Charlie", "timestamp": "2023-10-01T10:10:00", "bytes": 150},
    {"msg_id": 4, "sender": "Charlie", "receiver": "Alice", "timestamp": "2023-10-01T10:15:00", "bytes": 50},
    {"msg_id": 5, "sender": "David", "receiver": "Alice", "timestamp": "2023-10-01T10:20:00", "bytes": 300},
    {"msg_id": 6, "sender": "Alice", "receiver": "David", "timestamp": "2023-10-01T10:25:00", "bytes": 100},
    {"msg_id": 7, "sender": "Bob", "receiver": "Alice", "timestamp": "2023-10-01T10:30:00", "bytes": 250},
    {"msg_id": 8, "sender": "Alice", "receiver": "Eve", "timestamp": "2023-10-01T10:35:00", "bytes": 80},
    {"msg_id": 9, "sender": "Eve", "receiver": "Alice", "timestamp": "2023-10-01T10:40:00", "bytes": 90},
    {"msg_id": 10, "sender": "Alice", "receiver": "Bob", "timestamp": "2023-10-01T10:45:00", "bytes": 120},
    {"msg_id": 11, "sender": "Charlie", "receiver": "Bob", "timestamp": "2023-10-01T10:50:00", "bytes": 60},
    {"msg_id": 12, "sender": "Bob", "receiver": "David", "timestamp": "2023-10-01T10:55:00", "bytes": 210},
    {"msg_id": 13, "sender": "David", "receiver": "Bob", "timestamp": "2023-10-01T11:00:00", "bytes": 310},
    {"msg_id": 14, "sender": "Alice", "receiver": "Charlie", "timestamp": "2023-10-01T11:05:00", "bytes": 140},
    {"msg_id": 15, "sender": "Bob", "receiver": "Eve", "timestamp": "2023-10-01T11:10:00", "bytes": 220},
    {"msg_id": 16, "sender": "Eve", "receiver": "Charlie", "timestamp": "2023-10-01T11:15:00", "bytes": 95},
    {"msg_id": 17, "sender": "Charlie", "receiver": "David", "timestamp": "2023-10-01T11:20:00", "bytes": 70},
    {"msg_id": 18, "sender": "Alice", "receiver": "David", "timestamp": "2023-10-01T11:25:00", "bytes": 110},
    {"msg_id": 19, "sender": "David", "receiver": "Eve", "timestamp": "2023-10-01T11:30:00", "bytes": 320},
    {"msg_id": 20, "sender": "Bob", "receiver": "Alice", "timestamp": "2023-10-01T11:35:00", "bytes": 260}
]

EXPECTED_CANONICAL = [
    {"msg_id": 7, "sender": "Bob", "timestamp": "2023-10-01T10:30:00", "bytes": 250, "cumulative_bytes": 450},
    {"msg_id": 8, "sender": "Alice", "timestamp": "2023-10-01T10:35:00", "bytes": 80, "cumulative_bytes": 430},
    {"msg_id": 10, "sender": "Alice", "timestamp": "2023-10-01T10:45:00", "bytes": 120, "cumulative_bytes": 550},
    {"msg_id": 12, "sender": "Bob", "timestamp": "2023-10-01T10:55:00", "bytes": 210, "cumulative_bytes": 660},
    {"msg_id": 13, "sender": "David", "timestamp": "2023-10-01T11:00:00", "bytes": 310, "cumulative_bytes": 610}
]


def write_events(events):
    os.makedirs(os.path.dirname(DATA), exist_ok=True)
    with open(DATA, 'w', encoding='utf-8') as f:
        for event in events:
            f.write(json.dumps(event) + '\n')


def execute_analyzer(events):
    write_events(events)
    if os.path.lexists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        [sys.executable, ANALYZE],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'analyze.py exited with status {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )
    assert os.path.isfile(REPORT), 'analyze.py did not create /home/user/report.json.'
    try:
        with open(REPORT, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        assert False, f'/home/user/report.json is not a valid JSON file: {exc}'


def derive_expected(events):
    graph = nx.DiGraph()
    for event in events:
        sender = event['sender']
        receiver = event['receiver']
        if graph.has_edge(sender, receiver):
            graph[sender][receiver]['weight'] += event['bytes']
        else:
            graph.add_edge(sender, receiver, weight=event['bytes'])

    ranks = nx.pagerank(graph, alpha=0.85, weight='weight')
    top_three = set(sorted(ranks, key=lambda user: (-ranks[user], user))[:3])

    cumulative = {}
    rows = []
    selected = [event for event in events if event['sender'] in top_three]
    selected.sort(key=lambda event: (event['sender'], event['timestamp'], event['msg_id']))
    for event in selected:
        sender = event['sender']
        cumulative[sender] = cumulative.get(sender, 0) + event['bytes']
        rows.append({
            'msg_id': event['msg_id'],
            'sender': sender,
            'timestamp': event['timestamp'],
            'bytes': event['bytes'],
            'cumulative_bytes': cumulative[sender],
        })

    rows.sort(key=lambda row: (row['timestamp'], row['msg_id']))
    return rows[5:10]


def assert_report(data, expected):
    assert isinstance(data, list), 'The output in report.json must be a JSON array.'
    assert len(data) == 5, f'Expected exactly 5 items in report.json for Page 2, but found {len(data)}.'
    assert len(expected) == 5, 'Internal generated fixture did not produce a full second page.'

    for i, expected_item in enumerate(expected):
        actual_item = data[i]
        assert isinstance(actual_item, dict), f'Item at index {i} must be a JSON object.'
        expected_keys = {'msg_id', 'sender', 'timestamp', 'bytes', 'cumulative_bytes'}
        actual_keys = set(actual_item.keys())
        assert actual_keys == expected_keys, f'Item at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}.'
        assert actual_item['msg_id'] == expected_item['msg_id'], f"Item at index {i} has wrong msg_id. Expected {expected_item['msg_id']}, got {actual_item['msg_id']}."
        assert actual_item['sender'] == expected_item['sender'], f"Item at index {i} has wrong sender. Expected {expected_item['sender']}, got {actual_item['sender']}."
        assert actual_item['timestamp'] == expected_item['timestamp'], f"Item at index {i} has wrong timestamp. Expected {expected_item['timestamp']}, got {actual_item['timestamp']}."
        assert actual_item['bytes'] == expected_item['bytes'], f"Item at index {i} has wrong bytes. Expected {expected_item['bytes']}, got {actual_item['bytes']}."
        assert actual_item['cumulative_bytes'] == expected_item['cumulative_bytes'], f"Item at index {i} has wrong cumulative_bytes. Expected {expected_item['cumulative_bytes']}, got {actual_item['cumulative_bytes']}."


def make_random_events():
    rng = secrets.SystemRandom()
    while True:
        users = [f'user_{uuid.uuid4().hex}' for _ in range(6)]
        ids = rng.sample(range(1000, 100000), 54)
        events = []
        base = datetime.datetime(2025, 1, 1, 8, 0, 0)

        # Seed a cycle so every user is present in a strongly connected graph.
        for i, user in enumerate(users):
            events.append({
                'msg_id': ids[i],
                'sender': user,
                'receiver': users[(i + 1) % len(users)],
                'timestamp': (base + datetime.timedelta(minutes=rng.randrange(0, 8))).isoformat(),
                'bytes': rng.randrange(20, 500),
            })

        for i in range(6, 54):
            sender = rng.choice(users)
            receiver = rng.choice([user for user in users if user != sender])
            events.append({
                'msg_id': ids[i],
                'sender': sender,
                'receiver': receiver,
                # Deliberately use a small range to exercise timestamp/msg_id ties.
                'timestamp': (base + datetime.timedelta(minutes=rng.randrange(0, 18))).isoformat(),
                'bytes': rng.randrange(1, 2000),
            })

        if len(derive_expected(events)) == 5:
            return events


def test_report_file_exists():
    assert os.path.isfile(REPORT), 'The output file /home/user/report.json was not found.'


def test_analyzer_exists_and_canonical_report():
    assert os.path.lexists(ANALYZE), 'The required script /home/user/analyze.py was not found.'
    mode = os.lstat(ANALYZE).st_mode
    assert stat.S_ISREG(mode), '/home/user/analyze.py must be a regular file.'

    data = execute_analyzer(CANONICAL_EVENTS)
    assert_report(data, EXPECTED_CANONICAL)


def test_analyzer_processes_unseen_inputs():
    for _ in range(3):
        events = make_random_events()
        expected = derive_expected(events)
        actual = execute_analyzer(events)
        assert_report(actual, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
