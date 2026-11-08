#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

DB_PATH = '/home/user/microservices.db'
REPORT_PATH = '/home/user/optimized_report.json'
PIPELINE_DIR = '/home/user/pipeline'
SOURCE_PATH = os.path.join(PIPELINE_DIR, 'analyze.go')
GOMOD_PATH = os.path.join(PIPELINE_DIR, 'go.mod')
BINARY_PATH = '/tmp/analyze_submission'


def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()


def assert_regular_file(path):
    assert os.path.exists(path), f'Required file {path} is missing.'
    assert not os.path.islink(path), f'{path} must be a regular file, not a symlink.'
    assert stat.S_ISREG(os.stat(path).st_mode), f'{path} must be a regular file.'


def run_program():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        [BINARY_PATH],
        cwd=PIPELINE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        'The submitted Go program failed when executed.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(REPORT_PATH), f'The report file {REPORT_PATH} is missing.'

    with open(REPORT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {REPORT_PATH} does not contain valid JSON.')


def assert_original_report(data):
    # Preserve the original verifier's report assertions.
    assert 'top_service' in data, "Missing 'top_service' key in the report."
    assert 'in_degree' in data, "Missing 'in_degree' key in the report."
    assert 'avg_latency' in data, "Missing 'avg_latency' key in the report."
    assert data['top_service'] == 'Auth', f"Expected top_service to be 'Auth', got '{data['top_service']}'"
    assert data['in_degree'] == 3, f"Expected in_degree to be 3, got {data['in_degree']}"
    assert float(data['avg_latency']) == 200.0, f"Expected avg_latency to be 200.0, got {data['avg_latency']}"


def create_database(services, calls):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript('''
            CREATE TABLE services (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL
            );
            CREATE TABLE calls (
                source_id INTEGER,
                target_id INTEGER,
                call_count INTEGER,
                latency_ms REAL,
                FOREIGN KEY(source_id) REFERENCES services(id),
                FOREIGN KEY(target_id) REFERENCES services(id)
            );
        ''')
        conn.executemany('INSERT INTO services(id, name) VALUES (?, ?)', services)
        conn.executemany(
            'INSERT INTO calls(source_id, target_id, call_count, latency_ms) VALUES (?, ?, ?, ?)',
            calls,
        )
        conn.commit()
    finally:
        conn.close()


def derive_expected(services, calls):
    names = dict(services)
    by_source = {}
    for source_id, target_id, call_count, latency_ms in calls:
        by_source.setdefault(source_id, []).append((target_id, float(latency_ms)))

    selected = []
    for edges in by_source.values():
        selected.extend(sorted(edges, key=lambda edge: edge[1], reverse=True)[:2])

    incoming = {}
    for target_id, latency in selected:
        incoming.setdefault(target_id, []).append(latency)

    assert incoming
    winner = max(
        incoming,
        key=lambda target_id: (
            len(incoming[target_id]),
            sum(incoming[target_id]) / len(incoming[target_id]),
        ),
    )
    latencies = incoming[winner]
    return names[winner], len(latencies), sum(latencies) / len(latencies)


def assert_dynamic_report(data, expected):
    assert 'top_service' in data, "Missing 'top_service' key in the report."
    assert 'in_degree' in data, "Missing 'in_degree' key in the report."
    assert 'avg_latency' in data, "Missing 'avg_latency' key in the report."
    expected_name, expected_degree, expected_average = expected
    assert data['top_service'] == expected_name
    assert data['in_degree'] == expected_degree
    assert abs(float(data['avg_latency']) - expected_average) < 1e-9


def test_pipeline_source_and_execution():
    assert_regular_file(SOURCE_PATH)
    assert_regular_file(GOMOD_PATH)
    assert_regular_file(DB_PATH)

    with open(SOURCE_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    with open(GOMOD_PATH, 'r', encoding='utf-8') as f:
        gomod = f.read()

    assert re.search(r'(?m)^\s*package\s+main\b', source), 'analyze.go must be a Go main package.'
    assert re.search(r'\bfunc\s+main\s*\(', source), 'analyze.go must define the executable main function.'
    assert 'database/sql' in source, 'analyze.go must use Go database/sql.'
    assert 'github.com/mattn/go-sqlite3' in source, 'analyze.go must use github.com/mattn/go-sqlite3.'
    assert re.search(r'(?is)\b(?:row_number|rank|dense_rank)\s*\(\s*\)\s*over\s*\(', source), (
        'analyze.go must contain a SQL window function used to rank outgoing calls.'
    )
    assert re.search(r'(?m)^\s*module\s+\S+', gomod), 'A Go module must be initialized in /home/user/pipeline.'
    assert 'github.com/mattn/go-sqlite3' in gomod, 'go.mod must declare github.com/mattn/go-sqlite3.'

    backup_dir = tempfile.mkdtemp(prefix='microservices_backup_')
    backup_path = os.path.join(backup_dir, 'microservices.db')
    shutil.copy2(DB_PATH, backup_path)
    original_hash = file_hash(backup_path)

    try:
        build = subprocess.run(
            ['go', 'build', '-o', BINARY_PATH, '.'],
            cwd=PIPELINE_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert build.returncode == 0, (
            'The Go pipeline could not be built.\n'
            f'stdout:\n{build.stdout}\nstderr:\n{build.stderr}'
        )

        # Execute against the original database and retain all original checks.
        original_data = run_program()
        assert_original_report(original_data)
        assert file_hash(DB_PATH) == original_hash, 'The Go program modified the original database.'

        token = secrets.token_hex(8)
        cases = [
            (
                [(101, f'Alpha-{token}'), (203, f'Beta-{token}'), (307, f'Gamma-{token}'),
                 (409, f'Delta-{token}'), (503, f'Epsilon-{token}')],
                [(101, 203, 1, 900.0), (101, 307, 1, 800.0), (101, 409, 1, 700.0),
                 (203, 307, 1, 100.0), (203, 409, 1, 90.0), (203, 503, 1, 80.0),
                 (307, 409, 1, 600.0), (307, 203, 1, 500.0), (307, 503, 1, 400.0)],
            ),
            (
                [(11, f'One-{token}'), (22, f'Two-{token}'), (33, f'Three-{token}'),
                 (44, f'Four-{token}'), (55, f'Five-{token}')],
                [(11, 22, 5, 10.0), (11, 33, 5, 90.0), (11, 44, 5, 80.0),
                 (22, 44, 5, 70.0), (22, 55, 5, 60.0), (22, 33, 5, 1.0),
                 (33, 55, 5, 50.0), (33, 22, 5, 40.0), (33, 44, 5, 30.0)],
            ),
        ]

        for services, calls in cases:
            create_database(services, calls)
            challenge_hash = file_hash(DB_PATH)
            data = run_program()
            assert_dynamic_report(data, derive_expected(services, calls))
            assert file_hash(DB_PATH) == challenge_hash, 'The Go program modified the database.'
    finally:
        shutil.copy2(backup_path, DB_PATH)
        shutil.rmtree(backup_dir, ignore_errors=True)

    # Leave the requested report generated from the restored original database.
    assert file_hash(DB_PATH) == original_hash
    final_data = run_program()
    assert_original_report(final_data)
    assert file_hash(DB_PATH) == original_hash, 'The Go program modified the original database.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
