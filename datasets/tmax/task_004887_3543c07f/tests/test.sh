#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import json
import os
import random
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid
from collections import defaultdict
from decimal import Decimal

import pytest

HOME = '/home/user'
SOURCE = f'{HOME}/process_telemetry.cpp'
MERGED = f'{HOME}/merged_output.csv'
LOG = f'{HOME}/processing_log.json'
DB = f'{HOME}/telemetry.db'
A_CSV = f'{HOME}/telemetry_a.csv'
B_CSV = f'{HOME}/telemetry_b.csv'

FIXED_EXPECTED = {
    (1698849001, 'm1'): (46.0, 61.0),
    (1698849002, 'm2'): (50.0, 0.0),
    (1698849003, 'm1'): (47.0, 0.0),
    (1698849003, 'm3'): (0.0, 80.0),
}


def read_merged(path):
    assert os.path.isfile(path), f'Merged CSV file {path} is missing.'
    result = {}
    with open(path, newline='') as f:
        rows = list(csv.reader(f))
    for line_no, row in enumerate(rows, 1):
        assert len(row) == 4, f'Line {line_no} of merged_output.csv does not have four columns.'
        assert re.fullmatch(r'-?\d+', row[0]), f'Invalid epoch_sec on line {line_no}: {row[0]!r}'
        assert row[1] != '', f'Empty machine_id on line {line_no}.'
        assert re.fullmatch(r'-?\d+\.\d', row[2]), f'CPU average on line {line_no} is not formatted to one decimal place.'
        assert re.fullmatch(r'-?\d+\.\d', row[3]), f'RAM average on line {line_no} is not formatted to one decimal place.'
        key = (int(row[0]), row[1])
        assert key not in result, f'Duplicate merged group {key}.'
        result[key] = (float(row[2]), float(row[3]))
    return result


def assert_rows(actual, expected):
    assert set(actual) == set(expected), f'Wrong merged groups: expected {set(expected)}, got {set(actual)}'
    for key, values in expected.items():
        got = actual[key]
        assert abs(got[0] - values[0]) < 0.01, f'Wrong avg_cpu_temp for {key}: expected {values[0]}, got {got[0]}'
        assert abs(got[1] - values[1]) < 0.01, f'Wrong avg_ram_usage for {key}: expected {values[1]}, got {got[1]}'


def test_01_json_log_exists_and_valid():
    assert os.path.isfile(LOG), f'JSON log file {LOG} is missing.'
    with open(LOG) as f:
        try:
            log_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('processing_log.json is not valid JSON.')

    assert 'valid_rows_a' in log_data, "Key 'valid_rows_a' missing in JSON log."
    assert 'invalid_rows_a' in log_data, "Key 'invalid_rows_a' missing in JSON log."
    assert 'rows_b' in log_data, "Key 'rows_b' missing in JSON log."
    assert 'merged_groups' in log_data, "Key 'merged_groups' missing in JSON log."
    assert log_data['valid_rows_a'] == 4, f"Expected 4 valid_rows_a, got {log_data['valid_rows_a']}"
    assert log_data['invalid_rows_a'] == 2, f"Expected 2 invalid_rows_a, got {log_data['invalid_rows_a']}"
    assert log_data['rows_b'] == 3, f"Expected 3 rows_b, got {log_data['rows_b']}"
    assert log_data['merged_groups'] == 4, f"Expected 4 merged_groups, got {log_data['merged_groups']}"
    assert set(log_data) == {'valid_rows_a', 'invalid_rows_a', 'rows_b', 'merged_groups'}, 'JSON log contains keys other than the four required keys.'


def test_02_merged_output_for_original_fixture():
    assert_rows(read_merged(MERGED), FIXED_EXPECTED)


