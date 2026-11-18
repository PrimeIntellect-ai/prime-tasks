#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import os
import re
import secrets
import shutil
import socket
import zlib
import pytest

HOST = '127.0.0.1'
PORT = 8888
AUTH_KEY = 'BKP-8821-X9'
DATA_DIR = '/app/data'
SAVED_DIR = f'/tmp/original-data-{os.getpid()}'
RANDOM_MARKER = 'DYNAMIC_VALID_' + secrets.token_hex(16)
RANDOM_MARKER_2 = 'DYNAMIC_SECOND_' + secrets.token_hex(16)
SMALL_MARKER = 'SMALL_' + secrets.token_hex(8)
NONLOG_MARKER = 'NONLOG_' + secrets.token_hex(8)
TOKEN_1 = ''.join(secrets.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789') for _ in range(8))
TOKEN_2 = ''.join(secrets.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789') for _ in range(8))


def setup_module(module):
    os.rename(DATA_DIR, SAVED_DIR)
    os.mkdir(DATA_DIR, 0o777)
    os.chmod(DATA_DIR, 0o777)

    files = {
        'log1.log': b'USER=admin ACTION=login STATUS=success SECRET_TOKEN=x9A4b2C1 details=none\nPadding padding padding padding padding padding padding\n',
        'log2.log': b'rotating...\n',
        'log3.log': b'USER=guest ACTION=logout SECRET_TOKEN=99zzAA11 and another SECRET_TOKEN=00000000\nMore padding to ensure the file is larger than 50 bytes.\n',
        'config.txt': b'SECRET_TOKEN=12345678\nPadding padding padding padding padding padding padding\n',
        f'{secrets.token_hex(8)}.log': (f'{RANDOM_MARKER} SECRET_TOKEN={TOKEN_1} middle SECRET_TOKEN={TOKEN_2} ' + 'payload-' * 12 + '\n').encode(),
        f'{secrets.token_hex(8)}-small.log': (SMALL_MARKER + '\n').encode(),
        f'{secrets.token_hex(8)}.txt': (NONLOG_MARKER + ' ' + 'excluded-' * 12 + '\n').encode(),
    }
    for name, content in files.items():
        with open(os.path.join(DATA_DIR, name), 'wb') as f:
            f.write(content)
        os.chmod(os.path.join(DATA_DIR, name), 0o666)


def teardown_module(module):
    if os.path.isdir(DATA_DIR):
        shutil.rmtree(DATA_DIR)
    if os.path.exists(SAVED_DIR):
        os.rename(SAVED_DIR, DATA_DIR)


def fetch(request):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect((HOST, PORT))
        s.sendall(request)
        data = b''
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        return data
    except ConnectionRefusedError:
        pytest.fail(f'Could not connect to server at {HOST}:{PORT}. Is it running?')
    finally:
        s.close()


def decompress_strict(data):
    try:
        decoder = zlib.decompressobj()
        result = decoder.decompress(data) + decoder.flush()
    except zlib.error:
        pytest.fail('Returned data is not valid zlib compressed data.')
    assert decoder.eof, 'Returned zlib stream is incomplete.'
    assert not decoder.unused_data, 'Unexpected data follows the zlib stream.'
    return result


def expected_file_payloads():
    result = []
    for entry in os.scandir(DATA_DIR):
        if entry.is_file() and entry.name.endswith('.log') and entry.stat().st_size > 50:
            with open(entry.path, 'rb') as f:
                content = f.read()
            result.append(re.sub(rb'SECRET_TOKEN=[A-Za-z0-9]{8}', b'SECRET_TOKEN=REDACTED', content))
    return result


def assert_is_concatenation_of_expected_files(payload):
    pieces = expected_file_payloads()

    @functools.lru_cache(None)
    def matches(offset, mask):
        if mask == (1 << len(pieces)) - 1:
            return offset == len(payload)
        for i, piece in enumerate(pieces):
            if not (mask & (1 << i)) and payload.startswith(piece, offset):
                if matches(offset + len(piece), mask | (1 << i)):
                    return True
        return False

    assert matches(0, 0), 'Payload is not exactly the concatenation of all and only eligible .log files after redaction.'


def test_bad_auth_key():
    """Verify that an invalid auth key results in immediate connection closure with no data."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect((HOST, PORT))
        s.sendall(b'FETCH_BACKUP INVALID-KEY\n')
        data = s.recv(4096)
        assert not data, "Server should not return data for an invalid auth key, but it did."
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to server at {HOST}:{PORT}. Is it running?")
    finally:
        s.close()


def test_backup_server_success():
    """Verify that a valid auth key returns the correct zlib-compressed, redacted log stream."""
    data = fetch(f'FETCH_BACKUP {AUTH_KEY}\n'.encode('utf-8'))
    assert data, "Server returned no data for a valid auth key."

    raw = decompress_strict(data)
    try:
        decompressed = raw.decode('utf-8')
    except UnicodeDecodeError:
        pytest.fail("Decompressed data is not valid UTF-8 text.")

    # Check exclusions
    assert "rotating..." not in decompressed, "Included file <= 50 bytes (e.g., log2.log)."
    assert "12345678" not in decompressed, "Included non .log file (e.g., config.txt)."

    # Check redactions
    assert "SECRET_TOKEN=x9A4b2C1" not in decompressed, "Failed to redact log1."
    assert "SECRET_TOKEN=99zzAA11" not in decompressed, "Failed to redact log3 (first token)."
    assert "SECRET_TOKEN=00000000" not in decompressed, "Failed to redact log3 (second token)."

    # Check expected redacted text and content exists
    assert "SECRET_TOKEN=REDACTED" in decompressed, "Redacted text missing from the output stream."
    assert "USER=admin" in decompressed, "Missing valid log content from log1."
    assert "USER=guest" in decompressed, "Missing valid log content from log3."

    assert RANDOM_MARKER in decompressed, 'Missing dynamically generated eligible log content.'
    assert SMALL_MARKER not in decompressed, 'Included dynamically generated log file <= 50 bytes.'
    assert NONLOG_MARKER not in decompressed, 'Included dynamically generated non-.log file.'
    assert TOKEN_1 not in decompressed and TOKEN_2 not in decompressed, 'Failed to redact dynamically generated tokens.'
    assert_is_concatenation_of_expected_files(raw)


def test_server_reexamines_directory_for_later_requests():
    name = f'{secrets.token_hex(8)}-later.log'
    content = (RANDOM_MARKER_2 + ' ' + 'new-content-' * 12 + '\n').encode()
    with open(os.path.join(DATA_DIR, name), 'wb') as f:
        f.write(content)
    os.chmod(os.path.join(DATA_DIR, name), 0o666)

    data = fetch(f'FETCH_BACKUP {AUTH_KEY}\n'.encode('utf-8'))
    assert data, 'Server returned no data for a later valid request.'
    raw = decompress_strict(data)
    assert RANDOM_MARKER_2.encode() in raw, 'Server did not dynamically process a newly added eligible log file.'
    assert_is_concatenation_of_expected_files(raw)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
