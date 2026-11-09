#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_graph_analyzer.py
import csv
import json
import os
import random
import subprocess
from pathlib import Path

project = Path('/home/user/graph_analyzer')
users_path = Path('/home/user/data/users.csv')
communications_path = Path('/home/user/data/communications.csv')
top_path = Path('/home/user/top_engineers.txt')
cypher_path = Path('/home/user/cypher_output.cql')

assert project.is_dir(), 'Cargo project /home/user/graph_analyzer is missing.'
assert (project / 'Cargo.toml').is_file(), 'Cargo.toml is missing.'
assert any(project.rglob('*.rs')), 'The project contains no Rust source files.'

metadata = json.loads(subprocess.check_output(
    ['cargo', 'metadata', '--no-deps', '--format-version', '1'],
    cwd=project,
    text=True,
))
packages = [p for p in metadata['packages'] if p['name'] == 'graph_analyzer']
assert packages, 'The Cargo package must be named graph_analyzer.'
assert any('bin' in target['kind'] for p in packages for target in p['targets']), \
    'The graph_analyzer package has no Rust binary target.'

subprocess.run(['cargo', 'build', '--quiet'], cwd=project, check=True)

original_users = users_path.read_bytes()
original_communications = communications_path.read_bytes()


def remove_outputs():
    for path in (top_path, cypher_path):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_program():
    remove_outputs()
    subprocess.run(['cargo', 'run', '--quiet'], cwd=project, check=True)
    assert top_path.is_file(), f'File {top_path} is missing after running the program.'
    assert cypher_path.is_file(), f'File {cypher_path} is missing after running the program.'


def nonempty_lines(path):
    with path.open('r') as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def assert_original_outputs():
    lines = nonempty_lines(top_path)
    expected_lines = [
        'Eve,100',
        'Charlie,22',
        'Alice,15'
    ]
    assert lines == expected_lines, \
        f'Content of {top_path} does not match the expected top 3 engineers and their out-degrees.'

    lines = nonempty_lines(cypher_path)
    expected_lines = [
        "CREATE (:User {id: 5, name: 'Eve', department: 'Engineering'});",
        "CREATE (:User {id: 3, name: 'Charlie', department: 'Engineering'});",
        "CREATE (:User {id: 1, name: 'Alice', department: 'Engineering'});",
        'MATCH (s:User {id: 5}), (r:User {id: 1}) CREATE (s)-[:MESSAGED {count: 100}]->(r);',
        'MATCH (s:User {id: 3}), (r:User {id: 1}) CREATE (s)-[:MESSAGED {count: 2}]->(r);',
        'MATCH (s:User {id: 3}), (r:User {id: 4}) CREATE (s)-[:MESSAGED {count: 20}]->(r);',
        'MATCH (s:User {id: 1}), (r:User {id: 2}) CREATE (s)-[:MESSAGED {count: 10}]->(r);',
        'MATCH (s:User {id: 1}), (r:User {id: 3}) CREATE (s)-[:MESSAGED {count: 5}]->(r);'
    ]
    assert len(lines) == len(expected_lines), \
        f'Expected {len(expected_lines)} lines in {cypher_path}, but found {len(lines)}.'
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, \
            f'Line {i+1} in {cypher_path} does not match expected output. Expected: {expected} Actual: {actual}'


def write_dynamic_inputs():
    users = [
        {'id': 1, 'name': 'Atlas', 'department': 'Engineering'},
        {'id': 2, 'name': 'Birch', 'department': 'Sales'},
        {'id': 3, 'name': 'Cedar', 'department': 'Engineering'},
        {'id': 4, 'name': 'Delta', 'department': 'Engineering'},
        {'id': 5, 'name': 'Ember', 'department': 'Engineering'},
        {'id': 6, 'name': 'Frost', 'department': 'HR'},
        {'id': 7, 'name': 'Gale', 'department': 'Engineering'},
    ]
    communications = [
        {'sender_id': 5, 'receiver_id': 6, 'message_count': random.randint(70, 79)},
        {'sender_id': 5, 'receiver_id': 2, 'message_count': random.randint(20, 24)},
        {'sender_id': 4, 'receiver_id': 7, 'message_count': random.randint(50, 59)},
        {'sender_id': 4, 'receiver_id': 1, 'message_count': random.randint(10, 14)},
        {'sender_id': 3, 'receiver_id': 7, 'message_count': random.randint(30, 39)},
        {'sender_id': 3, 'receiver_id': 1, 'message_count': random.randint(5, 9)},
        {'sender_id': 1, 'receiver_id': 3, 'message_count': random.randint(10, 14)},
        {'sender_id': 7, 'receiver_id': 2, 'message_count': random.randint(1, 3)},
        {'sender_id': 2, 'receiver_id': 6, 'message_count': random.randint(180, 220)},
    ]
    random.shuffle(communications)

    with users_path.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['id', 'name', 'department'])
        writer.writeheader()
        writer.writerows(users)
    with communications_path.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['sender_id', 'receiver_id', 'message_count'])
        writer.writeheader()
        writer.writerows(communications)
    return users, communications


def derive_expected(users, communications):
    totals = {u['id']: 0 for u in users}
    for edge in communications:
        totals[edge['sender_id']] = totals.get(edge['sender_id'], 0) + edge['message_count']

    top = sorted(
        (u for u in users if u['department'] == 'Engineering'),
        key=lambda u: totals[u['id']],
        reverse=True,
    )[:3]

    expected_top = [f"{u['name']},{totals[u['id']]}" for u in top]
    expected_cypher = [
        f"CREATE (:User {{id: {u['id']}, name: '{u['name']}', department: '{u['department']}'}});"
        for u in top
    ]
    for user in top:
        edges = sorted(
            (e for e in communications if e['sender_id'] == user['id']),
            key=lambda e: e['receiver_id'],
        )
        expected_cypher.extend(
            f"MATCH (s:User {{id: {e['sender_id']}}}), (r:User {{id: {e['receiver_id']}}}) "
            f"CREATE (s)-[:MESSAGED {{count: {e['message_count']}}}]->(r);"
            for e in edges
        )
    return expected_top, expected_cypher


try:
    run_program()
    assert_original_outputs()

    users, communications = write_dynamic_inputs()
    expected_top, expected_cypher = derive_expected(users, communications)
    run_program()
    assert nonempty_lines(top_path) == expected_top, \
        'top_engineers.txt was not computed correctly from the replacement CSV inputs.'
    assert nonempty_lines(cypher_path) == expected_cypher, \
        'cypher_output.cql was not computed and sorted correctly from the replacement CSV inputs.'
finally:
    users_path.write_bytes(original_users)
    communications_path.write_bytes(original_communications)
    subprocess.run(['cargo', 'run', '--quiet'], cwd=project, check=True)
PY_EOF

if python3 /tmp/verify_graph_analyzer.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
