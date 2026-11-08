#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import signal
import socket
import stat
import struct
import subprocess
import time
import urllib.request
import wave

import pytest


def levenshtein_distance(s1, s2):
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def clean_result(value):
    return ''.join(filter(str.isalnum, value.strip()))


def assert_acceptable(actual, expected):
    actual = clean_result(actual)
    distance = levenshtein_distance(actual, expected)
    cer = distance / len(expected)
    assert cer <= 0.2, (
        f"CER {cer:.3f} exceeds threshold 0.2. "
        f"Expected: '{expected}', Got: '{actual}'"
    )


def http_get(path):
    with urllib.request.urlopen(
        'http://127.0.0.1:8080' + path,
        timeout=8,
    ) as response:
        assert response.status == 200
        return response.read().decode('utf-8').strip()


def unix_http_get(path):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(8)
    try:
        sock.connect('/tmp/dtmf.sock')
        request = f"GET {path} HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        sock.sendall(request.encode('ascii'))
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        sock.close()
    raw = b''.join(chunks)
    head, separator, body = raw.partition(b'\r\n\r\n')
    assert separator, f"Invalid HTTP response from Unix socket: {raw[:200]!r}"
    status_line = head.split(b'\r\n', 1)[0]
    assert b' 200 ' in status_line, f"Backend returned {status_line!r}"
    return body.decode('utf-8').strip()


def stop_old_nginx():
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/comm', 'r') as f:
                if f.read().strip() == 'nginx':
                    os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)


def nginx_using_required_config_is_running():
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/comm', 'r') as f:
                if f.read().strip() != 'nginx':
                    continue
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ')
            if b'/home/user/nginx.conf' in cmdline:
                return True
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return False


@pytest.fixture(scope='session', autouse=True)
def start_submitted_system():
    for path in ('/home/user/server.go', '/home/user/start.sh', '/home/user/nginx.conf'):
        assert os.path.isfile(path), f"Required file missing: {path}"

    stop_old_nginx()
    for path in ('/tmp/dtmf.sock', '/home/user/nginx.pid'):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        ['/bin/bash', '/home/user/start.sh'],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
    )
    assert completed.returncode == 0, 'start.sh exited unsuccessfully'

    deadline = time.time() + 20
    last_error = None
    while time.time() < deadline:
        try:
            if stat.S_ISSOCK(os.stat('/tmp/dtmf.sock').st_mode):
                http_get('/decode?startup=1')
                break
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    else:
        pytest.fail(f"Submitted system did not become ready: {last_error}")

    assert nginx_using_required_config_is_running(), (
        'Nginx was not started using /home/user/nginx.conf'
    )


def test_nginx_config_updated():
    config_path = '/home/user/nginx.conf'
    assert os.path.exists(config_path), f"Nginx config missing at {config_path}"
    with open(config_path, 'r') as f:
        content = f.read()
    assert 'unix:/tmp/dtmf.sock' in content, (
        'Nginx config not updated to point to /tmp/dtmf.sock'
    )

    active = '\n'.join(line.split('#', 1)[0] for line in content.splitlines())
    assert 'unix:/tmp/dtmf.sock' in active, 'Required socket path is only commented out'
    assert re.search(r'\bproxy_pass\b', active), 'No active proxy_pass directive found'
    assert re.search(r'\blisten\s+8080\b', active), 'Nginx is not configured to listen on port 8080'

    checked = subprocess.run(
        ['nginx', '-t', '-c', config_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert checked.returncode == 0, f"Invalid Nginx configuration:\n{checked.stdout}"
    assert stat.S_ISSOCK(os.stat('/tmp/dtmf.sock').st_mode), (
        '/tmp/dtmf.sock is not an active Unix socket'
    )


def test_dtmf_decoding_api():
    expected = '8675309'
    try:
        result = http_get('/decode?fixture=original')
    except Exception as exc:
        pytest.fail(f"Failed to connect to or read from http://127.0.0.1:8080/decode: {exc}")
    assert_acceptable(result, expected)


DTMF = {
    '1': (697, 1209), '2': (697, 1336), '3': (697, 1477),
    '4': (770, 1209), '5': (770, 1336), '6': (770, 1477),
    '7': (852, 1209), '8': (852, 1336), '9': (852, 1477),
    '0': (941, 1336),
}


def write_dtmf_wav(path, digits):
    sample_rate = 8000
    tone_samples = int(0.24 * sample_rate)
    gap_samples = int(0.10 * sample_rate)
    frames = [0] * int(0.05 * sample_rate)

    for digit in digits:
        low, high = DTMF[digit]
        for i in range(tone_samples):
            envelope = min(1.0, i / 40.0, (tone_samples - 1 - i) / 40.0)
            value = envelope * 0.42 * (
                math.sin(2 * math.pi * low * i / sample_rate)
                + math.sin(2 * math.pi * high * i / sample_rate)
            )
            frames.append(int(32767 * value))
        frames.extend([0] * gap_samples)

    with wave.open(path, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(b''.join(struct.pack('<h', value) for value in frames))


def test_decodes_runtime_generated_audio_through_socket_and_nginx():
    signal_path = '/app/signal.wav'
    with open(signal_path, 'rb') as f:
        original = f.read()

    rng = secrets.SystemRandom()
    sequences = []
    while len(sequences) < 2:
        length = 8 + len(sequences) * 2
        candidate = ''.join(rng.choice('0123456789') for _ in range(length))
        if candidate != '8675309' and candidate not in sequences:
            sequences.append(candidate)

    try:
        for index, expected in enumerate(sequences):
            temporary = f'/app/.verifier-signal-{os.getpid()}-{index}.wav'
            write_dtmf_wav(temporary, expected)
            os.replace(temporary, signal_path)

            nonce = secrets.token_hex(12)
            direct = unix_http_get(f'/decode?dynamic={nonce}&via=socket')
            proxied = http_get(f'/decode?dynamic={nonce}&via=nginx')
            assert_acceptable(direct, expected)
            assert_acceptable(proxied, expected)
    finally:
        temporary = f'/app/.verifier-restore-{os.getpid()}.wav'
        with open(temporary, 'wb') as f:
            f.write(original)
        os.replace(temporary, signal_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
