#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import http.client
import json
import os
import pathlib
import random
import signal
import subprocess
import sys
import time

import pytest

ROOT = pathlib.Path('/home/user/qa_env')
BACKEND = ROOT / 'backend'
RESULT = ROOT / 'result.txt'
EXPECTED_RESULT = 'eyJzdW0iOiA0MC4wMDAwMDB9'


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, check=True, **kwargs)


def stop_existing_services():
    subprocess.run(['pkill', '-x', 'socat'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pkill', '-x', 'nginx'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)
    pidfile = ROOT / 'nginx_temp' / 'nginx.pid'
    try:
        pidfile.unlink()
    except FileNotFoundError:
        pass


def test_result_file_exists():
    assert RESULT.is_file(), f'The file {RESULT} is missing. Did you save the output?'


def test_result_content():
    assert RESULT.is_file(), f'Cannot check content because {RESULT} is missing.'
    content = RESULT.read_text().strip()
    assert content == EXPECTED_RESULT, (
        f'The content of {RESULT} is incorrect.\n'
        f'Expected: {EXPECTED_RESULT}\nGot: {content}\n'
        'Ensure the CMake linking, RPATH, Nginx proxy, and request payload were correct.'
    )


def test_clean_build_linkage_runtime_and_proxy():
    cmake_file = BACKEND / 'CMakeLists.txt'
    nginx_file = ROOT / 'nginx.conf'
    build_script = ROOT / 'build_and_serve.sh'

    assert cmake_file.is_file(), 'CMakeLists.txt is missing'
    assert nginx_file.is_file(), 'nginx.conf is missing'
    assert build_script.is_file(), 'build_and_serve.sh is missing'

    cmake_text = cmake_file.read_text().lower()
    assert 'encode' in cmake_text, 'CMakeLists.txt does not configure the encode library'
    assert ('rpath' in cmake_text or '-wl,-rpath' in cmake_text), (
        'CMakeLists.txt does not configure a runtime library search path'
    )

    stop_existing_services()
    build_dir = BACKEND / 'build'
    subprocess.run(['rm', '-rf', str(build_dir)], check=True)

    # Use the required CI script for a genuinely clean build. Its background
    # listener is stopped afterward so the proxy can be tested deterministically.
    run(
        [str(build_script)],
        cwd=str(ROOT),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=90,
    )
    time.sleep(0.5)
    subprocess.run(['pkill', '-x', 'socat'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    exe = build_dir / 'num_service'
    assert exe.is_file(), 'The CI script did not produce num_service'
    assert os.access(exe, os.X_OK), 'num_service is not executable'
    assert exe.read_bytes()[:4] == b'\x7fELF', 'num_service is not an ELF executable'

    dynamic = run(['readelf', '-d', str(exe)], capture_output=True).stdout
    assert 'Shared library: [libencode.so]' in dynamic, 'num_service is not dynamically linked to libencode.so'
    assert '(RPATH)' in dynamic or '(RUNPATH)' in dynamic, 'num_service has no embedded RPATH/RUNPATH'

    ldd_output = run(['ldd', str(exe)], capture_output=True).stdout
    expected_lib = str((BACKEND / 'lib' / 'libencode.so').resolve())
    assert expected_lib in ldd_output, (
        'libencode.so does not resolve to the supplied backend/lib library:\n' + ldd_output
    )
    assert 'not found' not in ldd_output

    # Exercise the built artifact on independently generated inputs, from a
    # different working directory and without LD_LIBRARY_PATH.
    env = os.environ.copy()
    env.pop('LD_LIBRARY_PATH', None)
    rng = random.Random(73129)
    for _ in range(4):
        values = [rng.randint(-500, 700) / 10.0 for _ in range(rng.randint(2, 7))]
        request = json.dumps({'data': values}, separators=(',', ':'))
        proc = run(
            [str(exe)],
            input=request + '\n',
            cwd='/tmp',
            env=env,
            capture_output=True,
            timeout=10,
        )
        header, separator, encoded = proc.stdout.partition('\r\n\r\n')
        assert separator, f'num_service returned a malformed HTTP response: {proc.stdout!r}'
        assert header.startswith('HTTP/1.1 200 OK')
        expected_json = '{"sum": ' + format(sum(values), '.6f') + '}'
        expected_encoded = base64.b64encode(expected_json.encode()).decode()
        assert encoded == expected_encoded, (
            f'Incorrect response for generated input {request}: expected '
            f'{expected_encoded!r}, got {encoded!r}'
        )

    # Validate and exercise the submitted Nginx configuration against a
    # body-aware test upstream. This tests proxy routing independently of the
    # supplied socat protocol mismatch.
    record_file = pathlib.Path('/tmp/qa_upstream_records.jsonl')
    try:
        record_file.unlink()
    except FileNotFoundError:
        pass

    upstream_code = r'''
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
record = '/tmp/qa_upstream_records.jsonl'
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        with open(record, 'a') as f:
            f.write(json.dumps({'path': self.path, 'body': body.decode()}) + '\n')
        payload = b'upstream-ok:' + body
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, *args):
        pass
HTTPServer(('127.0.0.1', 9000), Handler).serve_forever()
'''
    upstream = subprocess.Popen(
        [sys.executable, '-c', upstream_code],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )

    nginx_started = False
    try:
        time.sleep(0.4)
        assert upstream.poll() is None, 'Could not start the test upstream on port 9000'
        run(['nginx', '-t', '-c', str(nginx_file)], capture_output=True, timeout=10)
        run(['nginx', '-c', str(nginx_file)], capture_output=True, timeout=10)
        nginx_started = True

        requests = [
            ('/api', json.dumps({'probe': 'root-api', 'n': 17})),
            ('/api/subresource', json.dumps({'probe': 'nested-api', 'n': -8})),
        ]
        for path, body in requests:
            last_error = None
            for _ in range(30):
                try:
                    conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=2)
                    conn.request('POST', path, body=body, headers={'Content-Type': 'application/json'})
                    response = conn.getresponse()
                    response_body = response.read().decode()
                    conn.close()
                    assert response.status == 200
                    assert response_body == 'upstream-ok:' + body
                    break
                except (ConnectionRefusedError, OSError) as exc:
                    last_error = exc
                    time.sleep(0.1)
            else:
                raise AssertionError(f'Nginx did not accept requests on port 8080: {last_error}')

        records = [json.loads(line) for line in record_file.read_text().splitlines()]
        assert records == [{'path': path, 'body': body} for path, body in requests], (
            f'Nginx did not proxy /api requests and bodies correctly: {records!r}'
        )
    finally:
        if nginx_started:
            pidfile = ROOT / 'nginx_temp' / 'nginx.pid'
            if pidfile.is_file():
                try:
                    os.kill(int(pidfile.read_text().strip()), signal.SIGTERM)
                except (OSError, ValueError):
                    pass
        upstream.terminate()
        try:
            upstream.wait(timeout=5)
        except subprocess.TimeoutExpired:
            upstream.kill()
        stop_existing_services()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
