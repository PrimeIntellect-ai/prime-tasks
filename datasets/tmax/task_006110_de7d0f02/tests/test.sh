#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import multiprocessing
import os
import queue
import signal
import struct
import subprocess
import sys

import pytest

SCRIPT = '/home/user/log_merger.py'
OUTPUT = '/home/user/merged_timeline.json'
LOGS = {
    '/home/user/logs/service_A/log1.bin': [(i * 100, i) for i in range(10, 20)],
    '/home/user/logs/service_B/log1.bin': [
        (-2147483648, 999) if i == 12 else (i * 105, i)
        for i in range(5, 15)
    ],
}


def read_records(path):
    with open(path, 'rb') as f:
        raw = f.read()
    assert len(raw) % 8 == 0, f'{path} is not composed of complete 8-byte records.'
    return [struct.unpack('<ii', raw[i:i + 8]) for i in range(0, len(raw), 8)]


def expected_timeline():
    records = []
    for path, expected_raw_records in LOGS.items():
        actual_raw_records = read_records(path)
        assert actual_raw_records == expected_raw_records, f'The source log was modified: {path}'
        service = os.path.basename(os.path.dirname(path))
        for timestamp, value in actual_raw_records:
            if timestamp >= 0:
                records.append({
                    'service': service,
                    'timestamp': timestamp,
                    'value': value,
                })
    return sorted(records, key=lambda record: record['timestamp'])


def run_script_with_timeout(seconds=10):
    process = subprocess.Popen(
        [sys.executable, SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        pytest.fail('log_merger.py hung instead of completing.')
    assert process.returncode == 0, (
        f'log_merger.py exited with status {process.returncode}.\n'
        f'stdout:\n{stdout}\nstderr:\n{stderr}'
    )


def test_source_logs_are_preserved():
    expected_timeline()


def test_script_exists_and_generates_output_without_deadlock():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} does not exist.'
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    run_script_with_timeout()
    assert os.path.isfile(OUTPUT), (
        'The file /home/user/merged_timeline.json does not exist. '
        'Did the script run successfully?'
    )


def test_merged_timeline_exists():
    assert os.path.isfile(OUTPUT), "The file /home/user/merged_timeline.json does not exist. Did the script run successfully?"


def test_merged_timeline_content():
    with open(OUTPUT, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('The file /home/user/merged_timeline.json does not contain valid JSON.')

    assert isinstance(data, list), 'The JSON output should be a list of records.'

    # Check length: 10 from service_A + 9 valid from service_B = 19
    assert len(data) == 19, f'Expected 19 records in the merged timeline, but found {len(data)}.'

    # Retain the original checks for rejected corruption and schema fields.
    for record in data:
        assert 'timestamp' in record, "Record is missing 'timestamp' key."
        assert 'value' in record, "Record is missing 'value' key."
        assert record['timestamp'] >= 0, f'Found a record with a negative timestamp: {record}'
        assert record['value'] != 999, f'Found the corrupted record with value 999: {record}'

    timestamps = [record['timestamp'] for record in data]
    assert timestamps == sorted(timestamps), 'The records in the merged timeline are not sorted by timestamp in ascending order.'

    # Require every record, value, timestamp, and service to come from the binary logs.
    assert data == expected_timeline(), 'The merged timeline does not exactly match the valid source records.'


def test_worker_signals_completion_after_unexpected_exception(tmp_path):
    spec = importlib.util.spec_from_file_location('submitted_log_merger', SCRIPT)
    merger = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(merger)
    assert hasattr(merger, 'process_file'), 'log_merger.py must provide its worker function process_file.'

    sample = tmp_path / 'record.bin'
    sample.write_bytes(struct.pack('<ii', 1, 1))

    original_unpack = merger.struct.unpack

    def unexpected_unpack_failure(*args, **kwargs):
        raise RuntimeError('injected unexpected parser failure')

    merger.struct.unpack = unexpected_unpack_failure
    completion_queue = multiprocessing.Queue()
    worker = multiprocessing.Process(target=merger.process_file, args=(str(sample), completion_queue))
    try:
        worker.start()
        merger.struct.unpack = original_unpack
        try:
            item = completion_queue.get(timeout=5)
        except queue.Empty:
            pytest.fail('The worker failed to signal completion after an unexpected exception.')
        assert item == 'DONE', 'The worker must always send the DONE completion sentinel.'
    finally:
        merger.struct.unpack = original_unpack
        worker.join(timeout=2)
        if worker.is_alive():
            worker.terminate()
            worker.join(timeout=2)
        completion_queue.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
