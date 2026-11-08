#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import ast
import csv
import json
import os
import subprocess
import sys
import uuid

import pytest

RAW_DATA_DIR = '/home/user/raw_data'
OUTPUT_FILE = '/home/user/output/clean_data.jsonl'
SCRIPT_FILE = '/home/user/process_data.py'


def read_csv_robust(filepath):
    """Attempt to read a CSV file using multiple encodings."""
    encodings = ['utf-8', 'utf-16', 'iso-8859-1']
    for enc in encodings:
        try:
            with open(filepath, 'r', encoding=enc) as f:
                text = f.read()
                # If reading succeeds and we find expected headers, return parsed rows
                if 'transaction_id' in text:
                    reader = csv.DictReader(text.splitlines())
                    return list(reader)
        except UnicodeDecodeError:
            continue
    raise ValueError(f"Could not decode or find headers in {filepath}")


def compute_expected_data():
    """Derive the expected output directly from the raw data files."""
    all_records = []
    for filename in os.listdir(RAW_DATA_DIR):
        if filename.endswith('.csv'):
            filepath = os.path.join(RAW_DATA_DIR, filename)
            all_records.extend(read_csv_robust(filepath))

    # Deduplicate by transaction_id, keeping the most recent timestamp
    deduped = {}
    for record in all_records:
        tid = record['transaction_id']
        if tid not in deduped:
            deduped[tid] = record
        else:
            # Compare timestamps string-wise (YYYY-MM-DD HH:MM:SS allows this)
            if record['timestamp'] > deduped[tid]['timestamp']:
                deduped[tid] = record

    # Masking
    for tid, record in deduped.items():
        # Mask email
        email = record['email']
        if '@' in email:
            domain = email.split('@', 1)[1]
            record['email'] = f"***@{domain}"

        # Mask SSN
        ssn = record['ssn']
        if len(ssn) >= 11 and ssn[3] == '-' and ssn[6] == '-':
            record['ssn'] = f"***-**-{ssn[-4:]}"

    # Sort by transaction_id
    sorted_records = sorted(deduped.values(), key=lambda x: x['transaction_id'])
    return sorted_records


def dotted_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = dotted_name(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return ''


def test_processing_script_exists_and_uses_parallel_api():
    assert os.path.isfile(SCRIPT_FILE), f"Required script {SCRIPT_FILE} does not exist."

    with open(SCRIPT_FILE, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_FILE)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_FILE} is not valid Python: {exc}")

    parallel_imported = False
    imported_facilities = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing' or alias.name.startswith('multiprocessing.') or alias.name == 'concurrent.futures':
                    parallel_imported = True
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == 'multiprocessing' or node.module.startswith('multiprocessing.') or node.module == 'concurrent.futures'):
                parallel_imported = True
                for alias in node.names:
                    imported_facilities.add(alias.asname or alias.name)

    facility_names = {
        'Pool', 'Process', 'ProcessPoolExecutor', 'ThreadPoolExecutor',
        'Executor', 'get_context'
    }
    operation_names = {
        'map', 'starmap', 'imap', 'imap_unordered', 'map_async',
        'starmap_async', 'apply_async', 'submit', 'start'
    }
    facility_constructed = False
    parallel_operation = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            name = dotted_name(node.func)
            leaf = name.rsplit('.', 1)[-1]
            if leaf in facility_names or leaf in imported_facilities:
                facility_constructed = True
            if leaf in operation_names:
                parallel_operation = True

    assert parallel_imported, \
        "process_data.py must import multiprocessing or concurrent.futures."
    assert facility_constructed and parallel_operation, \
        "process_data.py must construct and use a multiprocessing/concurrent.futures parallel worker API."


