#!/bin/bash
set -o pipefail
mkdir -p /logs/verifier

run_tests() {
    local project=/home/user/log_processor
    local backup

    test -d "$project" || return 1
    test -f "$project/Cargo.toml" || return 1
    test -f "$project/src/main.rs" || return 1

    python3 - <<'PY' || return 1
import pathlib
import re

project = pathlib.Path('/home/user/log_processor')
cargo = (project / 'Cargo.toml').read_text(errors='replace')
rust_files = list((project / 'src').rglob('*.rs'))
assert rust_files, 'Rust project has no source files'
source = '\n'.join(p.read_text(errors='replace') for p in rust_files)

assert re.search(r'(?mi)^\s*regex\s*=', cargo), 'Cargo.toml must declare the regex crate'
assert re.search(r'\bregex\s*::\s*Regex\b|\buse\s+regex\b', source), 'Rust code must use regex parsing'

# A manually implemented distance routine must be present and actually referenced.
functions = re.findall(r'\bfn\s+([A-Za-z_][A-Za-z0-9_]*(?:levenshtein|edit_distance)[A-Za-z0-9_]*)\s*\(', source, re.I)
assert functions, 'No manually implemented Levenshtein/edit-distance function found'
assert any(len(re.findall(r'\b' + re.escape(name) + r'\b', source)) >= 2 for name in functions), \
    'The distance function is not called'

# Reject common crates that would delegate the required manual implementation.
banned = ('strsim', 'levenshtein', 'edit-distance', 'edit_distance', 'triple_accel')
lower_cargo = cargo.lower()
for name in banned:
    assert name not in lower_cargo, f'External distance implementation is not allowed: {name}'
PY

    test -f /home/user/raw_logs.txt || return 1
    test -f /home/user/processed_logs.csv || return 1
    test -f /home/user/logs.db || return 1

    backup=$(mktemp -d) || return 1
    cp /home/user/raw_logs.txt "$backup/raw_logs.txt" || return 1
    cp /home/user/processed_logs.csv "$backup/processed_logs.csv" || return 1
    cp /home/user/logs.db "$backup/logs.db" || return 1

    restore_files() {
        cp "$backup/raw_logs.txt" /home/user/raw_logs.txt 2>/dev/null || true
        cp "$backup/processed_logs.csv" /home/user/processed_logs.csv 2>/dev/null || true
        cp "$backup/logs.db" /home/user/logs.db 2>/dev/null || true
    }
    trap restore_files EXIT

    python3 - <<'PY' || return 1
import secrets

s1, s2, s3 = ('dyn_' + secrets.token_hex(8) for _ in range(3))
lines = [
    f'[2026-08-11T01:02:03Z] 203.0.113.17 "GET /dynamic///alpha//item HTTP/1.1" 207 "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "{s1}"',
    f'[2026-08-11T01:02:04Z] 203.0.113.18 "POST /must/be/discarded HTTP/1.0" 500 "curl/9.1.2" "{s1}"',
    '[2026-08-11T01:02:05Z] malformed line which must be discarded',
    f'[2026-08-11T01:02:06Z] 198.51.100.9 "PUT ////beta///z HTTP/2" 418 "curl/7.68.0" "{s2}"',
    f'[2026-08-11T01:02:07Z] 192.0.2.44 "DELETE /plain HTTP/1.1" 204 "Mozilla/5.0 (X11; Linux x86_64)" "{s3}"',
    f'[2026-08-11T01:02:08Z] 192.0.2.45 "GET /bad HTTP/1.1" 20x "curl/1" "bad_{s3}"',
    f'[2026-08-11T01:02:09Z] 192.0.2.46 "GET /bad HTTP/1.1" 200 "curl/1" "bad_{s3}" trailing',
]
with open('/home/user/raw_logs.txt', 'w') as f:
    f.write('\n'.join(lines) + '\n')
PY

    rm -f /home/user/processed_logs.csv /home/user/logs.db
    (cd "$project" && timeout 120 cargo run --quiet) || return 1

    python3 - <<'PY' || return 1
import os
import re

baseline = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
pattern = re.compile(r'^\[(.*?)\] (.*?) "(.*?) (.*?) (.*?)" (\d+) "(.*?)" "(.*?)"$')

def distance(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1,
                               previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]

expected = []
seen = set()
with open('/home/user/raw_logs.txt') as f:
    for raw in f:
        match = pattern.match(raw.strip())
        if not match:
            continue
        timestamp, ip, method, path, protocol, status, ua, session = match.groups()
        if session in seen:
            continue
        seen.add(session)
        path = re.sub(r'/+', '/', path)
        expected.append(f'{timestamp},{ip},{path},{int(status)},{session},{distance(ua, baseline)}')

assert os.path.isfile('/home/user/processed_logs.csv'), 'Running the Rust tool did not create processed_logs.csv'
with open('/home/user/processed_logs.csv') as f:
    actual = [line.strip() for line in f if line.strip()]
assert actual == expected, f'Rust tool failed generated behavioral test: expected {expected!r}, got {actual!r}'
PY

    restore_files
    trap - EXIT
    rm -rf "$backup"

    # Exercise the required SQLite CLI against the submitted database.
    test "$(sqlite3 /home/user/logs.db 'PRAGMA integrity_check;')" = "ok" || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3


def levenshtein_distance(s1, s2):
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def process_logs(raw_logs_path):
    log_pattern = re.compile(r'^\[(.*?)\] (.*?) "(.*?) (.*?) (.*?)" (\d+) "(.*?)" "(.*?)"$')
    baseline_ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    seen_sessions = set()
    processed_records = []

    with open(raw_logs_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = log_pattern.match(line)
            if not match:
                continue
            timestamp, ip, method, path, protocol, status, ua, session_id = match.groups()
            if session_id in seen_sessions:
                continue
            seen_sessions.add(session_id)
            cleaned_path = re.sub(r'/+', '/', path)
            distance = levenshtein_distance(ua, baseline_ua)
            processed_records.append((timestamp, ip, cleaned_path, int(status), session_id, distance))
    return processed_records


def test_processed_csv_exists_and_correct():
    raw_logs_path = "/home/user/raw_logs.txt"
    csv_path = "/home/user/processed_logs.csv"
    assert os.path.exists(raw_logs_path), f"Raw logs file missing: {raw_logs_path}"
    assert os.path.exists(csv_path), f"Processed CSV file missing: {csv_path}"
    expected_records = process_logs(raw_logs_path)
    with open(csv_path, "r") as f:
        csv_lines = [line.strip() for line in f if line.strip()]
    assert len(csv_lines) == len(expected_records), f"Expected {len(expected_records)} rows in CSV, found {len(csv_lines)}"
    for i, expected in enumerate(expected_records):
        expected_line = f"{expected[0]},{expected[1]},{expected[2]},{expected[3]},{expected[4]},{expected[5]}"
        assert csv_lines[i] == expected_line, f"CSV line {i+1} mismatch. Expected: {expected_line}, Got: {csv_lines[i]}"


def test_sqlite_database_exists_and_correct():
    raw_logs_path = "/home/user/raw_logs.txt"
    db_path = "/home/user/logs.db"
    assert os.path.exists(db_path), f"SQLite database missing: {db_path}"
    expected_records = process_logs(raw_logs_path)
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cleaned_logs'")
    assert cursor.fetchone() is not None, "Table 'cleaned_logs' does not exist in the database."

    cursor.execute("PRAGMA table_info(cleaned_logs)")
    schema = [(row[1], row[2].upper()) for row in cursor.fetchall()]
    assert schema == [
        ('timestamp', 'TEXT'), ('ip_address', 'TEXT'), ('path', 'TEXT'),
        ('status_code', 'INTEGER'), ('session_id', 'TEXT'), ('ua_distance', 'INTEGER')
    ], f"Unexpected cleaned_logs schema: {schema}"

    cursor.execute("SELECT COUNT(*) FROM cleaned_logs")
    count = cursor.fetchone()[0]
    assert count == len(expected_records), f"Expected {len(expected_records)} rows in 'cleaned_logs' table, found {count}"
    cursor.execute("SELECT timestamp, ip_address, path, status_code, session_id, ua_distance FROM cleaned_logs ORDER BY session_id")
    db_rows = cursor.fetchall()
    expected_sorted = sorted(expected_records, key=lambda x: x[4])
    for i, (expected, db_row) in enumerate(zip(expected_sorted, db_rows)):
        assert str(db_row[0]) == expected[0], f"Row {i} timestamp mismatch"
        assert str(db_row[1]) == expected[1], f"Row {i} ip_address mismatch"
        assert str(db_row[2]) == expected[2], f"Row {i} path mismatch"
        assert int(db_row[3]) == expected[3], f"Row {i} status_code mismatch"
        assert str(db_row[4]) == expected[4], f"Row {i} session_id mismatch"
        assert int(db_row[5]) == expected[5], f"Row {i} ua_distance mismatch"
    conn.close()
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if run_tests 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
