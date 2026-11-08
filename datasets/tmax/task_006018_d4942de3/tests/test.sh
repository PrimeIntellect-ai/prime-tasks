#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import sqlite3
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/backup_analyzer')
DB = Path('/home/user/backups.db')
SCHEMA = Path('/home/user/schema.json')
REPORT = Path('/home/user/report.json')

NORMAL_SCHEMA = {
    '$schema': 'http://json-schema.org/draft-07/schema#',
    'type': 'array',
    'items': {
        'type': 'object',
        'properties': {
            'shard_id': {'type': 'string'},
            'avg_duration': {'type': 'number'},
            'failure_count': {'type': 'integer'},
        },
        'required': ['shard_id', 'avg_duration', 'failure_count'],
        'additionalProperties': False,
    },
}

BASELINE_ROWS = [
    ('shard-01', '2023-10-01T00:00:00Z', 100, 'SUCCESS'),
    ('shard-01', '2023-10-02T00:00:00Z', 200, 'FAILED'),
    ('shard-01', '2023-10-03T00:00:00Z', 310, 'SUCCESS'),
    ('shard-01', '2023-10-04T00:00:00Z', 320, 'SUCCESS'),
    ('shard-01', '2023-10-05T00:00:00Z', 330, 'SUCCESS'),
    ('shard-02', '2023-10-01T00:00:00Z', 400, 'SUCCESS'),
    ('shard-02', '2023-10-02T00:00:00Z', 400, 'SUCCESS'),
    ('shard-02', '2023-10-03T00:00:00Z', 400, 'SUCCESS'),
    ('shard-02', '2023-10-04T00:00:00Z', 400, 'SUCCESS'),
    ('shard-03', '2023-10-01T00:00:00Z', 100, 'SUCCESS'),
    ('shard-03', '2023-10-02T00:00:00Z', 100, 'FAILED'),
    ('shard-03', '2023-10-03T00:00:00Z', 100, 'FAILED'),
    ('shard-03', '2023-10-04T00:00:00Z', 100, 'SUCCESS'),
    ('shard-03', '2023-10-05T00:00:00Z', 100, 'SUCCESS'),
]

DYNAMIC_ROWS = [
    ('zone-alpha', '2025-01-04T00:00:00Z', 307, 'SUCCESS'),
    ('zone-alpha', '2025-01-01T00:00:00Z', 1000, 'SUCCESS'),
    ('zone-alpha', '2025-01-03T00:00:00Z', 302, 'SUCCESS'),
    ('zone-alpha', '2025-01-02T00:00:00Z', 301, 'SUCCESS'),
    ('zone-alpha', '2025-01-05T00:00:00Z', 8, 'FAILED'),
    ('zone-alpha', '2025-01-06T00:00:00Z', 9, 'FAILED'),
    ('zone-beta', '2025-02-01T00:00:00Z', 900, 'SUCCESS'),
    ('zone-beta', '2025-02-02T00:00:00Z', 800, 'SUCCESS'),
    ('zone-beta', '2025-02-03T00:00:00Z', 700, 'SUCCESS'),
    ('zone-gamma', '2025-03-01T00:00:00Z', 300, 'SUCCESS'),
    ('zone-gamma', '2025-03-02T00:00:00Z', 300, 'SUCCESS'),
    ('zone-gamma', '2025-03-03T00:00:00Z', 300, 'SUCCESS'),
    ('zone-gamma', '2025-03-04T00:00:00Z', 1, 'FAILED'),
    ('zone-delta', '2025-04-01T00:00:00Z', 500, 'SUCCESS'),
    ('zone-delta', '2025-04-02T00:00:00Z', 700, 'SUCCESS'),
    ('zone-delta', '2025-04-03T00:00:00Z', 1, 'FAILED'),
    ('zone-low', '2025-05-01T00:00:00Z', 10, 'SUCCESS'),
    ('zone-low', '2025-05-02T00:00:00Z', 20, 'SUCCESS'),
    ('zone-low', '2025-05-03T00:00:00Z', 30, 'SUCCESS'),
    ('zone-low', '2025-05-04T00:00:00Z', 1, 'FAILED'),
]


def create_database(rows):
    if DB.exists():
        DB.unlink()
    conn = sqlite3.connect(DB)
    conn.execute('''CREATE TABLE backup_logs (
        id INTEGER PRIMARY KEY,
        shard_id TEXT,
        backup_date TEXT,
        duration_seconds INTEGER,
        status TEXT
    )''')
    conn.executemany(
        'INSERT INTO backup_logs (shard_id, backup_date, duration_seconds, status) VALUES (?, ?, ?, ?)',
        rows,
    )
    conn.commit()
    conn.close()


def write_schema(value):
    SCHEMA.write_text(json.dumps(value), encoding='utf-8')


