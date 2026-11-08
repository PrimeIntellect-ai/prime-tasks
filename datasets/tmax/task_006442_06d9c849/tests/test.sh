#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hook
cat <<'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os

_MARKER = os.environ.get('PARALLEL_AUDIT_MARKER')

def _log(op, n=1, workers=0, target=''):
    if not _MARKER:
        return
    try:
        with open(_MARKER, 'a') as f:
            f.write(json.dumps({
                'op': op,
                'n': int(n),
                'workers': int(workers or 0),
                'target': str(target),
            }) + '\n')
    except Exception:
        pass

# Instrument multiprocessing Pool work submission.
try:
    import multiprocessing.pool as _mp_pool

    for _name in ('map', 'map_async', 'imap', 'imap_unordered', 'starmap', 'starmap_async'):
        if hasattr(_mp_pool.Pool, _name):
            _original = getattr(_mp_pool.Pool, _name)
            def _make_wrapper(original, opname):
                def wrapper(self, func, iterable, *args, **kwargs):
                    items = list(iterable)
                    _log('pool_' + opname, len(items), getattr(self, '_processes', 0),
                         getattr(func, '__qualname__', repr(func)))
                    return original(self, func, items, *args, **kwargs)
                return wrapper
            setattr(_mp_pool.Pool, _name, _make_wrapper(_original, _name))

    if hasattr(_mp_pool.Pool, 'apply_async'):
        _original_apply_async = _mp_pool.Pool.apply_async
        def _apply_async(self, func, args=(), kwds=None, callback=None, error_callback=None):
            _log('pool_apply_async', 1, getattr(self, '_processes', 0),
                 getattr(func, '__qualname__', repr(func)))
            if kwds is None:
                kwds = {}
            return _original_apply_async(self, func, args, kwds, callback, error_callback)
        _mp_pool.Pool.apply_async = _apply_async
except Exception:
    pass

# Instrument concurrent.futures submissions. Executor.map ultimately calls submit.
try:
    import concurrent.futures as _cf

    def _patch_submit(cls, label):
        original = cls.submit
        def submit(self, fn, *args, **kwargs):
            _log(label, 1, getattr(self, '_max_workers', 0),
                 getattr(fn, '__qualname__', repr(fn)))
            return original(self, fn, *args, **kwargs)
        cls.submit = submit

    _patch_submit(_cf.ProcessPoolExecutor, 'process_executor_submit')
    _patch_submit(_cf.ThreadPoolExecutor, 'thread_executor_submit')
except Exception:
    pass

# Also support programs that explicitly create multiprocessing.Process objects.
try:
    import multiprocessing.process as _mp_process
    _original_start = _mp_process.BaseProcess.start
    def _start(self, *args, **kwargs):
        target = getattr(self, '_target', None)
        target_name = getattr(target, '__qualname__', repr(target))
        if target_name != 'worker' and 'multiprocessing.pool' not in str(target):
            _log('process_start', 1, 2, target_name)
        return _original_start(self, *args, **kwargs)
    _mp_process.BaseProcess.start = _start
except Exception:
    pass
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
import subprocess
from pathlib import Path
import pytest

