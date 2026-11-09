#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import signal
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import numpy as np
import pytest
import requests
from scipy.io import wavfile


def test_check_script_output():
    check_script_path = "/home/user/check.py"
    audio_file_path = "/app/test_audio.wav"

    assert os.path.isfile(check_script_path), f"Missing check script at {check_script_path}"
    assert os.path.isfile(audio_file_path), f"Missing audio file at {audio_file_path}"

    # Calculate ground truth
    sample_rate, data = wavfile.read(audio_file_path)

    if data.dtype == np.int16:
        data_float = data.astype(np.float32) / 32768.0
    elif data.dtype == np.int32:
        data_float = data.astype(np.float32) / 2147483648.0
    else:
        data_float = data.astype(np.float32)

    if data_float.ndim > 1:
        data_float = np.mean(data_float, axis=1)

    truth_value = np.mean(np.abs(data_float))

    # Run the check script
    result = subprocess.run(["python3", check_script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"check.py failed to run. Stderr: {result.stderr}"

    output_str = result.stdout.strip()
    try:
        output_val = float(output_str)
    except ValueError:
        pytest.fail(f"check.py output could not be parsed as a float. Output was: {output_str!r}")

    error = abs(output_val - truth_value)
    assert error <= 0.001, (
        f"Metric threshold failed: Absolute Error {error} > 0.001. "
        f"Output: {output_val}, Truth: {truth_value}"
    )


def _process_cmdlines():
    cmdlines = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode('utf-8', 'replace')
            if cmd:
                cmdlines.append(cmd)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return cmdlines


def test_nginx_and_gunicorn_proxy_random_audio():
    cmdlines = _process_cmdlines()
    assert any('nginx' in cmd for cmd in cmdlines), 'Nginx is not running'
    assert any('gunicorn' in cmd for cmd in cmdlines), 'Gunicorn is not running'

    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'big'))
    samples = rng.integers(-32768, 32768, size=1739, dtype=np.int16)
    audio = io.BytesIO()
    wavfile.write(audio, 22050, samples)
    payload = audio.getvalue()
    expected = float(np.mean(np.abs(samples.astype(np.float32) / 32768.0)))

    response = requests.post(
        'http://127.0.0.1:8080/process',
        files={'file': ('random.wav', payload, 'audio/wav')},
        timeout=10,
    )
    assert response.status_code == 200, (
        f'Proxied /process request returned {response.status_code}: {response.text!r}'
    )
    assert 'nginx' in response.headers.get('Server', '').lower(), (
        f'Request was not served through Nginx; Server header was '
        f'{response.headers.get("Server")!r}'
    )
    try:
        actual = float(response.text.strip())
    except ValueError:
        pytest.fail(f'Backend response was not a float: {response.text!r}')
    assert abs(actual - expected) <= 0.001, (
        f'Backend metric incorrect for verifier-generated audio: {actual} vs {expected}'
    )


def _stop_nginx():
    targets = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ')
            if b'nginx' in cmd:
                targets.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    for pid in targets:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in targets:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    deadline = time.time() + 5
    while time.time() < deadline:
        sock = socket.socket()
        try:
            sock.bind(('127.0.0.1', 8080))
            sock.close()
            return
        except OSError:
            sock.close()
            time.sleep(0.1)
    pytest.fail('Could not free Nginx port 8080 for check.py request verification')


def test_check_script_really_posts_audio_to_required_url():
    audio_path = '/app/test_audio.wav'
    with open(audio_path, 'rb') as f:
        expected_audio = f.read()

    # A fresh unpredictable response ensures check.py prints the HTTP response
    # rather than recomputing or hardcoding the known test-audio metric.
    nonce = 0.2 + (int.from_bytes(os.urandom(8), 'big') % 500000000) / 1000000000.0
    seen = {'valid': False}

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            body = self.rfile.read(length)
            content_type = self.headers.get('Content-Type', '')
            seen['valid'] = (
                self.path == '/process'
                and content_type.lower().startswith('multipart/form-data;')
                and b'name="file"' in body
                and expected_audio in body
            )
            response = repr(nonce).encode('ascii')
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response)

        def log_message(self, *args):
            pass

    _stop_nginx()
    server = HTTPServer(('127.0.0.1', 8080), Handler)
    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()
    try:
        result = subprocess.run(
            ['python3', '/home/user/check.py'],
            capture_output=True,
            text=True,
            timeout=15,
        )
    finally:
        server.server_close()
        thread.join(timeout=2)

    assert result.returncode == 0, f'check.py failed against HTTP test server: {result.stderr}'
    assert seen['valid'], (
        'check.py did not POST /app/test_audio.wav as multipart field "file" '
        'to http://127.0.0.1:8080/process'
    )
    try:
        output = float(result.stdout.strip())
    except ValueError:
        pytest.fail(f'check.py output was not solely a float: {result.stdout!r}')
    assert output == nonce, 'check.py did not print the floating-point HTTP response'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