def test_03_database_exists_and_has_data():
    assert os.path.isfile(DB), f'Database file {DB} is missing.'
    conn = sqlite3.connect(DB)
    cursor = conn.cursor()
    try:
        cursor.execute('PRAGMA table_info(merged_telemetry);')
        schema = cursor.fetchall()
        assert [(r[1], r[2].upper()) for r in schema] == [
            ('epoch_sec', 'INTEGER'),
            ('machine_id', 'TEXT'),
            ('avg_cpu_temp', 'REAL'),
            ('avg_ram_usage', 'REAL'),
        ], f'Incorrect merged_telemetry schema: {schema}'

        cursor.execute('SELECT count(*) FROM merged_telemetry;')
        count = cursor.fetchone()[0]
        assert count == 4, f'Expected 4 rows in merged_telemetry, got {count}'

        cursor.execute("SELECT avg_cpu_temp, avg_ram_usage FROM merged_telemetry WHERE epoch_sec=1698849001 AND machine_id='m1';")
        row1 = cursor.fetchone()
        assert row1 is not None, "Row for epoch_sec=1698849001, machine_id='m1' is missing."
        assert abs(row1[0] - 46.0) < 0.01, f'Expected avg_cpu_temp 46.0, got {row1[0]}'
        assert abs(row1[1] - 61.0) < 0.01, f'Expected avg_ram_usage 61.0, got {row1[1]}'

        cursor.execute("SELECT avg_cpu_temp, avg_ram_usage FROM merged_telemetry WHERE epoch_sec=1698849002 AND machine_id='m2';")
        row2 = cursor.fetchone()
        assert row2 is not None, "Row for epoch_sec=1698849002, machine_id='m2' is missing."
        assert abs(row2[0] - 50.0) < 0.01, f'Expected avg_cpu_temp 50.0, got {row2[0]}'
        assert abs(row2[1] - 0.0) < 0.01, f'Expected avg_ram_usage 0.0, got {row2[1]}'

        cursor.execute("SELECT avg_cpu_temp, avg_ram_usage FROM merged_telemetry WHERE epoch_sec=1698849003 AND machine_id='m1';")
        row3 = cursor.fetchone()
        assert row3 is not None, "Row for epoch_sec=1698849003, machine_id='m1' is missing."
        assert abs(row3[0] - 47.0) < 0.01, f'Expected avg_cpu_temp 47.0, got {row3[0]}'
        assert abs(row3[1] - 0.0) < 0.01, f'Expected avg_ram_usage 0.0, got {row3[1]}'

        cursor.execute("SELECT avg_cpu_temp, avg_ram_usage FROM merged_telemetry WHERE epoch_sec=1698849003 AND machine_id='m3';")
        row4 = cursor.fetchone()
        assert row4 is not None, "Row for epoch_sec=1698849003, machine_id='m3' is missing."
        assert abs(row4[0] - 0.0) < 0.01, f'Expected avg_cpu_temp 0.0, got {row4[0]}'
        assert abs(row4[1] - 80.0) < 0.01, f'Expected avg_ram_usage 80.0, got {row4[1]}'

        cursor.execute('SELECT epoch_sec, machine_id, avg_cpu_temp, avg_ram_usage FROM merged_telemetry;')
        db_rows = {(int(e), m): (float(c), float(r)) for e, m, c, r in cursor.fetchall()}
        assert_rows(db_rows, FIXED_EXPECTED)
        assert_rows(db_rows, read_merged(MERGED))
    except sqlite3.OperationalError as e:
        pytest.fail(f"Database query failed: {e}. Ensure table 'merged_telemetry' exists with correct schema.")
    finally:
        conn.close()


