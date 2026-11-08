#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import importlib.metadata
import importlib.machinery
import json
import os
import secrets
import shutil
import subprocess
import time
from collections import Counter


def test_backup_errors_performance_and_correctness():
    script_path = '/home/user/backup_errors.py'
    assert os.path.isfile(script_path), f"Script not found at {script_path}"

    active_logs_dir = '/home/user/active_logs'
    staging_dir = '/home/user/backup_staging'
    csv_path = '/home/user/critical_logs.csv'

    for d in [active_logs_dir, staging_dir]:
        if os.path.exists(d):
            shutil.rmtree(d)
        os.makedirs(d)
    if os.path.exists(csv_path):
        os.unlink(csv_path)

    token = secrets.token_hex(16)
    expected = []

    # Multiple files and unpredictable values prevent a fixed CSV from passing.
    small_a = [
        {"timestamp": f"2026-01-01T00:00:00Z-{token}", "level": "WARNING", "service": "headers", "message": "timestamp service message DB connection lost"},
        {"timestamp": f"2026-01-01T00:00:01Z-{token}", "level": "CRITICAL", "service": f"api,{token[:8]}", "message": f"first critical, {token}"},
        {"timestamp": f"2026-01-01T00:00:02Z-{token}", "level": "critical", "service": "wrong-case", "message": f"must not appear {token}"},
    ]
    small_b = [
        {"timestamp": f"2026-02-02T02:02:02Z-{token}", "level": "CRITICAL", "service": "worker", "message": f"multiline value\n{token}"},
        {"timestamp": f"2026-02-02T02:02:03Z-{token}", "level": "INFO", "service": "web", "message": f"not critical {token}"},
    ]
    for name, records in [('a.json', small_a), ('z.json', small_b)]:
        with open(os.path.join(active_logs_dir, name), 'w') as f:
            json.dump(records, f)
        for record in records:
            if record.get('level') == 'CRITICAL':
                expected.append((record['timestamp'], record['service'], record['message']))

    # Preserve the original large-file performance test while placing several
    # critical records at unpredictable positions with unpredictable contents.
    count = 2500000
    positions = set()
    while len(positions) < 7:
        positions.add(1000 + secrets.randbelow(count - 2000))
    positions = sorted(positions)
    critical_by_position = {}
    for n, position in enumerate(positions):
        message = f"critical-{n}-{token}"
        if n == 0:
            message = f"DB connection lost {token}"
        record = {
            "timestamp": f"2026-03-{n + 1:02d}T12:34:56Z-{token}",
            "level": "CRITICAL",
            "service": f"service-{n}-{token[:6]}",
            "message": message,
        }
        critical_by_position[position] = record
        expected.append((record['timestamp'], record['service'], record['message']))

    log_path = os.path.join(active_logs_dir, 'test_huge.json')
    with open(log_path, 'w') as f:
        f.write('[\n')
        for i in range(count):
            if i in critical_by_position:
                text = json.dumps(critical_by_position[i], separators=(',', ':'))
            else:
                text = '{"timestamp":"2023-10-01T12:00:00Z","level":"INFO","service":"web","message":"Request processed"}'
            f.write(text)
            if i < count - 1:
                f.write(',')
            f.write('\n')
        f.write(']\n')

    # Instrument the installed ijson API so the test can confirm that the
    # submission actually invokes its streaming parser during the timed run.
    hook_dir = '/tmp/ijson_verifier_hook'
    marker = '/tmp/ijson_was_used'
    shutil.rmtree(hook_dir, ignore_errors=True)
    os.makedirs(hook_dir)
    if os.path.exists(marker):
        os.unlink(marker)
    with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w') as f:
        f.write(r'''
import functools
import os
import ijson
import ijson.backends.yajl2_c as _cbackend
_MARKER = "/tmp/ijson_was_used"
_NAMES = ("basic_parse", "parse", "items", "kvitems", "basic_parse_coro", "parse_coro", "items_coro", "kvitems_coro")
def _wrap(fn):
    @functools.wraps(fn)
    def wrapped(*args, **kwargs):
        with open(_MARKER, "a"):
            pass
        return fn(*args, **kwargs)
    return wrapped
for _module in (ijson, _cbackend):
    for _name in _NAMES:
        if hasattr(_module, _name):
            setattr(_module, _name, _wrap(getattr(_module, _name)))
''')

    env = os.environ.copy()
    env['PYTHONPATH'] = hook_dir + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    start_time = time.time()
    result = subprocess.run(['python3', script_path], capture_output=True, text=True, env=env)
    elapsed = time.time() - start_time

    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"
    assert os.path.exists(csv_path), "CSV not found at /home/user/critical_logs.csv"

    # Keep the original content assertions, then enforce the exact header and
    # complete set of critical records (with no non-critical or fabricated rows).
    with open(csv_path, 'r', newline='') as f:
        content = f.read()
    assert "DB connection lost" in content, "Critical log not extracted to the CSV."
    assert "timestamp" in content and "service" in content and "message" in content, "CSV headers missing or incorrect."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['timestamp', 'service', 'message'], f"Incorrect CSV headers: {reader.fieldnames}"
        actual = []
        for row in reader:
            assert None not in row, f"Malformed CSV row: {row}"
            assert set(row) == {'timestamp', 'service', 'message'}, f"Unexpected CSV columns: {row}"
            actual.append((row['timestamp'], row['service'], row['message']))
    assert Counter(actual) == Counter(expected), f"CSV did not contain exactly all CRITICAL entries. Expected {len(expected)} rows, got {len(actual)}."

    # Every active JSON file must have been snapshotted as a hard link.
    expected_names = {'a.json', 'z.json', 'test_huge.json'}
    staged_names = {n for n in os.listdir(staging_dir) if n.endswith('.json')}
    assert staged_names == expected_names, f"Incorrect staged JSON files: {staged_names}"
    for name in expected_names:
        active = os.path.join(active_logs_dir, name)
        staged = os.path.join(staging_dir, name)
        assert os.path.exists(staged), f"File was not hard-linked to backup_staging: {name}"
        stat_active = os.stat(active)
        stat_staged = os.stat(staged)
        assert stat_active.st_ino == stat_staged.st_ino, f"The staged file is not a hard link: {name}"
        assert stat_active.st_dev == stat_staged.st_dev, f"The staged file is not on the same filesystem: {name}"

    assert os.path.exists(marker), "The backup script did not use ijson's streaming parser."

    # Confirm that version 3.2.3 is installed with the native yajl2 backend and
    # that the deliberate setup.py perturbation was repaired.
    check = subprocess.run(
        ['python3', '-c',
         'import importlib.metadata, importlib.machinery, ijson, ijson.backends._yajl2 as native; '
         'assert importlib.metadata.version("ijson") == "3.2.3"; '
         'assert ijson.backend == "yajl2_c", ijson.backend; '
         'assert any(native.__file__.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), native.__file__'],
        capture_output=True, text=True)
    assert check.returncode == 0, f"ijson 3.2.3 C backend is not correctly installed:\n{check.stderr}"

    setup_path = '/app/ijson-3.2.3/setup.py'
    with open(setup_path, 'r') as f:
        setup_text = f.read()
    assert 'use_c_ext = False' not in setup_text, "The deliberate C-extension-disabling perturbation was not removed."
    assert 'use_c_ext = True' in setup_text, "setup.py was not repaired to enable the C extension."

    assert elapsed <= 4.0, f"Execution too slow: {elapsed:.2f} seconds (Threshold: 4.0s). The agent likely failed to fix the C-extension in the vendored package."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
