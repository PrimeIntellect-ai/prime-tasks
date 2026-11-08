#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import sqlite3
import subprocess
import tempfile

import pytest

SCRIPT_PATH = '/home/user/etl_graph.py'
DB_PATH = '/home/user/company_data.db'
OUTPUT_PATH = '/home/user/report.json'


def run_script(db_path, start_date, end_date, output_path):
    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run([
        'python3', SCRIPT_PATH,
        '--db', db_path,
        '--start-date', start_date,
        '--end-date', end_date,
        '--output', output_path
    ], capture_output=True, text=True)

    assert result.returncode == 0, (
        f"Script execution failed with return code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert os.path.isfile(output_path), f"Output JSON file was not created at {output_path}."

    with open(output_path, 'r') as f:
        content = f.read()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail("Output file is not valid JSON.")

    expected_content = json.dumps(data, indent=2)
    assert content.strip() == expected_content.strip(), \
        "JSON output is not formatted with an indentation of 2 spaces."
    return data


def test_script_exists():
    """Verify that the student's script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_argparse_and_parameterized_query_construction():
    """Verify the required CLI and parameterized SQLite call are present."""
    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()

    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f"Script is not valid Python: {exc}")

    imports_argparse = any(
        (isinstance(node, ast.Import) and any(alias.name == 'argparse' for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == 'argparse')
        for node in ast.walk(tree)
    )
    assert imports_argparse, "The script must use the argparse module."

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(
        (isinstance(call.func, ast.Attribute) and call.func.attr == 'ArgumentParser')
        or (isinstance(call.func, ast.Name) and call.func.id == 'ArgumentParser')
        for call in calls
    ), "The script must construct an argparse.ArgumentParser."
    assert any(
        isinstance(call.func, ast.Attribute) and call.func.attr == 'parse_args'
        for call in calls
    ), "The script must parse command-line arguments with argparse."

    required_options = {'--db', '--start-date', '--end-date', '--output'}
    string_literals = {
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }
    assert required_options.issubset(string_literals), \
        "The parser must define --db, --start-date, --end-date, and --output."

    parameterized_calls = [
        call for call in calls
        if isinstance(call.func, ast.Attribute)
        and call.func.attr in {'execute', 'executemany'}
        and len(call.args) >= 2
    ]
    assert parameterized_calls, \
        "SQLite queries must pass SQL parameters separately from the query string."


def test_script_execution():
    """Run the script with the required arguments and verify it completes successfully."""
    run_script(DB_PATH, '2023-01-01', '2023-03-31', OUTPUT_PATH)


def test_json_output_content():
    """Verify the content of the generated JSON file matches the expected results."""
    assert os.path.isfile(OUTPUT_PATH), f"Output JSON file missing at {OUTPUT_PATH}"

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")

    expected = [
        {
            "user_id": 2,
            "name": "Bob",
            "in_degree": 3
        },
        {
            "user_id": 1,
            "name": "Alice",
            "in_degree": 2
        },
        {
            "user_id": 5,
            "name": "Eve",
            "in_degree": 2
        },
        {
            "user_id": 3,
            "name": "Charlie",
            "in_degree": 1
        }
    ]

    assert data == expected, f"JSON output content does not match expected.\nExpected: {expected}\nActual: {data}"


def test_json_formatting():
    """Verify that the JSON is formatted with exactly 2 spaces of indentation."""
    assert os.path.isfile(OUTPUT_PATH), f"Output JSON file missing at {OUTPUT_PATH}"

    with open(OUTPUT_PATH, 'r') as f:
        content = f.read()

    data = json.loads(content)
    expected_content = json.dumps(data, indent=2)

    assert content.strip() == expected_content.strip(), "JSON output is not formatted with an indentation of 2 spaces."


def expected_report(users, messages, start_date, end_date):
    names = {user_id: name for user_id, name, _ in users}
    incoming = {}
    for _, sender_id, receiver_id, sent_at in messages:
        if start_date <= sent_at <= end_date and receiver_id in names:
            incoming.setdefault(receiver_id, set()).add(sender_id)

    result = [
        {
            'user_id': user_id,
            'name': names[user_id],
            'in_degree': len(senders)
        }
        for user_id, senders in incoming.items()
        if senders
    ]
    return sorted(result, key=lambda row: (-row['in_degree'], row['user_id']))


def test_generated_database_date_ranges_and_parameters():
    """Exercise the ETL against an independently generated database and ranges."""
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, f"communications_{secrets.token_hex(6)}.db")
        base = 1000 + secrets.randbelow(700000)
        ids = [base + offset for offset in (37, 5, 91, 18, 63, 44)]
        token = secrets.token_hex(5)
        users = [
            (ids[0], f"Alpha-{token}", 'Engineering'),
            (ids[1], f"Beta-{token}", 'HR'),
            (ids[2], f"Gamma-{token}", 'Sales'),
            (ids[3], f"Delta-{token}", 'Marketing'),
            (ids[4], f"Epsilon-{token}", 'Operations'),
            (ids[5], f"Zeta-{token}", 'Legal'),
        ]

        year = 2035 + secrets.randbelow(15)
        d1 = f'{year:04d}-06-01'
        d2 = f'{year:04d}-06-02'
        d3 = f'{year:04d}-06-03'
        d4 = f'{year:04d}-06-04'
        before = f'{year:04d}-05-31'
        after = f'{year:04d}-06-05'

        messages = [
            (1, ids[0], ids[1], d1),
            (2, ids[0], ids[1], d2),  # duplicate directed edge
            (3, ids[2], ids[1], d2),
            (4, ids[3], ids[0], d3),
            (5, ids[4], ids[0], d3),
            (6, ids[1], ids[2], d4),
            (7, ids[4], ids[3], before),
            (8, ids[5], ids[4], after),
        ]

        conn = sqlite3.connect(db_path)
        conn.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT)')
        conn.execute('CREATE TABLE messages (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, sent_at TEXT)')
        conn.executemany('INSERT INTO users VALUES (?, ?, ?)', users)
        conn.executemany('INSERT INTO messages VALUES (?, ?, ?, ?)', messages)
        conn.commit()
        conn.close()

        cases = [
            (d1, d4),
            (d3, d3),
            (d2, d2),
            (after, after),
            # Properly bound, this is simply a low lexical start date. Unsafe
            # interpolation turns the injected condition into SQL syntax.
            ("0000-01-01' AND 0=1 --", '9999-12-31'),
        ]

        for index, (start_date, end_date) in enumerate(cases):
            output_path = os.path.join(tmpdir, f'report_{index}_{secrets.token_hex(4)}.json')
            actual = run_script(db_path, start_date, end_date, output_path)
            expected = expected_report(users, messages, start_date, end_date)
            assert actual == expected, (
                f"Incorrect report for range {start_date!r} through {end_date!r}.\n"
                f"Expected: {expected}\nActual: {actual}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
