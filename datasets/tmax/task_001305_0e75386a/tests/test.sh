#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import importlib.util
import json
import os
import stat
import struct
import subprocess
import tempfile
import uuid

import pytest

PACKAGE_ROOT = '/app/legacy-doc-parser-1.2.0'
READER_PATH = PACKAGE_ROOT + '/legacy_doc_parser/reader.py'
ARCHIVE_PATH = '/home/user/legacy_docs.dat'
SUMMARY_PATH = '/home/user/summary.csv.gz'


def make_archive(path, records):
    with open(path, 'wb') as f:
        for record in records:
            payload = json.dumps(record).encode('utf-8')
            f.write(struct.pack('<I', len(payload)))
            f.write(payload)


def independently_parse_archive(path):
    records = []
    with open(path, 'rb') as f:
        while True:
            length_bytes = f.read(4)
            if not length_bytes:
                break
            assert len(length_bytes) == 4, 'Archive contains a truncated binary header.'
            length = struct.unpack('<I', length_bytes)[0]
            payload = f.read(length)
            assert len(payload) == length, 'Archive contains a truncated payload.'
            records.append(json.loads(payload.decode('utf-8')))
    return records


def run_vendored_tool(path):
    env = os.environ.copy()
    env['PYTHONPATH'] = PACKAGE_ROOT
    result = subprocess.run(
        ['python3', '-m', 'legacy_doc_parser', path],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'Vendored parser failed for {path}: {result.stderr}'
    )
    try:
        return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    except Exception as exc:
        pytest.fail(f'Vendored parser did not emit a valid JSON metadata stream: {exc}')


def test_reader_was_fixed_and_parses_fresh_archive():
    assert os.path.exists(READER_PATH), f'Expected fixed reader at {READER_PATH}.'
    assert stat.S_ISREG(os.lstat(READER_PATH).st_mode), f'{READER_PATH} must be a regular file.'

    token = uuid.uuid4().hex
    records = [
        {'doc_id': 'R-' + token, 'category': 'Fresh', 'title': 'T', 'content': 'a' * 517},
        {'doc_id': 'S-' + token[::-1], 'category': 'Random', 'title': 'U', 'content': 'b' * 293},
    ]
    with tempfile.TemporaryDirectory() as directory:
        archive = os.path.join(directory, 'fresh.dat')
        make_archive(archive, records)

        spec = importlib.util.spec_from_file_location('submitted_legacy_reader', READER_PATH)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert list(module.parse_archive(archive)) == records, (
            'legacy_doc_parser.reader.parse_archive does not correctly parse fresh little-endian archives.'
        )

        assert run_vendored_tool(archive) == records, (
            'The vendored legacy_doc_parser command does not use a working archive reader.'
        )


def test_vendored_tool_extracts_supplied_archive():
    expected = independently_parse_archive(ARCHIVE_PATH)
    assert run_vendored_tool(ARCHIVE_PATH) == expected


def test_summary_file_exists():
    path = SUMMARY_PATH
    assert os.path.isfile(path), f"Expected output file {path} does not exist."


def test_summary_file_size_threshold():
    path = SUMMARY_PATH
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    file_size = os.path.getsize(path)
    threshold = 250
    assert file_size < threshold, f"File size of {path} is {file_size} bytes, which is not less than the threshold of {threshold} bytes."


def test_summary_file_content():
    path = SUMMARY_PATH
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    try:
        with gzip.open(path, 'rt') as f:
            content = f.read().strip()
    except Exception as e:
        pytest.fail(f"Failed to read {path} as a gzip file: {e}")

    expected_lines = [
        "D001,API",
        "D002,Guide",
        "D003,API",
        "D004,FAQ",
        "D005,Guide"
    ]

    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert actual_lines == expected_lines, f"Content of {path} does not match the expected CSV format and data. Got: {actual_lines}"

    extracted_records = run_vendored_tool(ARCHIVE_PATH)
    independently_derived_lines = [
        f"{record['doc_id']},{record['category']}" for record in extracted_records
    ]
    assert actual_lines == independently_derived_lines, (
        'The compressed CSV does not match metadata extracted by the fixed vendored tool.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
