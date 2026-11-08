#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import sqlite3
import stat
import subprocess
from collections import defaultdict
from pathlib import Path

import pytest

ROOT = Path('/home/user')
DATA = ROOT / 'data'
OUTPUT = DATA / 'final_output.jsonl'


def read_jsonl(path):
    assert path.is_file(), f'{path} is missing. Did the ETL pipeline run and produce the file?'
    content = path.read_text().strip()
    assert content, f'{path} is empty.'
    result = []
    for i, line in enumerate(content.splitlines(), 1):
        try:
            result.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f'Line {i} is not valid JSON: {line}')
    return result


def assert_output(actual, expected):
    assert len(actual) == len(expected), f'Expected {len(expected)} lines in JSONL, got {len(actual)}'
    required = ['id', 'city', 'ts', 'val', 'rolling_avg']
    for i, (data, exp) in enumerate(zip(actual, expected), 1):
        for key in required:
            assert key in data, f"Line {i} is missing key '{key}'"
        assert data['id'] == exp['id'], f"Line {i}: expected id {exp['id']}, got {data['id']}"
        assert data['city'] == exp['city'], f"Line {i}: expected city '{exp['city']}', got '{data['city']}'"
        assert data['ts'] == exp['ts'], f"Line {i}: expected ts '{exp['ts']}', got '{data['ts']}'"
        assert math.isclose(data['val'], exp['val'], rel_tol=1e-5, abs_tol=1e-8), \
            f"Line {i}: expected val {exp['val']}, got {data['val']}"
        assert math.isclose(data['rolling_avg'], exp['rolling_avg'], abs_tol=0.01), \
            f"Line {i}: expected rolling_avg {exp['rolling_avg']}, got {data['rolling_avg']}"


def expected_from(meta, stream1, stream2):
    cities = {int(row['id']): row['city'] for row in meta}
    grouped = defaultdict(list)
    for row in stream1 + stream2:
        grouped[int(row['id'])].append((row['ts'], float(row['val'])))

    result = []
    for sensor_id in sorted(grouped):
        rows = sorted(grouped[sensor_id], key=lambda row: row[0])
        for index, (ts, val) in enumerate(rows):
            window = [v for _, v in rows[max(0, index - 2):index + 1]]
            result.append({
                'id': sensor_id,
                'city': cities[sensor_id],
                'ts': ts,
                'val': val,
                'rolling_avg': round(sum(window) / len(window), 2),
            })
    return result


