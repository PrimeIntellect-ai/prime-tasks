#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SHIM_EOF' > /tmp/curl
#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
data = None
for i, arg in enumerate(args):
    value = None
    if arg in ('-d', '--data', '--data-raw', '--data-binary', '--json') and i + 1 < len(args):
        value = args[i + 1]
    elif arg.startswith('--data=') or arg.startswith('--data-raw=') or arg.startswith('--data-binary=') or arg.startswith('--json='):
        value = arg.split('=', 1)[1]
    elif arg.startswith('-d') and len(arg) > 2:
        value = arg[2:]
    if value is not None:
        if value.startswith('@'):
            try:
                with open(value[1:], 'r') as f:
                    value = f.read()
            except OSError:
                pass
        data = value

with open(os.environ['CURL_TRACE_FILE'], 'a') as f:
    f.write(json.dumps({'args': args, 'data': data}) + '\n')

os.execv('/usr/bin/curl', ['/usr/bin/curl'] + args)
SHIM_EOF
chmod +x /tmp/curl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import json
import os
import py_compile
import random
import re
import string
import subprocess
import urllib.error
import urllib.request

API_URL = 'http://127.0.0.1:8080/process'
TRACE_FILE = '/tmp/e2e_curl_trace.jsonl'


def post_process(value):
    request = urllib.request.Request(
        API_URL,
        data=json.dumps({'input': value}).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            status = response.status
            body = response.read()
    except (urllib.error.URLError, TimeoutError) as exc:
        raise AssertionError(f'Failed to connect to API on 127.0.0.1:8080: {exc}')
    return status, json.loads(body.decode('utf-8'))


def test_python3_sources_and_wrapper_use_rebuilt_library():
    py_compile.compile('/app/api/server.py', doraise=True)
    py_compile.compile('/app/api/wrapper.py', doraise=True)

    source = '/app/vendored/libstrproc-1.0.2/src/strproc.c'
    library = '/app/vendored/libstrproc-1.0.2/libstrproc.so'
    assert os.path.isfile(source), 'The C source is missing'
    assert os.path.isfile(library), 'The C library was not recompiled'

    lib = ctypes.CDLL(library)
    func = lib.process_string
    func.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    func.restype = None

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + ' _-'
    lengths = [1, 17, 254, 256, 300, rng.randint(350, 700)]
    samples = [''.join(rng.choice(alphabet) for _ in range(n)) for n in lengths]
    for value in samples:
        encoded = value.encode('ascii')
        output = ctypes.create_string_buffer(len(encoded) + 1)
        func(encoded, output)
        assert output.value.decode('ascii') == value.upper()

    spec = importlib.util.spec_from_file_location('submitted_wrapper', '/app/api/wrapper.py')
    wrapper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(wrapper)
    for value in samples:
        result = wrapper.process(value)
        assert isinstance(result, str), 'Python 3 wrapper must return text, not bytes'
        assert result == value.upper()


def test_api_short_string():
    status, data = post_process('hello')
    assert status == 200, f'Expected HTTP 200, got {status}'
    assert 'result' in data, "Response JSON missing 'result' key"
    assert data['result'] == 'HELLO', f"Expected 'HELLO', got '{data['result']}'"


def test_api_long_string():
    long_input = 'a' * 300
    status, data = post_process(long_input)
    assert status == 200, f'Expected HTTP 200 for long string, got {status}'
    assert 'result' in data, "Response JSON missing 'result' key"
    expected_result = 'A' * 300
    assert data['result'] == expected_result, f"Expected {expected_result}, got '{data['result']}'"


def test_api_runtime_generated_inputs():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + ' _-'
    lengths = [rng.randint(2, 80) for _ in range(5)] + [rng.randint(256, 900) for _ in range(5)]
    for length in lengths:
        value = ''.join(rng.choice(alphabet) for _ in range(length))
        status, data = post_process(value)
        assert status == 200
        assert data == {'result': value.upper()}


def test_e2e_script_exists_executable_and_runs_three_curl_requests():
    script_path = '/app/test_e2e.sh'
    assert os.path.isfile(script_path), f'Bash script {script_path} is missing.'
    assert os.access(script_path, os.X_OK), f'Bash script {script_path} is not executable.'

    for path in (TRACE_FILE, '/app/test_results.log'):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['PATH'] = '/tmp:' + env.get('PATH', '')
    env['CURL_TRACE_FILE'] = TRACE_FILE
    run = subprocess.run(
        ['bash', '-x', script_path], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert run.returncode == 0, f'test_e2e.sh failed:\n{run.stdout}\n{run.stderr}'

    calls = []
    if os.path.isfile(TRACE_FILE):
        with open(TRACE_FILE) as f:
            calls = [json.loads(line) for line in f if line.strip()]

    if calls:
        assert len(calls) == 3, f'Expected exactly 3 curl requests, observed {len(calls)}'
        payloads = []
        for call in calls:
            assert any('/process' in arg for arg in call['args']), 'curl request did not target /process'
            assert call['data'] is not None, 'curl request did not send a request body'
            payload = json.loads(call['data'])
            assert isinstance(payload.get('input'), str), 'curl payload must contain a string input'
            payloads.append(payload['input'])
        assert any(len(value) > 255 for value in payloads), 'No curl request used an input longer than 255 characters'
    else:
        # Absolute curl paths bypass PATH, so use bash's execution trace as a fallback.
        traced = [line for line in run.stderr.splitlines()
                  if line.startswith('+') and re.search(r'(^|/)curl(?:\s|$)', line[1:].lstrip())]
        assert len(traced) == 3, f'Expected exactly 3 curl requests, observed {len(traced)}'
        assert all('/process' in line for line in traced)
        assert any(re.search(r'[A-Za-z]{256}', line) for line in traced), 'No curl request had a long input'


def test_results_log_exists_and_has_three_success_codes():
    log_path = '/app/test_results.log'
    assert os.path.isfile(log_path), f'Test results log {log_path} is missing.'
    with open(log_path, 'r') as f:
        content = f.read()
    assert '200' in content, "Test results log does not contain expected '200' HTTP status codes."
    codes = re.findall(r'(?<!\d)\d{3}(?!\d)', content)
    assert codes == ['200', '200', '200'], f'Expected exactly three HTTP 200 status codes, got {codes}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
