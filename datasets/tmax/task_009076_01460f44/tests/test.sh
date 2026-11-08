#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import stat
import subprocess
import sys
from pathlib import Path

import pytest

OUTPUT = Path('/home/user/user_profiles.jsonl')
USERS = Path('/home/user/users.csv')
FOLLOWS = Path('/home/user/follows.csv')
POSTS = Path('/home/user/posts.csv')
EXACT_KEYS = {'user_id', 'name', 'total_post_views', 'second_degree_follows'}


def load_jsonl(path):
    assert path.exists(), f'Output file {path} is missing.'
    lines = path.read_text().splitlines()
    assert all(line.strip() for line in lines), 'JSONL output contains a blank line.'
    result = []
    for line_num, line in enumerate(lines, start=1):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f'Line {line_num} in {path} is not valid JSON: {line}')
        assert isinstance(obj, dict), f'Line {line_num} is not a JSON object.'
        assert set(obj) == EXACT_KEYS, f'Line {line_num} must have exactly the keys {sorted(EXACT_KEYS)}.'
        assert type(obj['user_id']) is int, f'Line {line_num}: user_id must be an integer.'
        assert type(obj['name']) is str, f'Line {line_num}: name must be a string.'
        assert type(obj['total_post_views']) is int, f'Line {line_num}: total_post_views must be an integer.'
        assert isinstance(obj['second_degree_follows'], list), f'Line {line_num}: second_degree_follows must be a list.'
        assert all(type(value) is int for value in obj['second_degree_follows']), f'Line {line_num}: second_degree_follows must contain only integers.'
        result.append(obj)
    return result


def derive_expected():
    with USERS.open(newline='') as f:
        users = [(int(row['id']), row['name']) for row in csv.DictReader(f)]

    direct = {user_id: set() for user_id, _ in users}
    with FOLLOWS.open(newline='') as f:
        for row in csv.DictReader(f):
            direct.setdefault(int(row['follower_id']), set()).add(int(row['followed_id']))

    views = {user_id: 0 for user_id, _ in users}
    with POSTS.open(newline='') as f:
        for row in csv.DictReader(f):
            author = int(row['author_id'])
            views[author] = views.get(author, 0) + int(row['views'])

    expected = []
    for user_id, name in sorted(users):
        second = set()
        for followed in direct.get(user_id, set()):
            second.update(direct.get(followed, set()))
        second.difference_update(direct.get(user_id, set()))
        second.discard(user_id)
        expected.append({
            'user_id': user_id,
            'name': name,
            'total_post_views': views.get(user_id, 0),
            'second_degree_follows': sorted(second),
        })
    return expected


def find_python_scripts():
    candidates = []
    excluded = Path('/tmp/test_final_state.py').resolve()
    for root_name in ('/home/user', '/tmp'):
        root = Path(root_name)
        if not root.exists():
            continue
        for path in root.rglob('*'):
            try:
                if path.resolve() == excluded or path.is_symlink():
                    continue
                if not stat.S_ISREG(path.stat().st_mode):
                    continue
                is_python = path.suffix.lower() == '.py'
                if not is_python:
                    first_line = path.open('rb').readline(256).lower()
                    is_python = first_line.startswith(b'#!') and b'python' in first_line
                if is_python:
                    candidates.append(path)
            except (OSError, UnicodeError):
                continue
    return sorted(set(candidates), key=lambda p: str(p))


def write_dynamic_fixture():
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 9000), 7)
    names = {user_id: f'User_{secrets.token_hex(4)}' for user_id in ids}

    user_rows = [(user_id, names[user_id]) for user_id in ids]
    rng.shuffle(user_rows)
    with USERS.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'name'])
        writer.writerows(user_rows)

    a, b, c, d, e, f_id, g = ids
    edges = [
        (a, b), (a, e), (a, c),
        (b, c), (b, d),
        (e, d), (c, a),
        (d, f_id), (f_id, g), (g, b),
    ]
    rng.shuffle(edges)
    with FOLLOWS.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['follower_id', 'followed_id'])
        writer.writerows(edges)

    post_rows = [
        (rng.randrange(10000, 99999), a, rng.randrange(1, 500)),
        (rng.randrange(10000, 99999), a, rng.randrange(1, 500)),
        (rng.randrange(10000, 99999), b, rng.randrange(1, 500)),
        (rng.randrange(10000, 99999), c, 0),
        (rng.randrange(10000, 99999), e, rng.randrange(1, 500)),
        (rng.randrange(10000, 99999), g, rng.randrange(1, 500)),
    ]
    rng.shuffle(post_rows)
    with POSTS.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['post_id', 'author_id', 'views'])
        writer.writerows(post_rows)


def test_user_profiles_and_executable_transformation_script():
    expected_data = [
        {'user_id': 1, 'name': 'Alice', 'total_post_views': 150, 'second_degree_follows': [3, 4]},
        {'user_id': 2, 'name': 'Bob', 'total_post_views': 200, 'second_degree_follows': [1]},
        {'user_id': 3, 'name': 'Charlie', 'total_post_views': 0, 'second_degree_follows': [2, 5]},
        {'user_id': 4, 'name': 'Diana', 'total_post_views': 0, 'second_degree_follows': []},
        {'user_id': 5, 'name': 'Eve', 'total_post_views': 500, 'second_degree_follows': []},
    ]

    actual_data = load_jsonl(OUTPUT)
    assert len(actual_data) == len(expected_data), f'Expected {len(expected_data)} lines, got {len(actual_data)}.'
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get('user_id') == expected['user_id'], f"Line {i+1}: Expected user_id {expected['user_id']}, got {actual.get('user_id')}"
        assert actual.get('name') == expected['name'], f"Line {i+1}: Expected name {expected['name']}, got {actual.get('name')}"
        assert actual.get('total_post_views') == expected['total_post_views'], f"Line {i+1}: Expected total_post_views {expected['total_post_views']}, got {actual.get('total_post_views')}"
        assert actual.get('second_degree_follows') == expected['second_degree_follows'], f"Line {i+1}: Expected second_degree_follows {expected['second_degree_follows']}, got {actual.get('second_degree_follows')}"

    scripts = find_python_scripts()
    assert scripts, 'No Python transformation script was found.'

    backups = {path: path.read_bytes() for path in (USERS, FOLLOWS, POSTS, OUTPUT)}
    errors = []
    passed = False
    try:
        for script in scripts:
            try:
                write_dynamic_fixture()
                expected_dynamic = derive_expected()
                if OUTPUT.exists():
                    OUTPUT.unlink()
                result = subprocess.run(
                    [sys.executable, str(script)],
                    cwd='/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
                assert result.returncode == 0, f'exited with status {result.returncode}: {result.stderr[-500:]}'
                actual_dynamic = load_jsonl(OUTPUT)
                assert actual_dynamic == expected_dynamic, 'produced incorrect output for dynamically generated CSV inputs'
                passed = True
                break
            except Exception as exc:
                errors.append(f'{script}: {exc}')
        assert passed, 'No submitted Python script correctly performed the transformation when executed. ' + ' | '.join(errors[-5:])
    finally:
        for path, content in backups.items():
            path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
