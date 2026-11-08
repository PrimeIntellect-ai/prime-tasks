#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/etl_instrument
cat << 'PY_EOF' > /tmp/etl_instrument/sitecustomize.py
import builtins
import io
import os
import multiprocessing.process

_log_path = os.environ.get('ETL_AUDIT_LOG')
_orig_builtin_open = builtins.open
_orig_io_open = io.open
_orig_start = multiprocessing.process.BaseProcess.start

def _log(message):
    if not _log_path:
        return
    fd = os.open(_log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, (message + '\n').encode())
    finally:
        os.close(fd)

def _record_open(file):
    try:
        path = os.path.abspath(os.fspath(file))
    except (TypeError, ValueError):
        return
    prefix = '/home/user/telemetry_input/'
    if path.startswith(prefix) and path.endswith('.csv'):
        _log('OPEN %d %s' % (os.getpid(), path))

def audited_builtin_open(file, *args, **kwargs):
    _record_open(file)
    return _orig_builtin_open(file, *args, **kwargs)

def audited_io_open(file, *args, **kwargs):
    _record_open(file)
    return _orig_io_open(file, *args, **kwargs)

def audited_start(self, *args, **kwargs):
    result = _orig_start(self, *args, **kwargs)
    _log('START %d %d' % (os.getpid(), self.pid))
    return result

builtins.open = audited_builtin_open
io.open = audited_io_open
multiprocessing.process.BaseProcess.start = audited_start
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import subprocess
import pytest

SCRIPT = '/home/user/etl_pipeline.py'
INPUT = '/home/user/telemetry_input'
OUTPUT = '/home/user/etl_output'
HEADER = ['timestamp', 'sensor_id', 'metric_type', 'value', 'unit']


def reset_dirs():
    shutil.rmtree(INPUT, ignore_errors=True)
    shutil.rmtree(OUTPUT, ignore_errors=True)
    os.makedirs(INPUT)


