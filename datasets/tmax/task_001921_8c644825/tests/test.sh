#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import hashlib
import math
import os
import re
import secrets
import shutil
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import pandas as pd
import pytest

PIPELINE = Path('/home/user/pipeline.py')
RAW_DIR = Path('/home/user/raw_data')
CLEAN_DIR = Path('/home/user/clean_data')
LOG_PATH = Path('/home/user/pipeline.log')
FILES = [f'hospital_{i}.csv' for i in range(1, 5)]


def run_pipeline():
    CLEAN_DIR.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        (CLEAN_DIR / name.replace('.csv', '.parquet')).unlink(missing_ok=True)
    LOG_PATH.unlink(missing_ok=True)
    try:
        result = subprocess.run(
            ['python3', str(PIPELINE)], cwd='/home/user', text=True,
            capture_output=True, timeout=120
        )
    except subprocess.TimeoutExpired:
        pytest.fail('pipeline.py did not finish within 120 seconds')
    assert result.returncode == 0, (
        f'pipeline.py failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def expected_records(csv_path):
    result = []
    with open(csv_path, newline='') as f:
        for row in csv.DictReader(f):
            patient_id = hashlib.sha256(row['ssn'].encode()).hexdigest()
            for column in ('HR_00:00', 'HR_06:00', 'HR_12:00', 'HR_18:00'):
                value = row[column].strip()
                if not value:
                    continue
                try:
                    heart_rate = float(value)
                except ValueError:
                    pytest.fail(f'Invalid test input heart rate: {value!r}')
                if math.isnan(heart_rate):
                    continue
                local = datetime.strptime(
                    row['record_date'] + ' ' + column[3:], '%Y-%m-%d %H:%M'
                ).replace(tzinfo=ZoneInfo(row['tz']))
                utc_timestamp = local.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
                result.append((patient_id, utc_timestamp, heart_rate))
    return sorted(result)


def actual_records(parquet_path):
    try:
        df = pd.read_parquet(parquet_path)
    except Exception as exc:
        pytest.fail(f'Unable to read {parquet_path} as Parquet: {exc}')
    assert set(df.columns) == {'patient_id', 'heart_rate', 'utc_timestamp'}, (
        f'Incorrect columns in {parquet_path}: {list(df.columns)}'
    )
    assert not df['heart_rate'].isna().any(), f'Missing heart rates remain in {parquet_path}'
    records = []
    for row in df.to_dict(orient='records'):
        assert isinstance(row['patient_id'], str)
        assert re.fullmatch(r'[0-9a-f]{64}', row['patient_id']), 'patient_id is not a SHA-256 hex digest'
        assert isinstance(row['utc_timestamp'], str), 'utc_timestamp must be an ISO8601 string'
        assert re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', row['utc_timestamp']), (
            f'Invalid UTC timestamp format: {row["utc_timestamp"]!r}'
        )
        records.append((row['patient_id'], row['utc_timestamp'], float(row['heart_rate'])))
    return sorted(records)


def assert_all_outputs_match_inputs():
    for csv_name in FILES:
        parquet_name = csv_name.replace('.csv', '.parquet')
        output = CLEAN_DIR / parquet_name
        assert output.is_file(), f'Expected output file {output} is missing.'
        assert actual_records(output) == expected_records(RAW_DIR / csv_name), (
            f'{parquet_name} does not contain the exact transformed records from {csv_name}'
        )


def inspect_pipeline_source():
    assert PIPELINE.exists(), '/home/user/pipeline.py is missing'
    assert not PIPELINE.is_symlink(), '/home/user/pipeline.py must be a real Python script'
    assert stat.S_ISREG(PIPELINE.stat().st_mode), '/home/user/pipeline.py is not a regular file'
    source = PIPELINE.read_text()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f'pipeline.py is not valid Python: {exc}')

    parallel_modules = set()
    parallel_names = set()
    logging_modules = set()
    logging_names = set()
    constructors = {'Pool', 'Process', 'ProcessPoolExecutor', 'ThreadPoolExecutor'}

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == 'multiprocessing' or item.name.startswith('concurrent.futures'):
                    parallel_modules.add(item.asname or item.name.split('.')[0])
                if item.name == 'logging':
                    logging_modules.add(item.asname or 'logging')
        elif isinstance(node, ast.ImportFrom):
            if node.module in {'multiprocessing', 'concurrent.futures'}:
                for item in node.names:
                    parallel_names.add(item.asname or item.name)
            if node.module == 'logging':
                for item in node.names:
                    logging_names.add(item.asname or item.name)

    calls = [node.func for node in ast.walk(tree) if isinstance(node, ast.Call)]
    called_names = {f.id for f in calls if isinstance(f, ast.Name)}
    called_attrs = {f.attr for f in calls if isinstance(f, ast.Attribute)}

    imported_parallel_constructor = bool(
        constructors.intersection(parallel_names) or parallel_modules
    )
    used_parallel_constructor = bool(
        constructors.intersection(called_names | called_attrs)
    )
    dispatched_work = bool({'map', 'starmap', 'imap', 'imap_unordered', 'submit', 'start'}.intersection(called_attrs))
    assert imported_parallel_constructor and used_parallel_constructor and dispatched_work, (
        'pipeline.py must actually dispatch file processing with multiprocessing or concurrent.futures'
    )

    logging_imported = bool(logging_modules or logging_names)
    logging_configured = bool({'basicConfig', 'FileHandler'}.intersection(called_names | called_attrs))
    info_logged = 'info' in called_names or 'info' in called_attrs or (
        'log' in called_attrs and any(isinstance(n, ast.Name) and n.id == 'INFO' for n in ast.walk(tree))
    )
    assert logging_imported and logging_configured and info_logged, (
        'pipeline.py must configure Python logging and emit INFO messages'
    )


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    inspect_pipeline_source()
    run_pipeline()


