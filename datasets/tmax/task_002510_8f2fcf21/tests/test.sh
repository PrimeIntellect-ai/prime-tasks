#!/bin/bash
set -e
mkdir -p /logs/verifier

HOOK_DIR=/tmp/verifier_hooks
MARKER=/tmp/config_drift_verifier.marker
rm -rf "$HOOK_DIR"
mkdir -p "$HOOK_DIR"

cat << 'HOOK_EOF' > "$HOOK_DIR/sitecustomize.py"
import builtins
import io
import os
import pathlib
import multiprocessing.process

_TARGET = os.path.realpath('/home/user/raw_config_events.jsonl')
_MARKER = '/tmp/config_drift_verifier.marker'
_original_open = builtins.open
_original_io_open = io.open
_original_start = multiprocessing.process.BaseProcess.start


def _mark(value):
    fd = os.open(_MARKER, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, (value + '\n').encode('ascii'))
    finally:
        os.close(fd)


def _is_target(file):
    if isinstance(file, int):
        return False
    try:
        return os.path.realpath(os.fspath(file)) == _TARGET
    except (TypeError, ValueError):
        return False


class _StreamingFile:
    def __init__(self, wrapped):
        self._wrapped = wrapped

    def __enter__(self):
        self._wrapped.__enter__()
        return self

    def __exit__(self, *args):
        return self._wrapped.__exit__(*args)

    def __iter__(self):
        return self

    def __next__(self):
        return next(self._wrapped)

    def read(self, size=-1):
        if size is None or size < 0 or size > 1024 * 1024:
            raise RuntimeError('raw_config_events.jsonl must be streamed, not read wholly into memory')
        return self._wrapped.read(size)

    def read1(self, size=-1):
        if size is None or size < 0 or size > 1024 * 1024:
            raise RuntimeError('raw_config_events.jsonl must be streamed in bounded chunks')
        return self._wrapped.read1(size)

    def readlines(self, *args, **kwargs):
        raise RuntimeError('readlines() is not permitted for the large input file')

    def __getattr__(self, name):
        return getattr(self._wrapped, name)


def _guarded_open_impl(opener, file, *args, **kwargs):
    wrapped = opener(file, *args, **kwargs)
    if _is_target(file):
        _mark('INPUT')
        return _StreamingFile(wrapped)
    return wrapped


def _guarded_open(file, *args, **kwargs):
    return _guarded_open_impl(_original_open, file, *args, **kwargs)


def _guarded_io_open(file, *args, **kwargs):
    return _guarded_open_impl(_original_io_open, file, *args, **kwargs)


def _guarded_start(self, *args, **kwargs):
    _mark('PROCESS')
    return _original_start(self, *args, **kwargs)


builtins.open = _guarded_open
io.open = _guarded_io_open
multiprocessing.process.BaseProcess.start = _guarded_start

_original_read_text = pathlib.Path.read_text
_original_read_bytes = pathlib.Path.read_bytes


def _read_text(self, *args, **kwargs):
    if _is_target(self):
        raise RuntimeError('Path.read_text() is not streaming')
    return _original_read_text(self, *args, **kwargs)


def _read_bytes(self, *args, **kwargs):
    if _is_target(self):
        raise RuntimeError('Path.read_bytes() is not streaming')
    return _original_read_bytes(self, *args, **kwargs)


pathlib.Path.read_text = _read_text
pathlib.Path.read_bytes = _read_bytes
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import subprocess
from datetime import datetime, timedelta

import pytest

INPUT_FILE = '/home/user/raw_config_events.jsonl'
OUTPUT_FILE = '/home/user/hourly_config_drift.csv'
MARKER_FILE = '/tmp/config_drift_verifier.marker'
HOOK_DIR = '/tmp/verifier_hooks'


