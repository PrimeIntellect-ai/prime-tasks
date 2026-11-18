#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import sqlite3
import subprocess
import sys

CSV_PATH = '/home/user/top_research.csv'
SCRIPT_PATH = '/home/user/process_results.py'
DB_PATH = '/home/user/research_data.db'
RUNNER_PATH = '/tmp/run_submission.py'

EXPECTED_CSV_CONTENT = [
    ['TopicName', 'TopPaperTitle', 'TopPaperCitations', 'TopicTotalCitations'],
    ['Artificial Intelligence', 'General AI History', '80', '80'],
    ['Deep Learning', 'CNNs', '1000', '1900'],
    ['Machine Learning', 'Advanced ML', '200', '350'],
    ['Natural Language Processing', 'Attention Mechanisms', '300', '350']
]

RUNNER_SOURCE = r'''import json
import runpy
import sqlite3
import sys

script_path, trace_path = sys.argv[1], sys.argv[2]
statements = []
real_connect = sqlite3.connect

def tracked_connect(*args, **kwargs):
    connection = real_connect(*args, **kwargs)
    connection.set_trace_callback(statements.append)
    return connection

sqlite3.connect = tracked_connect
try:
    runpy.run_path(script_path, run_name='__main__')
finally:
    with open(trace_path, 'w', encoding='utf-8') as trace_file:
        json.dump(statements, trace_file)
'''


def read_csv():
    with open(CSV_PATH, 'r', newline='', encoding='utf-8') as f:
        return list(csv.reader(f))


def run_submission(label):
    trace_path = f'/tmp/{label}_sqlite_trace.json'
    for path in (CSV_PATH, trace_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [sys.executable, RUNNER_PATH, SCRIPT_PATH, trace_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'process_results.py failed with exit code {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.path.exists(trace_path), 'No SQLite execution trace was produced.'
    with open(trace_path, 'r', encoding='utf-8') as f:
        return json.load(f)


def install_dynamic_database():
    for suffix in ('', '-wal', '-shm'):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    taxonomy = [
        (10, None, 'Computing'),
        (42, 10, 'Artificial Intelligence'),
        (7, 42, 'Vision'),
        (99, 42, 'Robotics'),
        (13, 7, '3D Perception'),
        (5, 10, 'Unrelated Systems'),
    ]
    papers = [
        (101, 42, 'Old AI Notes', 4),
        (102, 42, 'Modern AI Survey', 17),
        (103, 7, 'Basic Vision', 11),
        (104, 7, 'Vision, Revisited', 43),
        (105, 99, 'Small Robot', 3),
        (106, 99, 'Autonomous Lab', 101),
        (107, 13, 'Sparse Depth', 9),
        (108, 13, 'Dense Depth', 27),
        (109, 5, 'Must Not Appear', 9999),
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE taxonomy (id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT)')
        conn.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, topic_id INTEGER, title TEXT, citations INTEGER)')
        conn.executemany('INSERT INTO taxonomy VALUES (?,?,?)', taxonomy)
        conn.executemany('INSERT INTO papers VALUES (?,?,?,?)', papers)
        conn.commit()
    finally:
        conn.close()


def test_submission_executes_and_uses_required_sql():
    # Preserve the original script existence assertions.
    assert os.path.exists(SCRIPT_PATH), f'Script file {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a file.'

    with open(RUNNER_PATH, 'w', encoding='utf-8') as f:
        f.write(RUNNER_SOURCE)

    original_trace = run_submission('original')

    # Preserve the original CSV existence and exact-content assertions, but check
    # a freshly generated file rather than trusting an artifact left by the agent.
    assert os.path.exists(CSV_PATH), f'Output CSV file {CSV_PATH} does not exist.'
    assert os.path.isfile(CSV_PATH), f'{CSV_PATH} is not a file.'
    actual_content = read_csv()
    assert actual_content, 'The CSV file is empty.'
    assert actual_content[0] == EXPECTED_CSV_CONTENT[0], (
        f'CSV headers are incorrect. Expected {EXPECTED_CSV_CONTENT[0]}, got {actual_content[0]}'
    )
    assert len(actual_content) == len(EXPECTED_CSV_CONTENT), (
        f'CSV has incorrect number of rows. Expected {len(EXPECTED_CSV_CONTENT)}, got {len(actual_content)}'
    )
    for i in range(1, len(EXPECTED_CSV_CONTENT)):
        assert actual_content[i] == EXPECTED_CSV_CONTENT[i], (
            f'CSV row {i} is incorrect. Expected {EXPECTED_CSV_CONTENT[i]}, got {actual_content[i]}'
        )

    # Replace the database with unseen IDs, names, hierarchy depth, paper values,
    # and an unrelated high-citation paper, then require the script to regenerate.
    install_dynamic_database()
    dynamic_trace = run_submission('dynamic')
    expected_dynamic = [
        ['TopicName', 'TopPaperTitle', 'TopPaperCitations', 'TopicTotalCitations'],
        ['3D Perception', 'Dense Depth', '27', '36'],
        ['Artificial Intelligence', 'Modern AI Survey', '17', '21'],
        ['Robotics', 'Autonomous Lab', '101', '104'],
        ['Vision', 'Vision, Revisited', '43', '54'],
    ]
    assert os.path.exists(CSV_PATH), 'The script did not regenerate top_research.csv.'
    assert os.path.isfile(CSV_PATH), f'{CSV_PATH} is not a file.'
    assert read_csv() == expected_dynamic, 'CSV output is incorrect for the dynamic database.'

    # Verify that actual SQL executed through sqlite3 contains the required
    # recursive taxonomy traversal and paper-ranking window function.
    statements = [s for s in original_trace + dynamic_trace if isinstance(s, str)]
    recursive_queries = [
        s for s in statements
        if re.search(r'\bWITH\s+RECURSIVE\b', s, re.IGNORECASE)
        and re.search(r'\btaxonomy\b', s, re.IGNORECASE)
    ]
    ranking_queries = [
        s for s in statements
        if re.search(r'\b(?:ROW_NUMBER|RANK|DENSE_RANK)\s*\([^)]*\)\s*OVER\s*\(', s, re.IGNORECASE)
        and re.search(r'\bpapers\b', s, re.IGNORECASE)
    ]
    assert recursive_queries, 'No executed recursive CTE over taxonomy was observed.'
    assert ranking_queries, 'No executed ranking window function over papers was observed.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
