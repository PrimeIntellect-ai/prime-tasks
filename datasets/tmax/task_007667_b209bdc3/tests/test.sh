#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone

import pytest

PROCESS_PATH = '/home/user/process.py'
PIPELINE_PATH = '/home/user/pipeline.sh'
STATS_PATH = '/home/user/stats.json'
LOGS_PATH = '/home/user/logs'
FIELDS = {'total_requests', 'error_rate', 'avg_response_size'}


def _minute(dt):
    return dt.replace(second=0, microsecond=0)


def _minute_string(dt):
    return dt.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:00Z')


def _expected(records):
    minutes = sorted({_minute(record[0]) for record in records})
    result = {}
    for minute in minutes:
        start = minute - timedelta(minutes=4)
        end = minute + timedelta(minutes=1)
        window = [record for record in records if start <= record[0] < end]
        result[_minute_string(minute)] = {
            'total_requests': len(window),
            'error_rate': round(sum(500 <= record[1] <= 599 for record in window) / len(window), 4),
            'avg_response_size': round(sum(record[2] for record in window) / len(window), 1),
        }
    return result


def _make_records(count):
    rng = secrets.SystemRandom()
    base = datetime(
        rng.choice([2024, 2025, 2026]), rng.randint(1, 12), rng.randint(1, 20),
        rng.randint(1, 20), rng.randint(5, 35), tzinfo=timezone.utc
    )
    records = []
    statuses = [200, 201, 204, 404, 500, 502, 503]
    for offset in range(count):
        for item in range(rng.randint(1, 3)):
            timestamp = base + timedelta(minutes=offset, seconds=rng.randint(0, 59))
            records.append((timestamp, rng.choice(statuses), rng.randint(73, 8191), item))
    return records


def _write_records(paths, records):
    handles = [open(path, 'w') for path in paths]
    try:
        for index, (timestamp, status, size, item) in enumerate(records):
            handles[index % len(handles)].write(
                f"{timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')},/generated/{item},{status},{size}\n"
            )
    finally:
        for handle in handles:
            handle.close()


def _load_and_check(expected):
    assert os.path.isfile(STATS_PATH), f'Stats JSON file not found at {STATS_PATH}'
    with open(STATS_PATH, 'r') as handle:
        try:
            actual = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f'File {STATS_PATH} is not valid JSON')

    assert isinstance(actual, dict), 'stats.json must contain a JSON object'
    assert set(actual) == set(expected), f'Unexpected minute keys: expected {set(expected)}, got {set(actual)}'
    for minute, wanted in expected.items():
        assert isinstance(actual[minute], dict), f'Metrics for {minute} must be an object'
        assert set(actual[minute]) == FIELDS, f'Unexpected metric fields for {minute}'
        assert actual[minute].get('total_requests') == wanted['total_requests']
        assert abs(actual[minute].get('error_rate', -1) - wanted['error_rate']) < 0.00001
        assert abs(actual[minute].get('avg_response_size', -1) - wanted['avg_response_size']) < 0.00001


def test_pipeline_script_executable():
    script_path = '/home/user/pipeline.sh'
    assert os.path.isfile(script_path), f"Pipeline script not found at {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Pipeline script {script_path} is not executable"


def test_process_script_exists_and_uses_parallel_processing():
    assert os.path.isfile(PROCESS_PATH), f'Processing script not found at {PROCESS_PATH}'
    with open(PROCESS_PATH, 'r') as handle:
        source = handle.read()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f'{PROCESS_PATH} is not valid Python: {exc}')

    parallel_modules = False
    imported_parallel_callables = set()
    constructors = {'Pool', 'Process', 'ProcessPoolExecutor', 'ThreadPoolExecutor'}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name == 'multiprocessing' or alias.name.startswith('concurrent') for alias in node.names):
                parallel_modules = True
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ''
            if module == 'multiprocessing' or module.startswith('multiprocessing.') or module == 'concurrent.futures':
                parallel_modules = True
                for alias in node.names:
                    if alias.name in constructors:
                        imported_parallel_callables.add(alias.asname or alias.name)

    parallel_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in imported_parallel_callables:
            parallel_call = True
        elif isinstance(node.func, ast.Attribute) and node.func.attr in constructors:
            parallel_call = True

    assert parallel_modules and parallel_call, (
        'process.py must actually use multiprocessing or concurrent.futures to process files in parallel'
    )


