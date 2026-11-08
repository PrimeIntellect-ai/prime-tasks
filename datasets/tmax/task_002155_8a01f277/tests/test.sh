#!/bin/bash
set -e
mkdir -p /logs/verifier

DB_PATH=/home/user/knowledge_graph.db
DB_BACKUP=$(mktemp)
cp -p "$DB_PATH" "$DB_BACKUP"
restore_db() {
    cp -p "$DB_BACKUP" "$DB_PATH"
    rm -f "$DB_BACKUP"
}
trap restore_db EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import re
import secrets
import sqlite3
import subprocess

import pytest

SCRIPT_PATH = '/home/user/query_optimizer.py'
OUTPUT_PATH = '/home/user/optimized_results.json'
DB_PATH = '/home/user/knowledge_graph.db'


def db_hash():
    with open(DB_PATH, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def run_script(skill, limit, offset):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    before = db_hash()
    result = subprocess.run(
        ['python3', SCRIPT_PATH, skill, str(limit), str(offset)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'Script execution failed with return code {result.returncode}.\n'
        f'Stdout: {result.stdout}\nStderr: {result.stderr}'
    )
    assert db_hash() == before, 'The script modified the database.'
    assert os.path.isfile(OUTPUT_PATH), (
        f'Output file {OUTPUT_PATH} was not created after running the script.'
    )

    try:
        with open(OUTPUT_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'Output file {OUTPUT_PATH} does not contain valid JSON: {exc}')

    assert isinstance(data, list), 'Output JSON must be a list of objects.'
    for row in data:
        assert isinstance(row, dict), 'Every result must be a JSON object.'
        assert list(row.keys()) == [
            'user_a', 'user_b', 'shared_projects_count'
        ], f'Incorrect result object structure: {row}'
        assert isinstance(row['user_a'], str)
        assert isinstance(row['user_b'], str)
        assert isinstance(row['shared_projects_count'], int)
    return data


def oracle(skill, limit, offset):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            '''
            SELECT ua.name, ub.name, COUNT(DISTINCT pma.project_id)
            FROM users AS ua
            JOIN user_skills AS usa ON usa.user_id = ua.id
            JOIN skills AS sa ON sa.id = usa.skill_id
            JOIN project_members AS pma ON pma.user_id = ua.id
            JOIN project_members AS pmb ON pmb.project_id = pma.project_id
            JOIN users AS ub ON ub.id = pmb.user_id
            JOIN user_skills AS usb ON usb.user_id = ub.id
            JOIN skills AS sb ON sb.id = usb.skill_id
            WHERE sa.skill_name = ?
              AND sb.skill_name = ?
              AND ua.name < ub.name
            GROUP BY ua.name, ub.name
            ORDER BY COUNT(DISTINCT pma.project_id) DESC,
                     ua.name ASC, ub.name ASC
            LIMIT ? OFFSET ?
            ''',
            (skill, skill, limit, offset),
        ).fetchall()
    finally:
        conn.close()

    return [
        {'user_a': a, 'user_b': b, 'shared_projects_count': count}
        for a, b, count in rows
    ]


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'


def test_query_is_parameterized_sql_with_joins():
    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    strings = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    strings[target.id] = node.value.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            strings[node.target.id] = node.value.value

    qualifying = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or len(node.args) < 2:
            continue
        func = node.func
        if not isinstance(func, ast.Attribute) or func.attr != 'execute':
            continue
        first = node.args[0]
        if isinstance(first, ast.Constant) and isinstance(first.value, str):
            sql = first.value
        elif isinstance(first, ast.Name):
            sql = strings.get(first.id, '')
        else:
            sql = ''
        upper = sql.upper()
        placeholders = len(re.findall(r'\?', sql)) + len(re.findall(r'(?<!:):[A-Za-z_]\w*', sql))
        if (
            'SELECT' in upper
            and upper.count('JOIN') >= 4
            and 'GROUP BY' in upper
            and 'ORDER BY' in upper
            and 'LIMIT' in upper
            and 'OFFSET' in upper
            and placeholders >= 3
        ):
            qualifying.append(node)

    assert qualifying, (
        'The script must execute a parameterized SQL query containing the joins, '
        'grouping, ordering, limit, and offset rather than computing results in Python.'
    )


def test_script_execution_and_output():
    expected_data = [
        {'user_a': 'Alice Smith', 'user_b': 'Bob Jones', 'shared_projects_count': 2},
        {'user_a': 'Alice Smith', 'user_b': 'Charlie Brown', 'shared_projects_count': 2},
        {'user_a': 'Charlie Brown', 'user_b': 'Diana Prince', 'shared_projects_count': 2},
        {'user_a': 'Alice Smith', 'user_b': 'Diana Prince', 'shared_projects_count': 1},
        {'user_a': 'Bob Jones', 'user_b': 'Charlie Brown', 'shared_projects_count': 1},
    ]
    data = run_script('Python', 5, 0)
    assert len(data) == len(expected_data), (
        f'Expected {len(expected_data)} results, but got {len(data)}.'
    )
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual == expected, (
            f'Result at index {i} does not match expected.\n'
            f'Expected: {expected}\nGot: {actual}'
        )


def test_pagination_and_parameterization():
    expected_data = [
        {'user_a': 'Alice Smith', 'user_b': 'Charlie Brown', 'shared_projects_count': 2},
        {'user_a': 'Charlie Brown', 'user_b': 'Diana Prince', 'shared_projects_count': 2},
    ]
    data = run_script('Python', 2, 1)
    assert data == expected_data, f'Pagination failed. Expected {expected_data}, Got {data}'


def test_behavior_on_unpredictable_database_rows_and_inputs():
    token = secrets.token_hex(12)
    skill = 'VerifierSkill_' + token
    names = [f'User_{token}_{suffix}' for suffix in ('Zulu', 'Alpha', 'Mike', 'Bravo')]

    conn = sqlite3.connect(DB_PATH)
    try:
        next_skill = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM skills').fetchone()[0]
        next_user = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM users').fetchone()[0]
        next_project = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM projects').fetchone()[0]

        conn.execute('INSERT INTO skills(id, skill_name) VALUES (?, ?)', (next_skill, skill))
        user_ids = []
        for i, name in enumerate(names):
            uid = next_user + i
            user_ids.append(uid)
            conn.execute('INSERT INTO users(id, name) VALUES (?, ?)', (uid, name))
            conn.execute('INSERT INTO user_skills(user_id, skill_id) VALUES (?, ?)', (uid, next_skill))

        memberships = [
            (0, [0, 1, 2]),
            (1, [0, 1]),
            (2, [2, 3]),
        ]
        for project_delta, members in memberships:
            pid = next_project + project_delta
            conn.execute('INSERT INTO projects(id, title) VALUES (?, ?)', (pid, f'Project_{token}_{project_delta}'))
            for member in members:
                conn.execute(
                    'INSERT INTO project_members(project_id, user_id) VALUES (?, ?)',
                    (pid, user_ids[member]),
                )
        conn.commit()
    finally:
        conn.close()

    for limit, offset in [(20, 0), (2, 1), (1, 3), (5, 10)]:
        assert run_script(skill, limit, offset) == oracle(skill, limit, offset)

    injection = skill + "' OR 1=1 --"
    assert run_script(injection, 20, 0) == oracle(injection, 20, 0) == []
    assert run_script('C++', 7, 0) == oracle('C++', 7, 0)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