def write_csv(path, fieldnames, rows):
    with path.open('w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def test_01_original_final_state_assertions():
    assert (ROOT / 'Makefile').is_file(), 'Makefile is missing in /home/user/'
    assert (DATA / 'warehouse.db').is_file(), 'warehouse.db is missing in /home/user/data/'

    expected = [
        {'id': 1, 'city': 'NewYork', 'ts': '2023-01-01', 'val': 10.0, 'rolling_avg': 10.00},
        {'id': 1, 'city': 'NewYork', 'ts': '2023-01-02', 'val': 12.0, 'rolling_avg': 11.00},
        {'id': 1, 'city': 'NewYork', 'ts': '2023-01-03', 'val': 14.0, 'rolling_avg': 12.00},
        {'id': 1, 'city': 'NewYork', 'ts': '2023-01-04', 'val': 16.0, 'rolling_avg': 14.00},
        {'id': 1, 'city': 'NewYork', 'ts': '2023-01-05', 'val': 10.0, 'rolling_avg': 13.33},
        {'id': 2, 'city': 'London', 'ts': '2023-01-01', 'val': 5.0, 'rolling_avg': 5.00},
        {'id': 2, 'city': 'London', 'ts': '2023-01-02', 'val': 6.0, 'rolling_avg': 5.50},
        {'id': 2, 'city': 'London', 'ts': '2023-01-03', 'val': 7.0, 'rolling_avg': 6.00},
        {'id': 2, 'city': 'London', 'ts': '2023-01-04', 'val': 8.0, 'rolling_avg': 7.00},
        {'id': 2, 'city': 'London', 'ts': '2023-01-06', 'val': 11.0, 'rolling_avg': 8.67},
    ]
    assert_output(read_jsonl(OUTPUT), expected)


def test_02_execute_dag_on_unseen_inputs_and_validate_artifacts():
    meta = [
        {'id': '42', 'city': 'Oslo'},
        {'id': '7', 'city': 'Tokyo'},
        {'id': '105', 'city': 'Lima'},
    ]
    stream1 = [
        {'ts': '2024-02-04', 'id': '7', 'val': '8.4'},
        {'ts': '2024-03-01', 'id': '42', 'val': '3.25'},
        {'ts': '2024-01-03', 'id': '105', 'val': '-2.0'},
        {'ts': '2024-02-01', 'id': '7', 'val': '1.2'},
        {'ts': '2024-03-05', 'id': '42', 'val': '12.5'},
    ]
    stream2 = [
        {'ts': '2024-03-03', 'id': '42', 'val': '6.75'},
        {'ts': '2024-02-02', 'id': '7', 'val': '2.6'},
        {'ts': '2024-01-01', 'id': '105', 'val': '9.0'},
        {'ts': '2024-02-03', 'id': '7', 'val': '5.0'},
        {'ts': '2024-03-07', 'id': '42', 'val': '-1.0'},
        {'ts': '2024-01-05', 'id': '105', 'val': '4.6'},
    ]

    write_csv(DATA / 'meta.csv', ['id', 'city'], meta)
    write_csv(DATA / 'stream1.csv', ['ts', 'id', 'val'], stream1)
    write_csv(DATA / 'stream2.csv', ['ts', 'id', 'val'], stream2)

    db = DATA / 'warehouse.db'
    if db.exists():
        db.unlink()
    if OUTPUT.exists():
        OUTPUT.unlink()

    proc = subprocess.run(
        ['make', '-B', '--trace', 'all'], cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300
    )
    assert proc.returncode == 0, f'make all failed:\n{proc.stdout}'

    trace_positions = []
    for target in ('db-init', 'db-import', 'etl-process'):
        match = re.search(r"target ['`]" + re.escape(target) + r"['`]", proc.stdout)
        assert match, f"make all did not execute the required target '{target}'. Trace:\n{proc.stdout}"
        trace_positions.append(match.start())
    assert trace_positions == sorted(trace_positions), \
        f'Required targets did not run in db-init, db-import, etl-process order:\n{proc.stdout}'
    assert re.search(r'(^|[ /])(cargo|rustc)([ /]|$)', proc.stdout, re.MULTILINE), \
        f'etl-process did not visibly compile or run Rust code:\n{proc.stdout}'

    assert db.is_file(), 'make all did not create warehouse.db'
    assert OUTPUT.is_file(), 'make all did not create final_output.jsonl'

    con = sqlite3.connect(db)
    try:
        for table, columns in (
            ('meta', ['id', 'city']),
            ('stream1', ['ts', 'id', 'val']),
            ('stream2', ['ts', 'id', 'val']),
        ):
            found = [row[1] for row in con.execute(f'PRAGMA table_info({table})')]
            assert found == columns, f'Table {table} has columns {found}, expected {columns}'

        db_meta = {(int(i), city) for i, city in con.execute('SELECT id, city FROM meta')}
        assert db_meta == {(int(r['id']), r['city']) for r in meta}, 'meta.csv was not correctly imported'
        for table, rows in (('stream1', stream1), ('stream2', stream2)):
            found = {(ts, int(i), float(v)) for ts, i, v in con.execute(f'SELECT ts, id, val FROM {table}')}
            wanted = {(r['ts'], int(r['id']), float(r['val'])) for r in rows}
            assert found == wanted, f'{table}.csv was not correctly imported into SQLite'
    finally:
        con.close()

    assert_output(read_jsonl(OUTPUT), expected_from(meta, stream1, stream2))

    project = ROOT / 'etl_pipeline'
    manifest = project / 'Cargo.toml'
    source = project / 'src' / 'main.rs'
    assert manifest.is_file(), 'Rust project is missing Cargo.toml'
    assert source.is_file(), 'Rust project is missing src/main.rs'
    assert re.search(r'\bfn\s+main\s*\(', source.read_text()), 'src/main.rs has no Rust main function'

    metadata_proc = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1', '--manifest-path', str(manifest)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert metadata_proc.returncode == 0, f'Invalid Cargo project: {metadata_proc.stderr}'
    metadata = json.loads(metadata_proc.stdout)
    bin_names = {
        target['name'] for package in metadata['packages'] for target in package['targets']
        if 'bin' in target.get('kind', [])
    }
    assert bin_names, 'Cargo project defines no executable binary target'
    target_dir = Path(metadata['target_directory'])
    binaries = []
    if target_dir.exists():
        for path in target_dir.rglob('*'):
            if path.is_file() and path.name in bin_names and (path.stat().st_mode & stat.S_IXUSR):
                try:
                    if path.read_bytes()[:4] == b'\x7fELF':
                        binaries.append(path)
                except OSError:
                    pass
    assert binaries, 'No compiled Rust executable was produced by the pipeline'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
