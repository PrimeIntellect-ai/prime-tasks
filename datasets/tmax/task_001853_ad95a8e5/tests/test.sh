#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import re
import stat
import subprocess
import time
import urllib.request

import pytest
import redis

ARCHIVE_PATH = '/home/user/stale_archive.gz'
SOURCE_PATH = '/home/user/archiver.cpp'
CONFIG_PATH = '/app/coordinator/config.json'
BINARY_PATH = '/tmp/archiver_under_test'

EXPECTED_PARTS = []


def canonical_raw_files():
    file1 = b''.join(
        f"Line {i}:  Double  spaces  and  carriage  returns.\r\n".encode()
        for i in range(1, 201)
    )
    file2 = b''.join(
        f"Data {i}:  Double  spaces  here.\r\n".encode()
        for i in range(1, 101)
    )
    file3 = b''.join(
        f"More {i}:  Double  spaces  and  carriage  returns.\r\n".encode()
        for i in range(1, 201)
    )
    return [file1, file2, file3]


def preprocess_text(data):
    return re.sub(b' {2,}', b' ', data.replace(b'\r', b''))


def fetch_with_retry(url):
    last_error = None
    for _ in range(30):
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                return response.read()
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)
    raise AssertionError(f"Could not fetch {url}: {last_error}")


@pytest.fixture(scope='session', autouse=True)
def build_and_execute_submission():
    global EXPECTED_PARTS

    subprocess.run(['service', 'nginx', 'start'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(['redis-server', '--daemonize', 'yes'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)

    client = redis.Redis(host='127.0.0.1', port=6379)
    last_error = None
    for _ in range(30):
        try:
            client.ping()
            last_error = None
            break
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)
    assert last_error is None, f"Redis did not become available: {last_error}"

    expected_metadata = {
        '1': {'filepath': 'file1.txt', 'is_text': True},
        '2': {'filepath': 'file2.dat', 'is_text': False},
        '3': {'filepath': 'file3.txt', 'is_text': True},
    }
    for file_id, metadata in expected_metadata.items():
        client.set(f'file:{file_id}', json.dumps(metadata))

    subprocess.run(['pkill', '-f', '^python3 /app/coordinator/app.py$'], check=False)
    coordinator_log = open('/tmp/coordinator-verifier.log', 'wb')
    subprocess.Popen(['python3', '/app/coordinator/app.py'], stdout=coordinator_log,
                     stderr=subprocess.STDOUT)

    stale_ids = fetch_with_retry('http://127.0.0.1:5000/api/stale_ids').decode().strip().split(',')
    assert stale_ids == ['1', '2', '3'], f"Unexpected stale ID list: {stale_ids}"

    raw_files = canonical_raw_files()
    for index, file_id in enumerate(stale_ids):
        metadata = json.loads(client.get(f'file:{file_id}'))
        assert metadata == expected_metadata[file_id], f"Unexpected metadata for file:{file_id}"
        downloaded = fetch_with_retry(
            'http://127.0.0.1:8080/files/' + metadata['filepath']
        )
        assert downloaded == raw_files[index], f"Source content for file:{file_id} was modified"

    EXPECTED_PARTS = [
        preprocess_text(raw_files[0]),
        raw_files[1],
        preprocess_text(raw_files[2]),
    ]

    assert os.path.exists(SOURCE_PATH), f"C++ source missing at {SOURCE_PATH}"
    source_stat = os.stat(SOURCE_PATH, follow_symlinks=False)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE_PATH} is not a regular file"

    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', SOURCE_PATH, '-o', BINARY_PATH,
         '-lcurl', '-lhiredis', '-lz'],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert compile_result.returncode == 0, 'archiver.cpp failed to compile:\n' + compile_result.stdout

    if os.path.lexists(ARCHIVE_PATH):
        os.remove(ARCHIVE_PATH)

    run_result = subprocess.run(
        [BINARY_PATH], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert run_result.returncode == 0, 'Compiled archiver failed:\n' + run_result.stdout


def test_config_updated():
    """Verify the coordinator config was updated correctly."""
    assert os.path.exists(CONFIG_PATH), f"Config file missing at {CONFIG_PATH}"
    with open(CONFIG_PATH, 'r') as f:
        config = json.load(f)

    assert config.get('redis_host') == '127.0.0.1', 'redis_host not set to 127.0.0.1'
    assert config.get('redis_port') == 6379, 'redis_port not set to 6379'
    assert config.get('storage_url') == 'http://127.0.0.1:8080/files/', 'storage_url not set correctly'


def test_archive_exists():
    """Verify the archive file was created."""
    assert os.path.exists(ARCHIVE_PATH), f"Archive file missing at {ARCHIVE_PATH}"
    assert os.path.isfile(ARCHIVE_PATH), f"Path {ARCHIVE_PATH} is not a file"


def test_archive_contents_and_size():
    """Verify exact concatenation, selective preprocessing, and size."""
    assert os.path.exists(ARCHIVE_PATH), f"Archive file missing at {ARCHIVE_PATH}"
    file_size = os.path.getsize(ARCHIVE_PATH)

    try:
        with gzip.open(ARCHIVE_PATH, 'rb') as archive:
            content_bytes = archive.read()
    except Exception as exc:
        pytest.fail(f"Failed to read {ARCHIVE_PATH} as a gzip file: {exc}")

    expected = b''.join(EXPECTED_PARTS)
    assert content_bytes == expected, 'Archive does not contain the stale files in order with the required selective preprocessing'

    try:
        content = content_bytes.decode('utf-8', errors='ignore')
    except Exception as exc:
        pytest.fail(f"Failed to decode archive contents as utf-8: {exc}")

    first_end = len(EXPECTED_PARTS[0])
    second_end = first_end + len(EXPECTED_PARTS[1])
    text_segments = content_bytes[:first_end] + content_bytes[second_end:]
    binary_segment = content_bytes[first_end:second_end]

    assert b'\r' not in text_segments, 'Carriage returns were not stripped from text files.'
    assert b'  ' not in text_segments, 'Multiple spaces were not collapsed in text files.'
    assert binary_segment == canonical_raw_files()[1], 'The non-text file was incorrectly preprocessed.'
    assert b'\r' in binary_segment and b'  ' in binary_segment, 'Required non-text bytes were not preserved.'

    assert len(content) >= 500, f"Archive decompressed content is too small ({len(content)} bytes), expected at least 500 bytes."

    threshold = 4500
    assert file_size < threshold, f"Archive file size {file_size} bytes is not below the threshold of {threshold} bytes. Pre-processing might be incomplete or compression not optimal."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