def test_clean_data_files_exist():
    for name in FILES:
        path = CLEAN_DIR / name.replace('.csv', '.parquet')
        assert path.is_file(), f'Expected output file {path} is missing.'


def test_parquet_columns_and_anonymization():
    path = CLEAN_DIR / 'hospital_1.parquet'
    data = pd.read_parquet(path)
    assert len(data) > 0, f'{path} is empty.'
    expected_cols = {'patient_id', 'heart_rate', 'utc_timestamp'}
    assert set(data.columns) == expected_cols
    expected_hash = hashlib.sha256('222-33-4444'.encode()).hexdigest()
    assert expected_hash in set(data['patient_id']), "SSN hashing failed or Bob Jones's records are missing."


def test_row_counts_and_nan_dropping():
    expected_counts = {
        'hospital_1.parquet': 7,
        'hospital_2.parquet': 7,
        'hospital_3.parquet': 4,
        'hospital_4.parquet': 4,
    }
    for filename, count in expected_counts.items():
        assert len(pd.read_parquet(CLEAN_DIR / filename)) == count


def test_utc_timestamp_alignment():
    data = pd.read_parquet(CLEAN_DIR / 'hospital_1.parquet')
    timestamps = list(data['utc_timestamp'])
    assert '2023-10-15T16:00:00Z' in timestamps
    for value in timestamps:
        assert isinstance(value, str) and value.endswith('Z')


def test_logging_output():
    assert LOG_PATH.is_file(), f'Log file {LOG_PATH} is missing.'
    content = LOG_PATH.read_text()
    expected = [
        'Successfully processed hospital_1.csv - 7 records generated',
        'Successfully processed hospital_2.csv - 7 records generated',
        'Successfully processed hospital_3.csv - 4 records generated',
        'Successfully processed hospital_4.csv - 4 records generated',
    ]
    for message in expected:
        assert message in content, f'Expected log entry {message!r} not found.'


def test_exact_contents_of_all_original_outputs():
    assert_all_outputs_match_inputs()


def test_z_pipeline_handles_unseen_conforming_inputs():
    backup = Path('/tmp/raw_data_verifier_backup')
    if backup.exists():
        shutil.rmtree(backup)
    shutil.copytree(RAW_DIR, backup)
    token = secrets.token_hex(8)
    zones = ['America/Los_Angeles', 'Europe/Paris', 'Asia/Kolkata', 'UTC']
    dates = ['2024-01-17', '2024-02-21', '2024-03-13', '2024-04-24']
    expected_counts = {}
    try:
        for index, filename in enumerate(FILES):
            rows = [
                ['patient_name', 'ssn', 'record_date', 'tz', 'HR_00:00', 'HR_06:00', 'HR_12:00', 'HR_18:00'],
                [f'Hidden {index}', f'{token}-{index}-A', dates[index], zones[index],
                 str(51 + index), '', str(71 + index), str(81 + index)],
                [f'Hidden Extra {index}', f'{token}-{index}-B', dates[index], zones[index],
                 '', str(61 + index), str(72 + index), ''],
            ]
            with open(RAW_DIR / filename, 'w', newline='') as f:
                csv.writer(f).writerows(rows)
            expected_counts[filename] = 5

        run_pipeline()
        assert_all_outputs_match_inputs()
        content = LOG_PATH.read_text()
        for filename, count in expected_counts.items():
            message = f'Successfully processed {filename} - {count} records generated'
            assert message in content, f'Expected dynamic log entry {message!r} not found.'
    finally:
        for path in RAW_DIR.glob('*.csv'):
            path.unlink()
        for path in backup.glob('*.csv'):
            shutil.copy2(path, RAW_DIR / path.name)
        shutil.rmtree(backup, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