def test_04_output_is_sqlite_cli_bulk_importable(tmp_path):
    imported_db = tmp_path / 'bulk_import.db'
    commands = (
        'CREATE TABLE merged_telemetry '
        '(epoch_sec INTEGER, machine_id TEXT, avg_cpu_temp REAL, avg_ram_usage REAL);\n'
        '.mode csv\n'
        f'.import {MERGED} merged_telemetry\n'
    )
    proc = subprocess.run(['sqlite3', str(imported_db)], input=commands, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    assert proc.returncode == 0, f'sqlite3 bulk import failed: {proc.stderr}'
    conn = sqlite3.connect(imported_db)
    try:
        rows = conn.execute('SELECT epoch_sec, machine_id, avg_cpu_temp, avg_ram_usage FROM merged_telemetry').fetchall()
    finally:
        conn.close()
    imported = {(int(e), m): (float(c), float(r)) for e, m, c, r in rows}
    assert_rows(imported, FIXED_EXPECTED)


def strict_iso_epoch(value):
    match = re.fullmatch(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.\d+)?Z', value)
    if not match:
        raise ValueError('malformed ISO timestamp')
    dt = datetime.datetime.strptime(match.group(1), '%Y-%m-%dT%H:%M:%S')
    dt = dt.replace(tzinfo=datetime.timezone.utc)
    return int(dt.timestamp())


def derive_expected(a_text, b_text):
    cpu = defaultdict(list)
    ram = defaultdict(list)
    valid_a = invalid_a = rows_b = 0
    for row in list(csv.reader(a_text.splitlines()))[1:]:
        try:
            epoch = strict_iso_epoch(row[0])
        except (ValueError, OverflowError):
            invalid_a += 1
            continue
        valid_a += 1
        cpu[(epoch, row[1])].append(Decimal(row[2]))
    for row in list(csv.reader(b_text.splitlines()))[1:]:
        rows_b += 1
        key = (int(row[0]) // 1000, row[1])
        ram[key].append(Decimal(row[2]))
    expected = {}
    for key in set(cpu) | set(ram):
        c = sum(cpu[key], Decimal(0)) / len(cpu[key]) if cpu[key] else Decimal('0')
        r = sum(ram[key], Decimal(0)) / len(ram[key]) if ram[key] else Decimal('0')
        expected[key] = (float(c), float(r))
    return expected, {
        'valid_rows_a': valid_a,
        'invalid_rows_a': invalid_a,
        'rows_b': rows_b,
        'merged_groups': len(expected),
    }


def test_05_compile_and_execute_cpp_on_unseen_fixture(tmp_path):
    assert os.path.exists(SOURCE), f'C++ source file {SOURCE} is missing.'
    mode = os.lstat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f'{SOURCE} must be a regular C++ source file.'
    assert os.path.getsize(SOURCE) > 0, f'{SOURCE} is empty.'

    executable = tmp_path / 'process_telemetry'
    compiled = subprocess.run(
        ['g++', '-std=c++17', '-O2', SOURCE, '-o', str(executable)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compiled.returncode == 0, f'process_telemetry.cpp does not compile with C++17:\n{compiled.stderr}'

    rng = random.SystemRandom()
    base = rng.randrange(1700000000, 1800000000)
    ids = [f'v_{uuid.uuid4().hex}' for _ in range(4)]

    def iso(sec, fraction='000'):
        stem = datetime.datetime.fromtimestamp(sec, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S')
        return f'{stem}.{fraction}Z'

    t = rng.randrange(300, 700)
    r = rng.randrange(300, 700)
    a_text = '\n'.join([
        'ts_iso,machine_id,cpu_temp',
        f'{iso(base, "123")},{ids[0]},{t / 10:.1f}',
        f'{iso(base, "999")},{ids[0]},{(t + 2) / 10:.1f}',
        f'{iso(base + 1, "001")},{ids[1]},{(t + 31) / 10:.1f}',
        f'{iso(base + 2, "875")},{ids[0]},{(t + 47) / 10:.1f}',
        f'{iso(base + 4, "500")},{ids[3]},{(t + 63) / 10:.1f}',
        f'{iso(base + 5, "250").replace("T", " ")},{ids[0]},999.0',
        f'{iso(base + 6, "300")[:-1]},{ids[1]},999.0',
        f'not-a-timestamp,{ids[2]},999.0',
    ]) + '\n'
    b_text = '\n'.join([
        'ts_unix_ms,machine_id,ram_usage',
        f'{base * 1000 + 5},{ids[0]},{r / 10:.1f}',
        f'{base * 1000 + 995},{ids[0]},{(r + 2) / 10:.1f}',
        f'{(base + 1) * 1000 + 444},{ids[1]},{(r + 20) / 10:.1f}',
        f'{(base + 3) * 1000 + 1},{ids[2]},{(r + 40) / 10:.1f}',
        f'{(base + 3) * 1000 + 999},{ids[2]},{(r + 44) / 10:.1f}',
        f'{(base + 4) * 1000 + 500},{ids[3]},{(r + 60) / 10:.1f}',
    ]) + '\n'
    expected_rows, expected_log = derive_expected(a_text, b_text)

    paths = [A_CSV, B_CSV, MERGED, LOG]
    backups = {path: open(path, 'rb').read() if os.path.exists(path) else None for path in paths}
    try:
        with open(A_CSV, 'w') as f:
            f.write(a_text)
        with open(B_CSV, 'w') as f:
            f.write(b_text)
        for path in (MERGED, LOG):
            if os.path.lexists(path):
                os.remove(path)

        run = subprocess.run([str(executable)], cwd=HOME, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        assert run.returncode == 0, f'Compiled program failed on an unseen fixture:\n{run.stderr}'
        assert_rows(read_merged(MERGED), expected_rows)
        assert os.path.isfile(LOG), 'The compiled program did not create processing_log.json.'
        with open(LOG) as f:
            actual_log = json.load(f)
        assert set(actual_log) == set(expected_log), 'Dynamic processing log does not contain exactly the required keys.'
        for key, value in expected_log.items():
            assert type(actual_log[key]) is int, f'{key} must be an integer.'
            assert actual_log[key] == value, f'Wrong dynamic log value for {key}: expected {value}, got {actual_log[key]}'
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.lexists(path):
                    os.remove(path)
            else:
                with open(path, 'wb') as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