@pytest.fixture(scope='session', autouse=True)
def execute_submitted_parallel_pipeline():
    marker = '/tmp/parallel_audit.jsonl'
    output = '/home/user/investigation_results.jsonl'

    candidates = []
    for path in Path('/home/user').rglob('*.py'):
        if not path.is_file():
            continue
        try:
            source = path.read_text(errors='replace')
        except OSError:
            continue
        if ('investigation_results.jsonl' in source and
                ('multiprocessing' in source or 'concurrent.futures' in source or
                 'concurrent import futures' in source)):
            candidates.append(path)

    assert candidates, (
        'No submitted Python pipeline using multiprocessing or concurrent.futures '
        'and producing investigation_results.jsonl was found under /home/user.'
    )

    failures = []
    executed = False
    for script in sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True):
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env['PARALLEL_AUDIT_MARKER'] = marker
        env['PYTHONPATH'] = '/tmp/verifier_hook' + (
            os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else ''
        )
        try:
            proc = subprocess.run(
                ['python3', str(script)], cwd=str(script.parent), env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                timeout=120
            )
        except Exception as exc:
            failures.append(f'{script}: {exc}')
            continue

        events = []
        if os.path.isfile(marker):
            with open(marker) as f:
                for line in f:
                    try:
                        events.append(json.loads(line))
                    except Exception:
                        pass

        parallel_work = sum(
            int(event.get('n', 0)) for event in events
            if int(event.get('workers', 0)) >= 2
        )
        if proc.returncode == 0 and os.path.isfile(output) and parallel_work >= 2:
            executed = True
            break
        failures.append(
            f'{script}: exit={proc.returncode}, parallel work items={parallel_work}, '
            f'stderr={proc.stderr[-500:]}'
        )

    assert executed, (
        'No submitted pipeline successfully produced the report while actually '
        'submitting at least two work items to a multiprocessing or '
        'concurrent.futures worker pool. ' + ' | '.join(failures)
    )

def levenshtein(s1, s2):
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]

def mask_ip(ip):
    parts = ip.split('.')
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.*.*"
    return ip

def mask_email(email):
    if '@' in email:
        user, domain = email.split('@', 1)
        if len(user) > 0:
            return f"{user[0]}****@{domain}"
    return email

def get_expected_results():
    web_logs_path = '/home/user/web_logs.csv'
    db_logs_path = '/home/user/db_logs.csv'

    web_extracted = []
    status_counts = {}

    with open(web_logs_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            status = row['status_code']
            if status_counts.get(status, 0) < 20:
                web_extracted.append(row)
                status_counts[status] = status_counts.get(status, 0) + 1

    db_logs = {}
    with open(db_logs_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            req_id = row['req_id']
            if req_id not in db_logs:
                db_logs[req_id] = []
            db_logs[req_id].append(row)

    results = []
    for web_row in web_extracted:
        req_id = web_row['req_id']
        if req_id in db_logs:
            min_dist = float('inf')
            best_db_row = None
            for db_row in db_logs[req_id]:
                dist = levenshtein(web_row['error_msg'], db_row['db_error'])
                if dist < min_dist:
                    min_dist = dist
                    best_db_row = db_row

            if min_dist < 15 and best_db_row is not None:
                results.append({
                    "req_id": req_id,
                    "status_code": int(web_row['status_code']) if web_row['status_code'].isdigit() else web_row['status_code'],
                    "masked_ip": mask_ip(web_row['ip_address']),
                    "masked_email": mask_email(best_db_row['user_email']),
                    "web_error": web_row['error_msg'],
                    "db_error": best_db_row['db_error'],
                    "edit_distance": min_dist
                })

    results.sort(key=lambda x: x['req_id'])
    return results

def test_investigation_results_exists():
    file_path = '/home/user/investigation_results.jsonl'
    assert os.path.exists(file_path), f"Output file {file_path} was not created."
    assert os.path.isfile(file_path), f"Output path {file_path} is not a file."

def test_investigation_results_content():
    file_path = '/home/user/investigation_results.jsonl'
    assert os.path.exists(file_path), f"Output file {file_path} was not created."

    expected = get_expected_results()
    actual = []

    with open(file_path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                # Cast status_code to int if it's a string representing an int, to be robust
                if 'status_code' in obj and isinstance(obj['status_code'], str) and obj['status_code'].isdigit():
                    obj['status_code'] = int(obj['status_code'])
                actual.append(obj)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {file_path} is not valid JSON.")

    assert len(actual) == len(expected), f"Expected {len(expected)} results, but got {len(actual)}."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act.get('req_id') == exp['req_id'], f"Row {i} req_id mismatch: expected {exp['req_id']}, got {act.get('req_id')}. Ensure sorting by req_id."
        assert act == exp, f"Row {i} mismatch. Expected: {exp}, Got: {act}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
