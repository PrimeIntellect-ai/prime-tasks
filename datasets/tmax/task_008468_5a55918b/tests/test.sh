#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess


def test_index_created():
    db_path = '/home/user/data.db'
    assert os.path.isfile(db_path), f"{db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_events_user';")
    count = cursor.fetchone()[0]
    assert count == 1, "The index 'idx_events_user' was not created in the database."

    cursor.execute("SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_events_user';")
    row = cursor.fetchone()
    assert row == ('events',), "The index 'idx_events_user' must index the events table."

    cursor.execute("PRAGMA index_info('idx_events_user');")
    indexed_columns = [row[2] for row in cursor.fetchall()]
    conn.close()
    assert indexed_columns == ['user_id'], "The index 'idx_events_user' must index events(user_id)."


def test_etl_script_exists_and_is_executable_bash():
    script_path = '/home/user/run_etl.sh'
    assert os.path.isfile(script_path), f"{script_path} was not created."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."
    with open(script_path, 'rb') as f:
        first_line = f.readline().decode('utf-8', errors='replace').strip()
    assert first_line.startswith('#!') and 'bash' in first_line, "run_etl.sh must be a Bash script with a Bash shebang."


def test_output_na_jsonl():
    file_path = '/home/user/output_NA.jsonl'
    assert os.path.isfile(file_path), f"{file_path} was not created."

    with open(file_path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 2, f"Expected 2 lines in {file_path}, found {len(lines)}."

    parsed_data = []
    for line in lines:
        try:
            parsed_data.append(json.loads(line))
        except json.JSONDecodeError:
            assert False, f"Line in {file_path} is not valid JSON: {line}"

    parsed_data.sort(key=lambda x: x.get('user_id', 0))
    expected_data = [
        {"user_id": 1, "name": "Alice", "total_events": 3, "event_types": ["login", "click", "logout"]},
        {"user_id": 3, "name": "Charlie", "total_events": 2, "event_types": ["login", "purchase"]}
    ]
    assert parsed_data == expected_data, f"Data in {file_path} does not match expected output."


def test_output_eu_jsonl():
    file_path = '/home/user/output_EU.jsonl'
    assert os.path.isfile(file_path), f"{file_path} was not created."

    with open(file_path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 2, f"Expected 2 lines in {file_path}, found {len(lines)}."

    parsed_data = []
    for line in lines:
        try:
            parsed_data.append(json.loads(line))
        except json.JSONDecodeError:
            assert False, f"Line in {file_path} is not valid JSON: {line}"

    parsed_data.sort(key=lambda x: x.get('user_id', 0))
    expected_data = [
        {"user_id": 2, "name": "Bob", "total_events": 1, "event_types": ["login"]},
        {"user_id": 4, "name": "Diana", "total_events": 2, "event_types": ["login", "click"]}
    ]
    assert parsed_data == expected_data, f"Data in {file_path} does not match expected output."


def test_summary_txt():
    file_path = '/home/user/summary.txt'
    assert os.path.isfile(file_path), f"{file_path} was not created."

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Region: NA | Top User: Alice | Events: 3",
        "Region: EU | Top User: Diana | Events: 2"
    ]
    for expected in expected_lines:
        assert expected in lines, f"Expected summary line '{expected}' not found in {file_path}."


def test_script_executes_for_safe_arbitrary_region():
    db_path = '/home/user/data.db'
    script_path = '/home/user/run_etl.sh'
    summary_path = '/home/user/summary.txt'
    token = secrets.token_hex(6)
    region = f"VERIFY_{token}' OR 1=1 --"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT COALESCE(MAX(id), 0) FROM users")
    base_user = cursor.fetchone()[0] + 100
    cursor.execute("SELECT COALESCE(MAX(id), 0) FROM events")
    base_event = cursor.fetchone()[0] + 100

    fixture_users = [
        (base_user, f'Lower_{token}', region),
        (base_user + 1, f'Higher_{token}', region),
    ]
    fixture_events = [
        (base_event, base_user, f'first_{token}', '2040-01-01 00:00:00'),
        (base_event + 1, base_user, f'second_"_{token}', '2040-01-01 00:01:00'),
        (base_event + 2, base_user + 1, f'alpha_{token}', '2040-01-01 00:02:00'),
        (base_event + 3, base_user + 1, f'beta_{token}', '2040-01-01 00:03:00'),
    ]
    cursor.executemany("INSERT INTO users(id, name, region) VALUES (?, ?, ?)", fixture_users)
    cursor.executemany("INSERT INTO events(id, user_id, event_type, event_time) VALUES (?, ?, ?, ?)", fixture_events)
    conn.commit()

    cursor.execute("SELECT id, name FROM users WHERE region = ? ORDER BY id", (region,))
    expected = []
    for user_id, name in cursor.fetchall():
        cursor.execute("SELECT event_type FROM events WHERE user_id = ? ORDER BY id", (user_id,))
        event_types = [row[0] for row in cursor.fetchall()]
        expected.append({
            'user_id': user_id,
            'name': name,
            'total_events': len(event_types),
            'event_types': event_types,
        })
    conn.close()

    output_path = f'/home/user/output_{region}.jsonl'
    if os.path.exists(output_path):
        os.remove(output_path)

    sentinel = f'Verifier sentinel {token}\n'
    with open(summary_path, 'a') as f:
        f.write(sentinel)
    with open(summary_path, 'rb') as f:
        summary_before = f.read()

    result = subprocess.run(
        [script_path, region],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"run_etl.sh failed for an arbitrary safely quoted region: {result.stderr}"
    assert os.path.isfile(output_path), f"The executed script did not create {output_path}."

    with open(output_path, 'r') as f:
        lines = f.read().splitlines()
    assert len(lines) == len(expected), f"Expected {len(expected)} JSONL records, found {len(lines)}."
    try:
        actual = [json.loads(line) for line in lines]
    except json.JSONDecodeError as exc:
        assert False, f"Executed script produced invalid JSONL: {exc}"
    actual.sort(key=lambda item: item.get('user_id', 0))
    assert actual == expected, "Executed script did not derive the arbitrary region output from the database."

    top = min(expected, key=lambda item: (-item['total_events'], item['user_id']))
    expected_summary = f"Region: {region} | Top User: {top['name']} | Events: {top['total_events']}"
    with open(summary_path, 'rb') as f:
        summary_after = f.read()
    assert summary_after.startswith(summary_before), "The script must append to summary.txt without replacing its existing contents."
    summary_lines = [line.strip() for line in summary_after.decode('utf-8').splitlines() if line.strip()]
    assert summary_lines[-1] == expected_summary, "The executed script appended an incorrect summary line."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