def write_csv(name, rows):
    with open(os.path.join(INPUT, name), 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(HEADER)
        writer.writerows(rows)


def run_pipeline(tag):
    log = '/tmp/etl_audit_' + tag + '.log'
    try:
        os.remove(log)
    except FileNotFoundError:
        pass
    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/etl_instrument' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['ETL_AUDIT_LOG'] = log
    proc = subprocess.Popen(
        ['python3', SCRIPT], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    main_pid = proc.pid
    try:
        stdout, stderr = proc.communicate(timeout=60)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        pytest.fail('ETL pipeline timed out. stdout=%r stderr=%r' % (stdout, stderr))
    assert proc.returncode == 0, 'ETL pipeline failed. stdout=%r stderr=%r' % (stdout, stderr)

    starts = set()
    opens = []
    if os.path.exists(log):
        with open(log) as f:
            for line in f:
                parts = line.rstrip('\n').split(' ', 2)
                if len(parts) == 3 and parts[0] == 'START':
                    starts.add(int(parts[2]))
                elif len(parts) == 3 and parts[0] == 'OPEN':
                    opens.append((int(parts[1]), parts[2]))
    return main_pid, starts, opens


@pytest.fixture(scope='module')
def initial_run():
    reset_dirs()
    write_csv('region1.csv', [
        ['2023-10-01T10:00:00Z', 'S1', 'temp', '68.0', 'F'],
        ['2023-10-01T11:00:00Z', 'S1', 'temp', '22.0', 'C'],
        ['2023-10-01T10:00:00Z', 'S2', 'humidity', '45.0', '%'],
    ])
    write_csv('region2.csv', [
        ['2023-10-01T12:00:00Z', 'S2', 'humidity', '110.0', '%'],
        ['2023-10-01T12:00:00Z', 'S1', 'temp', '150.0', 'F'],
        ['2023-10-01T12:00:00Z', 'S3', 'pressure', '1013.0', 'hPa'],
    ])
    write_csv('region3.csv', [
        ['2023-10-01T13:00:00Z', 'S3', 'pressure', '1015.0', 'hPa'],
        ['2023-10-01T13:00:00Z', 'S2', 'humidity', '55.0', '%'],
        ['2023-10-01T13:00:00Z', 'S1', 'temp', '24.0', 'C'],
        ['2023-10-01T13:00:00Z', 'S4', 'temp', 'invalid', 'C'],
    ])
    main_pid, starts, opens = run_pipeline('initial')
    child_readers = {pid for pid, path in opens if pid in starts}
    assert child_readers, 'No multiprocessing child read any telemetry CSV file.'
    return main_pid, starts, opens


def test_etl_pipeline_exists_and_multiprocessing():
    script_path = '/home/user/etl_pipeline.py'
    assert os.path.isfile(script_path), 'Script missing: ' + script_path
    with open(script_path, 'r') as f:
        content = f.read()
    assert 'multiprocessing' in content or 'concurrent.futures' in content, \
        'The script does not appear to use the multiprocessing module.'


def test_aggregated_json_output(initial_run):
    output_path = '/home/user/etl_output/aggregated.json'
    assert os.path.isfile(output_path), 'Output file missing: ' + output_path
    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('File %s is not valid JSON.' % output_path)
    assert isinstance(data, list), 'Aggregated JSON should be a list of objects.'
    expected_data = [
        {'sensor_id': 'S1', 'metric_type': 'temp', 'avg_value': 22.0},
        {'sensor_id': 'S2', 'metric_type': 'humidity', 'avg_value': 50.0},
        {'sensor_id': 'S3', 'metric_type': 'pressure', 'avg_value': 1014.0},
    ]
    assert len(data) == len(expected_data), 'Expected %d items, got %d.' % (len(expected_data), len(data))
    for i, expected in enumerate(expected_data):
        actual = data[i]
        assert actual.get('sensor_id') == expected['sensor_id'], 'Item %d sensor_id mismatch.' % i
        assert actual.get('metric_type') == expected['metric_type'], 'Item %d metric_type mismatch.' % i
        assert abs(actual.get('avg_value', 0) - expected['avg_value']) < 0.01, 'Item %d avg_value mismatch.' % i


def test_rejected_records_csv_output(initial_run):
    output_path = '/home/user/etl_output/rejected_records.csv'
    assert os.path.isfile(output_path), 'Output file missing: ' + output_path
    with open(output_path, 'r', newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, 'Rejected records CSV is empty.'
    assert rows[0] == HEADER, 'Expected header %r, got %r' % (HEADER, rows[0])
    actual_data_rows = sorted([','.join(row) for row in rows[1:]])
    expected_data_rows = sorted([
        '2023-10-01T12:00:00Z,S1,temp,150.0,F',
        '2023-10-01T12:00:00Z,S2,humidity,110.0,%',
        '2023-10-01T13:00:00Z,S4,temp,invalid,C',
    ])
    assert actual_data_rows == expected_data_rows, 'Rejected records data mismatch.'


def test_runtime_generated_inputs_and_real_parallel_reads(initial_run):
    reset_dirs()
    token = secrets.token_hex(4).upper()
    temp_sensor = 'T' + token
    humidity_sensor = 'H' + token
    pressure_sensor = 'P' + token
    temp_values = []
    humidity_values = []
    pressure_values = []
    rejected = []
    expected_files = set()

    for i in range(8):
        name = 'dynamic_%s_%d.csv' % (token, i)
        expected_files.add(os.path.join(INPUT, name))
        rows = []
        f_value = 50.0 + i + secrets.randbelow(50) / 100.0
        c_value = 18.0 + i / 3.0 + secrets.randbelow(30) / 100.0
        humidity = 35.0 + i * 2 + secrets.randbelow(50) / 100.0
        pressure = 980.0 + i + secrets.randbelow(50) / 100.0
        for j in range(250):
            rows.extend([
                ['2026-09-12T%02d:%02d:00Z' % (i, j % 60), temp_sensor, 'temp', str(f_value), 'F'],
                ['2026-09-12T%02d:%02d:01Z' % (i, j % 60), temp_sensor, 'temp', str(c_value), 'C'],
                ['2026-09-12T%02d:%02d:02Z' % (i, j % 60), humidity_sensor, 'humidity', str(humidity), '%'],
                ['2026-09-12T%02d:%02d:03Z' % (i, j % 60), pressure_sensor, 'pressure', str(pressure), 'hPa'],
            ])
            temp_values.extend([(f_value - 32.0) * 5.0 / 9.0, c_value])
            humidity_values.append(humidity)
            pressure_values.append(pressure)
        bad_rows = [
            ['2026-09-12T23:%02d:00Z' % i, temp_sensor, 'temp', '250.0', 'F'],
            ['2026-09-12T23:%02d:01Z' % i, humidity_sensor, 'humidity', '100.5', '%'],
            ['2026-09-12T23:%02d:02Z' % i, temp_sensor, 'temp', 'not-a-number-' + token, 'C'],
        ]
        rows.extend(bad_rows)
        rejected.extend(bad_rows)
        write_csv(name, rows)

    main_pid, starts, opens = run_pipeline('dynamic_' + token)
    child_opens = [(pid, path) for pid, path in opens if pid in starts]
    child_readers = {pid for pid, path in child_opens}
    child_paths = {path for pid, path in child_opens}
    assert len(child_readers) >= 2, 'CSV files were not read by at least two multiprocessing children.'
    assert main_pid not in {pid for pid, path in opens}, 'The main process read telemetry CSV data instead of delegating reads.'
    assert expected_files.issubset(child_paths), 'Not every generated CSV file was read by a multiprocessing child.'

    with open(os.path.join(OUTPUT, 'aggregated.json')) as f:
        actual = json.load(f)
    expected = [
        {'sensor_id': humidity_sensor, 'metric_type': 'humidity', 'avg_value': round(sum(humidity_values) / len(humidity_values), 2)},
        {'sensor_id': pressure_sensor, 'metric_type': 'pressure', 'avg_value': round(sum(pressure_values) / len(pressure_values), 2)},
        {'sensor_id': temp_sensor, 'metric_type': 'temp', 'avg_value': round(sum(temp_values) / len(temp_values), 2)},
    ]
    expected.sort(key=lambda item: (item['sensor_id'], item['metric_type']))
    assert isinstance(actual, list)
    assert len(actual) == len(expected)
    for got, want in zip(actual, expected):
        assert set(got) == {'sensor_id', 'metric_type', 'avg_value'}
        assert got['sensor_id'] == want['sensor_id']
        assert got['metric_type'] == want['metric_type']
        assert abs(float(got['avg_value']) - want['avg_value']) < 0.005

    with open(os.path.join(OUTPUT, 'rejected_records.csv'), newline='') as f:
        rejected_actual = list(csv.reader(f))
    assert rejected_actual[0] == HEADER
    assert sorted(rejected_actual[1:]) == sorted(rejected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
