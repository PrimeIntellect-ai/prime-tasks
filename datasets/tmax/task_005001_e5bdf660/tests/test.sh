#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
from pathlib import Path

import pandas as pd
import pytest

PARQUET_PATH = '/home/user/output/clean_data.parquet'
REPORT_PATH = '/home/user/output/report.md'
SENSOR_DIR = Path('/home/user/sensor_data')
EXPECTED_COLUMNS = ['timestamp', 'sensor_id', 'temperature', 'humidity']
ENCODINGS = {
    'sensor_A.csv': 'utf-8',
    'sensor_B.csv': 'utf-16',
    'sensor_C.csv': 'iso-8859-1',
}


def build_expected_dataframe():
    frames = []
    for filename, encoding in ENCODINGS.items():
        path = SENSOR_DIR / filename
        assert path.is_file(), f'Missing input file: {path}'

        raw = pd.read_csv(path, encoding=encoding)
        assert set(EXPECTED_COLUMNS).issubset(raw.columns), f'Bad columns in {path}'

        raw = raw[EXPECTED_COLUMNS].copy()
        raw['timestamp'] = pd.to_datetime(raw['timestamp'], errors='coerce')
        raw['temperature'] = pd.to_numeric(raw['temperature'], errors='coerce')
        raw['humidity'] = pd.to_numeric(raw['humidity'], errors='coerce')
        raw = raw.dropna(subset=EXPECTED_COLUMNS)
        raw = raw[
            raw['temperature'].between(-50.0, 150.0, inclusive='both')
            & raw['humidity'].between(0.0, 100.0, inclusive='both')
        ]

        sensor_ids = raw['sensor_id'].unique()
        assert len(sensor_ids) == 1, f'Expected one sensor_id in {path}, found {sensor_ids}'
        sensor_id = sensor_ids[0]

        values = raw.set_index('timestamp')[['temperature', 'humidity']]
        resampled = values.resample('5min').mean().ffill()
        resampled['sensor_id'] = sensor_id
        frames.append(resampled.reset_index()[EXPECTED_COLUMNS])

    return pd.concat(frames, ignore_index=True)


# Derive the oracle directly from the supplied source files before executing the submission.
EXPECTED_DF = build_expected_dataframe()


def find_submission_script():
    preferred = Path('/home/user/process_etl.py')
    if preferred.is_file():
        return preferred

    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in {'sensor_data', '__pycache__'}]
        for name in files:
            if not name.endswith('.py'):
                continue
            path = Path(root) / name
            try:
                text = path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue
            if 'clean_data.parquet' in text and 'report.md' in text:
                candidates.append(path)

    assert candidates, 'No Python ETL script that generates the required outputs was found'
    candidates.sort(key=lambda p: (len(p.parts), str(p)))
    return candidates[0]


def assert_parallel_implementation(script_path):
    source = script_path.read_text(encoding='utf-8')
    tree = ast.parse(source, filename=str(script_path))

    imported_modules = set()
    imported_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imported_modules.add(alias.name)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                imported_modules.add(node.module)
            for alias in node.names:
                imported_names.add(alias.asname or alias.name)

    call_names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name):
                call_names.append(func.id)
            elif isinstance(func, ast.Attribute):
                call_names.append(func.attr)

    parallel_import = any(
        module == 'multiprocessing'
        or module.startswith('multiprocessing.')
        or module == 'concurrent.futures'
        or module.startswith('concurrent.futures.')
        or module == 'threading'
        for module in imported_modules
    )
    constructors = {
        'ThreadPoolExecutor', 'ProcessPoolExecutor', 'Pool', 'Process', 'Thread'
    }
    operations = {'map', 'submit', 'starmap', 'imap', 'imap_unordered', 'apply_async', 'start'}

    assert parallel_import, 'ETL script does not import a parallel-processing facility'
    assert constructors.intersection(call_names) or constructors.intersection(imported_names), (
        'ETL script does not construct a worker pool, executor, process, or thread'
    )
    assert operations.intersection(call_names), (
        'ETL script does not dispatch file processing through a parallel API'
    )


def test_submission_script_runs_and_uses_parallel_processing():
    script = find_submission_script()
    assert_parallel_implementation(script)

    for output in (PARQUET_PATH, REPORT_PATH):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ['python3', str(script)],
        cwd=str(script.parent),
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'ETL script failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def test_parquet_file_exists_and_valid():
    assert os.path.exists(PARQUET_PATH), f'Output Parquet file not found at {PARQUET_PATH}'

    try:
        df = pd.read_parquet(PARQUET_PATH)
    except Exception as e:
        pytest.fail(f'Failed to read Parquet file: {e}')

    expected_columns = {'timestamp', 'sensor_id', 'temperature', 'humidity'}
    assert expected_columns.issubset(set(df.columns)), f'Parquet file missing expected columns. Found: {df.columns}'

    # Preserve the original validation assertions.
    assert df['temperature'].min() >= -50.0, 'Found temperature below -50.0 in final data'
    assert df['temperature'].max() <= 150.0, 'Found temperature above 150.0 in final data'
    assert df['humidity'].min() >= 0.0, 'Found humidity below 0.0 in final data'
    assert df['humidity'].max() <= 100.0, 'Found humidity above 100.0 in final data'
    assert not df.isnull().any().any(), 'Found null/NaN values in final data'

    timestamps = pd.to_datetime(df['timestamp'])
    minutes = timestamps.dt.minute
    assert all(minutes % 5 == 0), 'Not all timestamps are at strictly 5-minute intervals'

    actual = df[EXPECTED_COLUMNS].copy()
    actual['timestamp'] = pd.to_datetime(actual['timestamp'])
    expected = EXPECTED_DF.copy()
    expected['timestamp'] = pd.to_datetime(expected['timestamp'])

    actual = actual.sort_values(['sensor_id', 'timestamp']).reset_index(drop=True)
    expected = expected.sort_values(['sensor_id', 'timestamp']).reset_index(drop=True)

    pd.testing.assert_frame_equal(
        actual,
        expected,
        check_dtype=False,
        check_exact=False,
        rtol=1e-10,
        atol=1e-10,
    )


def test_report_matches_parquet():
    assert os.path.exists(REPORT_PATH), f'Report file not found at {REPORT_PATH}'

    df = pd.read_parquet(PARQUET_PATH)
    total_sensors = df['sensor_id'].nunique()
    total_records = len(df)
    avg_temps = df.groupby('sensor_id')['temperature'].mean()
    hottest_sensor = avg_temps.idxmax()
    hottest_temp = avg_temps.max()

    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        report_content = f.read()

    # Preserve the original report assertions.
    assert f'Total sensors processed: {total_sensors}' in report_content, 'Report does not contain correct total sensors'
    assert f'Total valid records after resampling: {total_records}' in report_content, 'Report does not contain correct total records'
    assert f'Sensor with highest average temp: {hottest_sensor}' in report_content, 'Report does not contain correct hottest sensor'
    expected_temp_str = f'{hottest_temp:.2f}'
    assert f'Average temp of hottest sensor: {expected_temp_str}' in report_content, 'Report does not contain correct hottest sensor average temperature'

    expected_report = (
        '# ETL Processing Report\n'
        f'Total sensors processed: {total_sensors}\n'
        f'Total valid records after resampling: {total_records}\n'
        f'Sensor with highest average temp: {hottest_sensor}\n'
        f'Average temp of hottest sensor: {expected_temp_str}'
    )
    assert report_content.strip() == expected_report, 'Report does not use the required exact template'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