def compute_expected_results():
    server_events = {}
    seen_events = set()

    with open(INPUT_FILE, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            event_id = data['event_id']
            if event_id in seen_events:
                continue
            seen_events.add(event_id)

            srv = data['server_id']
            if srv not in server_events:
                server_events[srv] = []

            dt = datetime.strptime(data['timestamp'], "%Y-%m-%dT%H:%M:%SZ")
            server_events[srv].append((dt, data['config_hash']))

    for srv in server_events:
        server_events[srv].sort(key=lambda x: x[0])

    start_hour = datetime(2023, 10, 1, 0, 0, 0)
    end_hour = datetime(2023, 10, 7, 23, 0, 0)
    expected_results = []
    current_hour = start_hour

    while current_hour <= end_hour:
        active_hashes = set()
        for evts in server_events.values():
            last_hash = None
            for dt, config_hash in evts:
                if dt <= current_hour:
                    last_hash = config_hash
                else:
                    break
            if last_hash is not None:
                active_hashes.add(last_hash)

        expected_results.append((current_hour.strftime("%Y-%m-%dT%H:%M:%SZ"), len(active_hashes)))
        current_hour += timedelta(hours=1)

    return expected_results


def _script_structure(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            source = f.read()
        tree = ast.parse(source, filename=path)
    except (OSError, SyntaxError, UnicodeError):
        return False, 'not a readable, valid Python script'

    imports_mp = any(
        (isinstance(node, ast.Import) and any(alias.name == 'multiprocessing' for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == 'multiprocessing')
        for node in ast.walk(tree)
    )

    call_names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                call_names.append(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                call_names.append(node.func.attr)

    uses_pool = 'Pool' in call_names and any(
        name in call_names for name in ('map', 'starmap', 'imap', 'imap_unordered', 'map_async', 'starmap_async', 'apply_async')
    )
    uses_process = 'Process' in call_names and 'start' in call_names

    if not imports_mp:
        return False, 'does not import the multiprocessing module'
    if not (uses_pool or uses_process):
        return False, 'does not dispatch work through multiprocessing Pool/Process APIs'
    return True, ''


def test_python_script_exists_and_executes_with_streaming_and_multiprocessing():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != '__pycache__']
        for name in files:
            if name.endswith('.py'):
                path = os.path.join(root, name)
                valid, _ = _script_structure(path)
                if valid:
                    candidates.append(path)

    assert candidates, 'No Python script using multiprocessing Pool/Process APIs was found under /home/user.'
    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)

    failures = []
    executed = False
    for script in candidates:
        for path in (OUTPUT_FILE, MARKER_FILE):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        env = os.environ.copy()
        env['PYTHONPATH'] = HOOK_DIR + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        env['PYTHONDONTWRITEBYTECODE'] = '1'
        try:
            result = subprocess.run(
                ['python3', script],
                cwd=os.path.dirname(script) or '/home/user',
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=120,
            )
        except subprocess.TimeoutExpired:
            failures.append(f'{script}: timed out')
            continue

        if result.returncode != 0:
            failures.append(f'{script}: exited {result.returncode}: {result.stdout[-1000:]}')
            continue

        try:
            with open(MARKER_FILE, 'r') as f:
                markers = set(line.strip() for line in f if line.strip())
        except FileNotFoundError:
            markers = set()

        if 'INPUT' not in markers:
            failures.append(f'{script}: did not open the required input while executing')
            continue
        if 'PROCESS' not in markers:
            failures.append(f'{script}: did not actually start any multiprocessing worker')
            continue
        if not os.path.isfile(OUTPUT_FILE):
            failures.append(f'{script}: did not generate {OUTPUT_FILE}')
            continue

        executed = True
        break

    assert executed, 'No qualifying script executed successfully. ' + ' | '.join(failures)


def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"Path {OUTPUT_FILE} is not a file."


def test_output_csv_content():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    expected_results = compute_expected_results()
    agent_results = []

    with open(OUTPUT_FILE, 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"Output file {OUTPUT_FILE} is empty.")

        assert header == ['hour', 'unique_configs'], f"Header mismatch. Expected ['hour', 'unique_configs'], got {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Row {row} does not have exactly 2 columns."
            agent_results.append((row[0], int(row[1])))

    assert len(agent_results) == len(expected_results), (
        f"Row count mismatch. Expected {len(expected_results)} rows, got {len(agent_results)}."
    )

    for exp, agt in zip(expected_results, agent_results):
        assert agt == exp, f"Mismatch at hour {exp[0]}: expected {exp[1]} unique configs, got {agt[1]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