def test_execute_processing_script():
    # Add an unpredictable input so a precomputed five-record output cannot pass.
    token = uuid.uuid4().hex
    transaction_id = f"Z{token}"
    challenge_file = os.path.join(RAW_DATA_DIR, f"verification_{token}.csv")
    challenge_text = (
        "transaction_id,customer_name,email,ssn,amount,timestamp\n"
        f"{transaction_id},Older Record,old.{token}@example.test,123-45-6789,1.00,2024-01-01 00:00:00\n"
        f"{transaction_id},Newest Record,new.{token}@example.test,987-65-4321,2.00,2024-01-02 00:00:00\n"
    )
    with open(challenge_file, 'w', encoding='utf-16') as f:
        f.write(challenge_text)

    instrument_dir = f"/tmp/parallel_instrument_{token}"
    marker_file = f"/tmp/parallel_marker_{token}"
    os.makedirs(instrument_dir)
    sitecustomize = r'''
import os

def _log(label):
    path = os.environ.get("PARALLEL_MARKER")
    if path:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(fd, (label + "\n").encode("ascii"))
        finally:
            os.close(fd)

try:
    import concurrent.futures.thread as _cft
    _old_ts = _cft.ThreadPoolExecutor.submit
    def _ts(self, *args, **kwargs):
        _log("concurrent-submit")
        return _old_ts(self, *args, **kwargs)
    _cft.ThreadPoolExecutor.submit = _ts
except Exception:
    pass

try:
    import concurrent.futures.process as _cfp
    _old_ps = _cfp.ProcessPoolExecutor.submit
    def _ps(self, *args, **kwargs):
        _log("concurrent-submit")
        return _old_ps(self, *args, **kwargs)
    _cfp.ProcessPoolExecutor.submit = _ps
except Exception:
    pass

try:
    import multiprocessing.pool as _mpool
    for _name in ("map", "starmap", "imap", "imap_unordered", "map_async", "starmap_async", "apply_async"):
        if hasattr(_mpool.Pool, _name):
            _old = getattr(_mpool.Pool, _name)
            def _make_wrapper(old, label):
                def _wrapper(self, *args, **kwargs):
                    _log("multiprocessing-" + label)
                    return old(self, *args, **kwargs)
                return _wrapper
            setattr(_mpool.Pool, _name, _make_wrapper(_old, _name))
except Exception:
    pass

try:
    import multiprocessing.process as _mpp
    _old_start = _mpp.BaseProcess.start
    def _start(self, *args, **kwargs):
        _log("multiprocessing-start")
        return _old_start(self, *args, **kwargs)
    _mpp.BaseProcess.start = _start
except Exception:
    pass
'''
    with open(os.path.join(instrument_dir, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
        f.write(sitecustomize)

    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    env = os.environ.copy()
    env['PARALLEL_MARKER'] = marker_file
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = instrument_dir + (os.pathsep + old_pythonpath if old_pythonpath else '')
    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_FILE],
            cwd='/home/user',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process_data.py did not finish within 60 seconds.")

    assert result.returncode == 0, \
        f"process_data.py failed with exit code {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(OUTPUT_FILE), \
        f"Executing {SCRIPT_FILE} did not generate {OUTPUT_FILE}."
    assert os.path.isfile(marker_file) and os.path.getsize(marker_file) > 0, \
        "No multiprocessing or concurrent.futures work API was invoked while process_data.py executed."


def test_output_file_exists():
    """Ensure the output JSONL file exists."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."


def test_output_format_and_content():
    """Verify the output file is valid JSONL and matches the expected derived data."""
    assert os.path.isfile(OUTPUT_FILE), "Cannot verify content: output file is missing."

    expected_data = compute_expected_data()

    actual_data = []
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_data.append(json.loads(line))
            except json.JSONDecodeError as e:
                pytest.fail(f"Line {line_num} in {OUTPUT_FILE} is not valid JSON: {e}")

    # Check sorting and counts
    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} records, but found {len(actual_data)} in output."

    actual_tids = [r.get('transaction_id') for r in actual_data]
    expected_tids = [r['transaction_id'] for r in expected_data]
    assert actual_tids == expected_tids, "Output is not correctly sorted by transaction_id or has incorrect IDs."

    # Check exact content
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        for key in ['transaction_id', 'customer_name', 'email', 'ssn', 'amount', 'timestamp']:
            assert key in actual, f"Record {i} is missing key '{key}'"
            assert actual[key] == expected[key], \
                f"Mismatch in record {i} for key '{key}'. Expected '{expected[key]}', got '{actual[key]}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