def run_program(expect_success=True):
    if REPORT.exists():
        REPORT.unlink()
    result = subprocess.run(
        ['cargo', 'run', '--offline', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
        env={**os.environ, 'CARGO_NET_OFFLINE': 'true'},
    )
    if expect_success:
        assert result.returncode == 0, f'Rust program failed:\nstdout={result.stdout}\nstderr={result.stderr}'
    return result


def assert_index_exists_and_correct():
    assert os.path.isfile(DB), f'Database file missing: {DB}'
    conn = sqlite3.connect(DB)
    cursor = conn.cursor()
    cursor.execute("PRAGMA index_info('idx_shard_status_date');")
    index_info = cursor.fetchall()
    assert len(index_info) > 0, "Index 'idx_shard_status_date' does not exist in backups.db"
    columns = [row[2] for row in index_info]
    expected_columns = ['shard_id', 'status', 'backup_date']
    assert columns == expected_columns, f'Index columns are incorrect. Expected {expected_columns}, got {columns}'
    conn.close()


def load_report():
    assert os.path.isfile(REPORT), f'Report file missing: {REPORT}'
    try:
        with REPORT.open('r', encoding='utf-8') as f:
            report_data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{REPORT} is not valid JSON: {exc}')
    assert isinstance(report_data, list), 'Report JSON must be an array.'
    return report_data


def derive_expected(rows):
    shards = {}
    for shard_id, backup_date, duration, status in rows:
        shard = shards.setdefault(shard_id, {'success': [], 'failures': 0})
        if status == 'SUCCESS':
            shard['success'].append((backup_date, duration))
        elif status == 'FAILED':
            shard['failures'] += 1

    expected = {}
    for shard_id, values in shards.items():
        latest = sorted(values['success'], key=lambda item: item[0], reverse=True)[:3]
        if not latest:
            continue
        average = sum(duration for _, duration in latest) / len(latest)
        if average > 300.0 and values['failures'] >= 1:
            expected[shard_id] = (average, values['failures'])
    return expected


def assert_report_matches_derived(report, rows):
    expected = derive_expected(rows)
    assert len(report) == len(expected), f'Expected {len(expected)} records, got {len(report)}: {report}'
    seen = set()
    for record in report:
        assert isinstance(record, dict)
        assert set(record) == {'shard_id', 'avg_duration', 'failure_count'}
        assert isinstance(record['shard_id'], str)
        assert isinstance(record['avg_duration'], (int, float)) and not isinstance(record['avg_duration'], bool)
        assert isinstance(record['failure_count'], int) and not isinstance(record['failure_count'], bool)
        shard_id = record['shard_id']
        assert shard_id in expected, f'Unexpected shard in report: {shard_id}'
        assert shard_id not in seen, f'Duplicate shard in report: {shard_id}'
        seen.add(shard_id)
        expected_avg, expected_failures = expected[shard_id]
        assert math.isclose(float(record['avg_duration']), expected_avg, rel_tol=1e-9, abs_tol=1e-9)
        assert record['failure_count'] == expected_failures


def test_rust_project_and_analytical_query_exist():
    assert PROJECT.is_dir(), f'Rust project directory missing: {PROJECT}'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing'
    rust_files = list(PROJECT.rglob('*.rs'))
    assert rust_files, 'No Rust source files found in backup_analyzer'
    source = '\n'.join(path.read_text(encoding='utf-8', errors='ignore') for path in rust_files).lower()
    assert re.search(r'\bover\s*\(', source), 'The Rust source does not contain a SQL window function'
    assert re.search(r'\bpartition\s+by\b', source), 'The analytical SQL does not partition its window by shard'
    assert 'backup_date' in source and 'duration_seconds' in source, 'The analytical query is missing required backup fields'


def test_original_database_result_and_index_are_produced_by_execution():
    create_database(BASELINE_ROWS)
    write_schema(NORMAL_SCHEMA)
    run_program()
    assert_index_exists_and_correct()
    report_data = load_report()

    assert len(report_data) == 1, f'Expected exactly 1 result in report.json, got {len(report_data)}'
    record = report_data[0]
    assert record.get('shard_id') == 'shard-01', f"Expected shard_id 'shard-01', got {record.get('shard_id')}"
    assert record.get('avg_duration') == 320.0, f"Expected avg_duration 320.0, got {record.get('avg_duration')}"
    assert record.get('failure_count') == 1, f"Expected failure_count 1, got {record.get('failure_count')}"


def test_program_handles_derived_unseen_data():
    create_database(DYNAMIC_ROWS)
    write_schema(NORMAL_SCHEMA)
    run_program()
    assert_index_exists_and_correct()
    assert_report_matches_derived(load_report(), DYNAMIC_ROWS)


def test_program_honors_json_schema_before_writing():
    create_database(DYNAMIC_ROWS)
    write_schema({'$schema': 'http://json-schema.org/draft-07/schema#', 'not': {}})
    run_program(expect_success=False)
    assert not REPORT.exists(), 'Program wrote report.json even though the supplied JSON schema rejects every instance'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
