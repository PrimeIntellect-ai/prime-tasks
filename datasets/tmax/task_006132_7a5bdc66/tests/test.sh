#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import secrets
import string
import subprocess
import urllib.request

import pytest

BASE = '/home/user/test_env'
C_FILE = f'{BASE}/telemetry.c'
SO_FILE = f'{BASE}/libtelemetry.so'
CFG_FILE = f'{BASE}/haproxy.cfg'
RESULT_FILE = f'{BASE}/result.json'
SERVER_FILE = f'{BASE}/server.py'


class Record(ctypes.Structure):
    _fields_ = [
        ('record_id', ctypes.c_uint32),
        ('decoded_text', ctypes.c_char * 64),
    ]


def load_library():
    try:
        lib = ctypes.CDLL(SO_FILE)
    except Exception as exc:
        pytest.fail(f'Failed to load shared library {SO_FILE}: {exc}')
    lib.process_record.argtypes = [ctypes.c_char_p, ctypes.POINTER(Record)]
    lib.process_record.restype = ctypes.c_int
    return lib


def rot13(data):
    out = bytearray()
    for value in data:
        if ord('a') <= value <= ord('z'):
            value = ord('a') + (value - ord('a') + 13) % 26
        elif ord('A') <= value <= ord('Z'):
            value = ord('A') + (value - ord('A') + 13) % 26
        out.append(value)
    return bytes(out)


def valid_payload(record_id, text):
    return (record_id.to_bytes(4, 'little') + text).hex().encode('ascii')


def post(payload):
    request = urllib.request.Request(
        'http://127.0.0.1:8080/', data=payload, method='POST'
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return response.status, response.read()


def matching_process(executable=None, required_args=()):
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as handle:
                cmdline = handle.read().replace(b'\0', b' ').decode('utf-8', 'replace')
            exe = os.path.basename(os.readlink(f'/proc/{entry}/exe'))
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
        if executable is not None and exe != executable:
            continue
        if all(argument in cmdline for argument in required_args):
            return True
    return False


def test_c_source_and_library_exist():
    assert os.path.isfile(C_FILE), f'C source file {C_FILE} does not exist.'
    assert os.path.isfile(SO_FILE), f'Shared library {SO_FILE} does not exist.'


def test_haproxy_config_exists():
    assert os.path.isfile(CFG_FILE), f'HAProxy config file {CFG_FILE} does not exist.'


def test_haproxy_config_content_and_validity():
    with open(CFG_FILE, encoding='utf-8') as handle:
        config = handle.read()

    uncommented = '\n'.join(line.split('#', 1)[0] for line in config.splitlines())
    has_8080_listener = bool(
        re.search(r'(?im)^\s*bind\s+[^\n]*:8080\b', uncommented)
        or re.search(r'(?im)^\s*listen\s+\S+\s+\S*:8080\b', uncommented)
    )
    assert has_8080_listener, 'HAProxy config does not listen on port 8080.'
    assert re.search(
        r'(?im)^\s*server\s+\S+\s+127\.0\.0\.1:9000\b', uncommented
    ), 'HAProxy config does not define a backend server at 127.0.0.1:9000.'

    checked = subprocess.run(
        ['haproxy', '-c', '-f', CFG_FILE], capture_output=True, text=True
    )
    assert checked.returncode == 0, (
        'HAProxy rejected haproxy.cfg:\n' + checked.stdout + checked.stderr
    )


def test_result_json_content():
    assert os.path.isfile(RESULT_FILE), f'Result file {RESULT_FILE} does not exist.'

    with open(RESULT_FILE, 'r') as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f'File {RESULT_FILE} does not contain valid JSON.')

    assert 'id' in data, "JSON response is missing the 'id' field."
    assert 'text' in data, "JSON response is missing the 'text' field."
    assert data['id'] == 5, f"Expected id 5, got {data['id']}"
    assert data['text'] == 'hello world!', (
        f"Expected text 'hello world!', got '{data['text']}'"
    )


def test_libtelemetry_abi():
    if not os.path.isfile(SO_FILE):
        pytest.skip('Shared library not found, skipping ABI test.')

    lib = load_library()
    record = Record()
    hex_input = b'050000007572797962206a6265797121'
    result = lib.process_record(hex_input, ctypes.byref(record))

    assert result == 0, 'process_record returned a non-zero status for valid input.'
    assert record.record_id == 5, f'Expected record_id 5, got {record.record_id}'
    decoded_text = record.decoded_text.decode('utf-8')
    assert decoded_text == 'hello world!', (
        f"Expected decoded_text 'hello world!', got '{decoded_text}'"
    )


def test_libtelemetry_general_decoding():
    lib = load_library()
    cases = [
        (0, b''),
        (0x78563412, b'AbCdEfGhIjKlMnOpQrStUvWxYz 0123!?'),
        (0xFFFFFFFF, b'a' * 63),
    ]
    alphabet = (string.ascii_letters + string.digits + ' !?.,_-').encode('ascii')
    for _ in range(8):
        size = secrets.randbelow(63) + 1
        text = bytes(alphabet[secrets.randbelow(len(alphabet))] for _ in range(size))
        cases.append((secrets.randbits(32), text))

    for record_id, text in cases:
        record = Record()
        result = lib.process_record(valid_payload(record_id, text), ctypes.byref(record))
        assert result == 0, f'Valid payload was rejected: id={record_id}, text={text!r}'
        assert record.record_id == record_id
        assert bytes(record.decoded_text) == rot13(text)


def test_libtelemetry_rejects_invalid_input():
    lib = load_library()
    invalid_inputs = [
        b'',
        b'00',
        b'000000',
        b'0000000',
        b'0000000g',
        b'01000000x1',
        b'010000000',
        valid_payload(1, b'x' * 64),
    ]
    for payload in invalid_inputs:
        record = Record()
        result = lib.process_record(payload, ctypes.byref(record))
        assert result == -1, f'Invalid payload was not rejected: {payload!r}'


def test_required_processes_and_live_proxy_pipeline():
    assert matching_process('haproxy', (CFG_FILE,)), (
        'HAProxy is not running with the required configuration.'
    )
    assert matching_process(required_args=(SERVER_FILE,)), (
        'The provided Python backend is not running.'
    )

    alphabet = (string.ascii_letters + string.digits + ' !?.,_-').encode('ascii')
    for _ in range(5):
        record_id = secrets.randbits(32)
        size = secrets.randbelow(40) + 1
        text = bytes(alphabet[secrets.randbelow(len(alphabet))] for _ in range(size))
        status, body = post(valid_payload(record_id, text))
        assert status == 200
        assert json.loads(body.decode('utf-8')) == {
            'id': record_id,
            'text': rot13(text).decode('ascii'),
        }


def test_result_is_exact_captured_proxy_response():
    payload = b'050000007572797962206a6265797121'
    status, current_body = post(payload)
    assert status == 200
    with open(RESULT_FILE, 'rb') as handle:
        saved_body = handle.read()
    assert saved_body == current_body, (
        'result.json is not the exact response body currently returned by HAProxy.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
