#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import gzip
import json
import os
import shutil
import struct
import subprocess
import tarfile

import pytest

SCRIPT_PATH = '/home/user/compact_logs.py'
TARGET_FILE = '/home/user/filtered.json.gz'
TAR_PATH = '/home/user/raw_logs.tar'
EXPECTED_RECORDS = None
SOURCE_FILES = {}


def canonical(record):
    return json.dumps(record, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def parse_binlog(data, name):
    levels = ['DEBUG', 'INFO', 'WARN', 'ERROR']
    records = []
    offset = 0
    while offset < len(data):
        assert len(data) - offset >= 7, f'Truncated record header in {name}'
        timestamp, level, message_length = struct.unpack_from('<IBH', data, offset)
        offset += 7
        assert len(data) - offset >= message_length, f'Truncated message in {name}'
        message = data[offset:offset + message_length].decode('utf-8')
        offset += message_length
        record = {
            'timestamp': timestamp,
            'level': levels[level] if level <= 3 else 'UNKNOWN',
            'message': message,
        }
        if record['level'] != 'DEBUG':
            records.append(record)
    return records


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    global EXPECTED_RECORDS, SOURCE_FILES

    assert os.path.exists(SCRIPT_PATH), f'Python script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH) and not os.path.islink(SCRIPT_PATH), \
        f'Python script {SCRIPT_PATH} must be a regular file.'

    expected = collections.Counter()
    with tarfile.open(TAR_PATH, 'r') as archive:
        members = [m for m in archive.getmembers() if m.isfile() and m.name.endswith('.binlog')]
        assert members, 'raw_logs.tar contains no .binlog files.'
        assert len({m.name for m in members}) == len(members), 'Duplicate .binlog names in archive.'
        for member in members:
            assert not os.path.isabs(member.name) and '..' not in member.name.split('/'), \
                f'Unsafe archive member: {member.name}'
            source = archive.extractfile(member)
            assert source is not None
            data = source.read()
            SOURCE_FILES[member.name] = data
            expected.update(canonical(record) for record in parse_binlog(data, member.name))

    EXPECTED_RECORDS = expected
    assert sum(expected.values()) > 0, 'No non-DEBUG records found in source logs.'

    # Force the submitted automation to perform extraction and generation itself.
    for member_name in SOURCE_FILES:
        destination = os.path.join('/home/user', member_name)
        if os.path.lexists(destination):
            if os.path.isdir(destination) and not os.path.islink(destination):
                shutil.rmtree(destination)
            else:
                os.unlink(destination)
    if os.path.lexists(TARGET_FILE):
        if os.path.isdir(TARGET_FILE) and not os.path.islink(TARGET_FILE):
            shutil.rmtree(TARGET_FILE)
        else:
            os.unlink(TARGET_FILE)

    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, \
        f'compact_logs.py failed with exit code {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'

    # Confirm that each archived binary log was actually extracted intact.
    for member_name, source_data in SOURCE_FILES.items():
        destination = os.path.join('/home/user', member_name)
        assert os.path.isfile(destination), f'Archive member {member_name} was not extracted.'
        with open(destination, 'rb') as extracted:
            assert extracted.read() == source_data, f'Extracted file {member_name} differs from the archive.'


def test_script_exists():
    """Verify that the student wrote the automation script."""
    assert os.path.exists(SCRIPT_PATH), f'Python script {SCRIPT_PATH} does not exist.'


def test_filtered_file_exists_and_size():
    """Verify that the output file exists, is not empty, and meets the size threshold."""
    assert os.path.exists(TARGET_FILE), f'File {TARGET_FILE} does not exist.'
    assert os.path.isfile(TARGET_FILE), f'File {TARGET_FILE} is not a regular file.'

    size = os.path.getsize(TARGET_FILE)
    assert size > 0, f'File {TARGET_FILE} is empty.'
    assert size <= 45000, f'File size {size} exceeds threshold 45000. Ensure you used maximum compression (compresslevel=9).'


def test_filtered_file_contents():
    """Verify valid gzip JSONL, exclusion of DEBUG, and completeness against the binary logs."""
    assert os.path.exists(TARGET_FILE), f'File {TARGET_FILE} does not exist.'

    actual = collections.Counter()
    record_count = 0
    try:
        with gzip.open(TARGET_FILE, 'rt') as output:
            for line in output:
                line = line.strip()
                if not line:
                    continue
                record = json.loads(line)
                assert isinstance(record, dict), f'Output record is not a JSON object: {record!r}'
                assert record.get('level') != 'DEBUG', f'Found DEBUG record in output: {record}'
                actual[canonical(record)] += 1
                record_count += 1
    except gzip.BadGzipFile:
        pytest.fail(f'File {TARGET_FILE} is not a valid gzip archive.')
    except json.JSONDecodeError:
        pytest.fail(f'File {TARGET_FILE} contains invalid JSON.')
    except Exception as exc:
        pytest.fail(f'Failed to read or parse {TARGET_FILE}: {exc}')

    assert record_count > 0, 'No records found in the filtered output.'
    assert actual == EXPECTED_RECORDS, \
        'The output does not contain exactly all non-DEBUG records parsed from the extracted .binlog files.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