def test_crontab_entry():
    crontab_path = '/home/user/crontab.txt'
    assert os.path.isfile(crontab_path), f"Crontab file not found at {crontab_path}"

    with open(crontab_path, 'r') as f:
        content = f.read().strip()

    match = re.search(r'(?:\*/5|0,5,10,15,20,25,30,35,40,45,50,55)\s+\*\s+\*\s+\*\s+\*\s+/home/user/pipeline\.sh', content)
    assert match is not None, f"Crontab entry does not match the expected schedule for /home/user/pipeline.sh every 5 minutes. Found: {content}"
    entries = [line for line in content.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    assert len(entries) == 1, f'crontab.txt must contain a single crontab entry, found {len(entries)}'


def test_process_reads_multiple_command_line_paths():
    records = _make_records(7)
    with tempfile.TemporaryDirectory(prefix='log inputs ') as directory:
        paths = [
            os.path.join(directory, 'input one.csv'),
            os.path.join(directory, 'second-input.data'),
            os.path.join(directory, 'third.log'),
        ]
        _write_records(paths, records)
        completed = subprocess.run(
            [sys.executable, PROCESS_PATH] + paths,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert completed.returncode == 0, f'process.py failed: {completed.stderr}'
        _load_and_check(_expected(records))


def test_pipeline_executes_process_with_all_access_logs():
    records = _make_records(9)
    token = uuid.uuid4().hex
    saved_logs = f'/home/user/logs.__verify_{token}'
    saved_process = f'/home/user/process.py.__verify_{token}'
    marker = f'/tmp/process_args_{token}.json'
    logs_moved = False
    process_moved = False

    try:
        os.rename(LOGS_PATH, saved_logs)
        logs_moved = True
        os.mkdir(LOGS_PATH)
        access_paths = [
            os.path.join(LOGS_PATH, 'access_alpha.log'),
            os.path.join(LOGS_PATH, 'access_beta.log'),
            os.path.join(LOGS_PATH, 'access_gamma.log'),
        ]
        _write_records(access_paths, records)
        with open(os.path.join(LOGS_PATH, 'ignored.log'), 'w') as handle:
            handle.write('2037-01-01T00:00:00Z,/must/not/be/read,599,999999\n')

        os.rename(PROCESS_PATH, saved_process)
        process_moved = True
        wrapper = f'''#!/usr/bin/env python3
import json
import os
import sys
with open({marker!r}, 'w') as handle:
    json.dump(sys.argv[1:], handle)
os.execv(sys.executable, [sys.executable, {saved_process!r}] + sys.argv[1:])
'''
        with open(PROCESS_PATH, 'w') as handle:
            handle.write(wrapper)
        os.chmod(PROCESS_PATH, 0o755)

        completed = subprocess.run(
            [PIPELINE_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        assert completed.returncode == 0, f'pipeline.sh failed: {completed.stderr}'
        assert os.path.isfile(marker), 'pipeline.sh did not execute /home/user/process.py'
        with open(marker, 'r') as handle:
            supplied = json.load(handle)
        assert sorted(map(os.path.realpath, supplied)) == sorted(map(os.path.realpath, access_paths)), (
            'pipeline.sh must pass every access_*.log path, and only those paths, to process.py'
        )
        _load_and_check(_expected(records))
    finally:
        if os.path.exists(PROCESS_PATH) and process_moved:
            os.remove(PROCESS_PATH)
        if process_moved and os.path.exists(saved_process):
            os.rename(saved_process, PROCESS_PATH)
        if logs_moved:
            if os.path.exists(LOGS_PATH):
                shutil.rmtree(LOGS_PATH)
            if os.path.exists(saved_logs):
                os.rename(saved_logs, LOGS_PATH)
        if os.path.exists(marker):
            os.remove(marker)


def test_stats_json_correctness():
    completed = subprocess.run(
        [PIPELINE_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert completed.returncode == 0, f'pipeline.sh failed on the supplied logs: {completed.stderr}'

    stats_path = '/home/user/stats.json'
    assert os.path.isfile(stats_path), f"Stats JSON file not found at {stats_path}"

    with open(stats_path, 'r') as f:
        try:
            stats = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {stats_path} is not valid JSON")

    expected_stats = {
        "2023-10-01T10:00:00Z": {"total_requests": 1, "error_rate": 0.0000, "avg_response_size": 500.0},
        "2023-10-01T10:01:00Z": {"total_requests": 2, "error_rate": 0.5000, "avg_response_size": 350.0},
        "2023-10-01T10:02:00Z": {"total_requests": 3, "error_rate": 0.3333, "avg_response_size": 566.7},
        "2023-10-01T10:03:00Z": {"total_requests": 4, "error_rate": 0.2500, "avg_response_size": 575.0},
        "2023-10-01T10:04:00Z": {"total_requests": 5, "error_rate": 0.4000, "avg_response_size": 510.0},
        "2023-10-01T10:05:00Z": {"total_requests": 5, "error_rate": 0.4000, "avg_response_size": 630.0}
    }

    for minute, expected in expected_stats.items():
        assert minute in stats, f"Missing expected minute key {minute} in stats.json"
        actual = stats[minute]
        assert actual.get("total_requests") == expected["total_requests"], \
            f"Incorrect total_requests for {minute}. Expected {expected['total_requests']}, got {actual.get('total_requests')}"
        assert abs(actual.get("error_rate", -1) - expected["error_rate"]) < 0.0002, \
            f"Incorrect error_rate for {minute}. Expected {expected['error_rate']}, got {actual.get('error_rate')}"
        assert abs(actual.get("avg_response_size", -1) - expected["avg_response_size"]) < 0.2, \
            f"Incorrect avg_response_size for {minute}. Expected {expected['avg_response_size']}, got {actual.get('avg_response_size')}"

    assert set(stats) == set(expected_stats), f'Unexpected extra minute keys in stats.json: {set(stats) - set(expected_stats)}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
