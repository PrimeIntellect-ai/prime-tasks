#!/bin/bash
set -o pipefail
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

SOURCE=/home/user/optimizer.cpp
DATABASE=/home/user/etl_metadata.db
OUTPUT=/home/user/pipeline.json
BINARY=/tmp/optimizer_verifier
DB_BACKUP=$(mktemp /tmp/etl_metadata.XXXXXX.db)

cleanup() {
    if [ -f "$DB_BACKUP" ]; then
        cp "$DB_BACKUP" "$DATABASE" 2>/dev/null || true
        rm -f "$DB_BACKUP"
    fi
    rm -f "$BINARY"
}
trap cleanup EXIT

if [ ! -f "$SOURCE" ] || [ -L "$SOURCE" ] || [ ! -s "$SOURCE" ]; then
    exit 0
fi

if ! cp "$DATABASE" "$DB_BACKUP"; then
    exit 0
fi

if ! g++ -std=c++17 -O2 "$SOURCE" -lsqlite3 -o "$BINARY"; then
    exit 0
fi

rm -f "$OUTPUT"
if ! timeout 15s "$BINARY"; then
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

PIPELINE_JSON_PATH = '/home/user/pipeline.json'

def test_pipeline_json_exists():
    assert os.path.exists(PIPELINE_JSON_PATH), f"Output file {PIPELINE_JSON_PATH} is missing."
    assert os.path.isfile(PIPELINE_JSON_PATH), f"{PIPELINE_JSON_PATH} is not a file."

def test_pipeline_json_content():
    assert os.path.exists(PIPELINE_JSON_PATH), f"Cannot check content, {PIPELINE_JSON_PATH} is missing."

    with open(PIPELINE_JSON_PATH, 'r') as f:
        content = f.read()

    # Check exact minified format as requested
    stripped_content = content.strip()
    expected_content = '{"pipeline":["raw_clicks","stg_clicks","realtime_metrics","executive_dashboard"]}'

    assert stripped_content == expected_content, (
        f"The content of {PIPELINE_JSON_PATH} does not match the expected minified JSON string.\n"
        f"Expected: {expected_content}\n"
        f"Actual: {stripped_content}"
    )

    # Ensure it contains no internal spaces or newlines (except possibly a trailing newline)
    assert ' ' not in stripped_content, "The JSON output contains spaces, which violates the minified constraint."
    assert '\n' not in stripped_content, "The JSON output contains newlines inside the structure, which violates the minified constraint."

    # Validate it is valid JSON
    try:
        parsed = json.loads(stripped_content)
    except json.JSONDecodeError:
        pytest.fail("The output is not valid JSON.")

    assert "pipeline" in parsed, "The JSON output does not contain the 'pipeline' key."
    assert parsed["pipeline"] == ["raw_clicks", "stg_clicks", "realtime_metrics", "executive_dashboard"], "The shortest path is incorrect."
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    exit 0
fi

if ! python3 - "$BINARY" << 'DYNAMIC_TEST_EOF'
import collections
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys

binary = sys.argv[1]
database = '/home/user/etl_metadata.db'
output = '/home/user/pipeline.json'
token = secrets.token_hex(8)
long1 = 'long_a_' + token
long2 = 'long_b_' + token
long3 = 'long_c_' + token
fast = 'fast_' + token
noise = 'noise_' + token

rows = [
    (long1, 'SELECT * FROM raw_clicks'),
    (long2, f'SELECT * FROM {long1}'),
    (long3, f'SELECT * FROM {long2}'),
    (fast, f'SELECT * FROM {noise} JOIN raw_clicks ON {noise}.id = raw_clicks.id'),
    ('executive_dashboard', f'SELECT * FROM {long3} JOIN {fast} ON {long3}.id = {fast}.id'),
]

# Independently derive the expected shortest path from the same documented rules.
graph = collections.defaultdict(list)
for target, query in rows:
    for source in re.findall(r'(?:FROM|JOIN) ([a-zA-Z0-9_]+)', query):
        graph[source].append(target)
queue = collections.deque([('raw_clicks', ['raw_clicks'])])
seen = {'raw_clicks'}
expected_path = None
while queue:
    node, path = queue.popleft()
    if node == 'executive_dashboard':
        expected_path = path
        break
    for neighbor in graph[node]:
        if neighbor not in seen:
            seen.add(neighbor)
            queue.append((neighbor, path + [neighbor]))
assert expected_path is not None
expected_content = json.dumps({'pipeline': expected_path}, separators=(',', ':'))

if os.path.lexists(database):
    os.remove(database)
connection = sqlite3.connect(database)
connection.execute('CREATE TABLE jobs(id INTEGER PRIMARY KEY, target_table TEXT, sql_query TEXT)')
connection.executemany('INSERT INTO jobs(target_table, sql_query) VALUES (?, ?)', rows)
connection.commit()
connection.close()

if os.path.lexists(output):
    os.remove(output)
subprocess.run([binary], check=True, timeout=15)
assert os.path.isfile(output), 'The program did not create /home/user/pipeline.json'
with open(output, 'r') as handle:
    content = handle.read()
stripped = content.strip()
assert stripped == expected_content, f'Expected {expected_content}, got {stripped}'
assert ' ' not in stripped
assert '\n' not in stripped
assert json.loads(stripped) == {'pipeline': expected_path}
DYNAMIC_TEST_EOF
then
    exit 0
fi

# Restore the supplied database and require the independently compiled program to
# reproduce the original answer after the behavioral test.
if ! cp "$DB_BACKUP" "$DATABASE"; then
    exit 0
fi
rm -f "$OUTPUT"
if ! timeout 15s "$BINARY"; then
    exit 0
fi
if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    exit 0
fi

echo "1" > /logs/verifier/reward.txt
