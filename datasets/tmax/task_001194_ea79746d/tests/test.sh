#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import gzip
import json
import os
import secrets
import struct
import subprocess
import sys
import pytest

PARSER = '/home/user/parser.py'
ARTIFACT_DIR = '/home/user/artifacts'
MANIFEST = '/home/user/manifest.jsonl'
SORTED_MANIFEST = '/home/user/manifest_sorted.jsonl'


def expected_from_data(filename, data):
    magic, artifact_id, timestamp = struct.unpack('<4sIQ', data[:16])
    assert magic == b'BLOB'
    iso = datetime.datetime.fromtimestamp(timestamp, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    return {'filename': filename, 'id': artifact_id, 'timestamp': iso}


def parse_single_json_output(result):
    assert result.returncode == 0, f'parser failed: {result.stderr.decode(errors="replace")}'
    text = result.stdout.decode('utf-8')
    lines = text.splitlines()
    assert len(lines) == 1 and lines[0].strip(), f'parser must print exactly one JSON line, got: {text!r}'
    value = json.loads(lines[0])
    assert isinstance(value, dict)
    assert set(value.keys()) == {'filename', 'id', 'timestamp'}
    return value


def test_parser_exists_and_accepts_exactly_one_argument():
    assert os.path.exists(PARSER), f'The file {PARSER} does not exist.'
    assert os.path.isfile(PARSER), f'The path {PARSER} is not a file.'

    no_arg = subprocess.run([sys.executable, PARSER], input=b'', stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=5)
    assert no_arg.returncode != 0, 'parser.py must reject calls with no filename argument'

    two_args = subprocess.run([sys.executable, PARSER, 'one.dat', 'two.dat'], input=b'',
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert two_args.returncode != 0, 'parser.py must reject calls with more than one argument'


def test_parser_reads_binary_data_from_stdin_on_unseen_input():
    artifact_id = secrets.randbelow(2**32)
    timestamp = 946684800 + secrets.randbelow(1500000000)
    filename = f'probe_{secrets.token_hex(8)}.dat'
    data = struct.pack('<4sIQ', b'BLOB', artifact_id, timestamp) + secrets.token_bytes(37)

    result = subprocess.run([sys.executable, PARSER, filename], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert parse_single_json_output(result) == expected_from_data(filename, data)


def test_parser_with_decompression_pipe_for_all_artifacts():
    for filename in sorted(name for name in os.listdir(ARTIFACT_DIR) if name.endswith('.dat')):
        path = os.path.join(ARTIFACT_DIR, filename)
        with gzip.open(path, 'rb') as f:
            expected = expected_from_data(filename, f.read())

        decompressor = subprocess.Popen(['gzip', '-cd', path], stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE)
        try:
            parser_result = subprocess.run([sys.executable, PARSER, filename],
                                           stdin=decompressor.stdout, stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, timeout=5)
        finally:
            decompressor.stdout.close()
        gzip_stderr = decompressor.stderr.read()
        gzip_status = decompressor.wait(timeout=5)
        assert gzip_status == 0, f'gzip failed for {path}: {gzip_stderr.decode(errors="replace")}'
        assert parse_single_json_output(parser_result) == expected


def test_manifest_exists_and_matches_artifacts():
    assert os.path.exists(MANIFEST), f'The file {MANIFEST} does not exist.'
    assert os.path.isfile(MANIFEST), f'The path {MANIFEST} is not a file.'

    expected = []
    for filename in sorted(name for name in os.listdir(ARTIFACT_DIR) if name.endswith('.dat')):
        with gzip.open(os.path.join(ARTIFACT_DIR, filename), 'rb') as f:
            expected.append(expected_from_data(filename, f.read()))

    with open(MANIFEST, 'r', encoding='utf-8') as f:
        manifest_lines = f.read().splitlines()
    assert len(manifest_lines) == len(expected)
    assert all(line.strip() for line in manifest_lines)
    actual = [json.loads(line) for line in manifest_lines]
    assert all(isinstance(item, dict) and set(item) == {'filename', 'id', 'timestamp'} for item in actual)
    assert sorted(actual, key=lambda item: item['filename']) == expected

    with open(SORTED_MANIFEST, 'r', encoding='utf-8') as f:
        sorted_lines = f.read().splitlines()
    assert sorted_lines == sorted(manifest_lines), 'manifest_sorted.jsonl is not the line-sorted manifest.jsonl'


def test_manifest_sorted_exists_and_correct():
    """Test that manifest_sorted.jsonl exists and contains the correct JSON objects in order."""
    manifest_path = '/home/user/manifest_sorted.jsonl'

    assert os.path.exists(manifest_path), f"The file {manifest_path} does not exist."
    assert os.path.isfile(manifest_path), f"The path {manifest_path} is not a file."

    expected_data = [
        {"filename": "alpha.dat", "id": 101, "timestamp": "2023-01-01T00:00:00Z"},
        {"filename": "beta.dat", "id": 102, "timestamp": "2023-01-02T00:00:00Z"},
        {"filename": "gamma.dat", "id": 103, "timestamp": "2023-01-03T00:00:00Z"}
    ]

    actual_data = []
    with open(manifest_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                actual_data.append(json.loads(line))
            except json.JSONDecodeError as e:
                pytest.fail(f"Failed to parse JSON line in {manifest_path}: {line}\nError: {e}")

    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} lines in {manifest_path}, but found {len(actual_data)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, (
            f"Line {i+1} in {manifest_path} does not match expected.\n"
            f"Expected: {expected}\n"
            f"Actual: {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
