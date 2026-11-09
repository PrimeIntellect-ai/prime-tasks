#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import subprocess
import time
import pytest


def run_sanitizer(path, data):
    proc = subprocess.run(['bash', path], input=data, capture_output=True, timeout=10)
    assert proc.returncode == 0, f"sanitizer exited with {proc.returncode}: {proc.stderr.decode(errors='ignore')}"
    return proc.stdout


def redis_entries():
    proc = subprocess.run(
        ['redis-cli', '-p', '6379', '--raw', 'lrange', 'raw_logs', '0', '-1'],
        capture_output=True,
        timeout=5,
    )
    assert proc.returncode == 0, proc.stderr.decode(errors='ignore')
    return proc.stdout.splitlines()


def wait_for_redis_token(token, timeout=8):
    deadline = time.time() + timeout
    token = token.encode()
    while time.time() < deadline:
        entries = redis_entries()
        if any(token in entry for entry in entries):
            return entries
        time.sleep(0.2)
    return redis_entries()


def test_nginx_config_fixed():
    """Verify syntax, binding to port 8080, and that Nginx serves a request."""
    proc = subprocess.run(['nginx', '-t'], capture_output=True)
    assert proc.returncode == 0, f"Nginx config syntax check failed. It is still broken:\n{proc.stderr.decode(errors='ignore')}"

    subprocess.run(['nginx', '-s', 'stop'], capture_output=True)
    time.sleep(0.5)
    try:
        start = subprocess.run(['nginx'], capture_output=True, timeout=5)
        assert start.returncode == 0, f"Nginx failed to start: {start.stderr.decode(errors='ignore')}"

        token = secrets.token_hex(12)
        request = subprocess.run(
            ['curl', '-sS', '--max-time', '5', '-D', '-', '-o', '/tmp/nginx-response-body',
             f'http://127.0.0.1:8080/verifier-{token}'],
            capture_output=True,
            timeout=8,
        )
        assert request.returncode == 0, f"Nginx did not serve port 8080: {request.stderr.decode(errors='ignore')}"
        assert b'server: nginx' in request.stdout.lower(), "The service answering on port 8080 was not Nginx"
    finally:
        subprocess.run(['nginx', '-s', 'stop'], capture_output=True)
        time.sleep(0.3)


def test_log_ingest_script_fixed():
    """Verify that log_ingest.sh uses the correct Redis port and integrates the sanitizer."""
    ingest_script_path = "/app/log_ingest.sh"
    assert os.path.isfile(ingest_script_path), f"{ingest_script_path} does not exist"

    with open(ingest_script_path, "r") as f:
        content = f.read()

    assert "6379" in content, "log_ingest.sh does not contain the correct redis-cli port 6379."
    assert "6380" not in content, "log_ingest.sh still contains the incorrect redis-cli port 6380."
    assert "sanitizer.sh" in content, "log_ingest.sh does not appear to pipe logs through sanitizer.sh."


def test_sanitizer_adversarial_corpus():
    """Preserve clean lines exactly and drop malicious lines, including fresh randomized cases."""
    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"
    sanitizer_path = "/app/sanitizer.sh"

    assert os.path.isfile(sanitizer_path), f"{sanitizer_path} does not exist"

    clean_modified = []
    clean_total = 0
    if os.path.isdir(clean_dir):
        for f in sorted(os.listdir(clean_dir)):
            filepath = os.path.join(clean_dir, f)
            if os.path.isfile(filepath):
                clean_total += 1
                with open(filepath, 'rb') as fd:
                    original = fd.read()

                proc = subprocess.run(['bash', sanitizer_path], input=original, capture_output=True)
                if proc.stdout != original:
                    clean_modified.append(f)

    evil_bypassed = []
    evil_total = 0
    if os.path.isdir(evil_dir):
        for f in sorted(os.listdir(evil_dir)):
            filepath = os.path.join(evil_dir, f)
            if os.path.isfile(filepath):
                evil_total += 1
                with open(filepath, 'rb') as fd:
                    original = fd.read()

                proc = subprocess.run(['bash', sanitizer_path], input=original, capture_output=True)
                if proc.stdout.strip() != b"":
                    evil_bypassed.append(f)

    errors = []
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {clean_total} clean modified: {', '.join(clean_modified)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {evil_total} evil bypassed: {', '.join(evil_bypassed)}")

    if errors:
        pytest.fail("Sanitizer failed corpus validation: " + "; ".join(errors))

    nonce = secrets.token_hex(16)
    clean_lines = [
        f'10.20.30.40 - - [11/Sep/2026:12:34:56 +0000] "GET /assets/{nonce}.css HTTP/1.1" 200 431 "-" "Verifier/{nonce}"\n'.encode(),
        f'172.16.4.9 - - [11/Sep/2026:12:34:57 +0000] "POST /api/items?tag={nonce}&page=2 HTTP/1.1" 204 0 "-" "curl/8.0"\n'.encode(),
    ]
    evil_targets = [
        f'/files/{nonce}/../secret',
        f'/files/{nonce}/%2e%2e/secret',
        f'/search?q={nonce}+UNION SELECT+password',
        f'/login?user={nonce}+OR 1=1',
        f'/search?q=<script>alert({nonce})</script>',
    ]
    evil_lines = [
        f'203.0.113.7 - - [11/Sep/2026:12:35:00 +0000] "GET {target} HTTP/1.1" 200 17 "-" "Verifier"\n'.encode()
        for target in evil_targets
    ]
    evil_lines.append(
        f'203.0.113.8 - - [11/Sep/2026:12:35:01 +0000] "GET /bad-{nonce}-'.encode()
        + b'\xff\xfe'
        + b' HTTP/1.1" 400 0 "-" "Verifier"\n'
    )

    for line in clean_lines:
        assert run_sanitizer(sanitizer_path, line) == line, "A fresh clean log line was not preserved byte-for-byte"
    for line in evil_lines:
        assert run_sanitizer(sanitizer_path, line).strip() == b'', "A fresh malicious log line was not dropped"

    mixed = clean_lines[0] + evil_lines[0] + clean_lines[1]
    assert run_sanitizer(sanitizer_path, mixed) == clean_lines[0] + clean_lines[1], \
        "The sanitizer did not filter malicious lines independently within a stream"


def test_end_to_end_nginx_ingest_redis():
    """Execute Nginx and the ingestion pipeline, then verify sanitized records reach Redis."""
    sanitizer_path = '/app/sanitizer.sh'
    ingest_path = '/app/log_ingest.sh'
    assert os.path.isfile(sanitizer_path)
    assert os.path.isfile(ingest_path)

    subprocess.run(['redis-cli', '-p', '6379', 'shutdown', 'nosave'], capture_output=True)
    time.sleep(0.3)
    redis_start = subprocess.run(['redis-server', '--port', '6379', '--daemonize', 'yes'], capture_output=True, timeout=5)
    assert redis_start.returncode == 0, redis_start.stderr.decode(errors='ignore')
    deadline = time.time() + 5
    while time.time() < deadline:
        ping = subprocess.run(['redis-cli', '-p', '6379', 'ping'], capture_output=True)
        if ping.returncode == 0 and ping.stdout.strip() == b'PONG':
            break
        time.sleep(0.1)
    else:
        pytest.fail('Redis did not start on port 6379')
    subprocess.run(['redis-cli', '-p', '6379', 'del', 'raw_logs'], capture_output=True, check=True)

    nginx_test = subprocess.run(['nginx', '-t'], capture_output=True)
    assert nginx_test.returncode == 0, nginx_test.stderr.decode(errors='ignore')
    subprocess.run(['nginx', '-s', 'stop'], capture_output=True)
    time.sleep(0.4)

    access_log = '/var/log/nginx/access.log'
    os.makedirs(os.path.dirname(access_log), exist_ok=True)
    with open(access_log, 'wb'):
        pass

    nginx_start = subprocess.run(['nginx'], capture_output=True, timeout=5)
    assert nginx_start.returncode == 0, nginx_start.stderr.decode(errors='ignore')

    ingest = subprocess.Popen(
        ['setsid', 'bash', ingest_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        time.sleep(1.0)
        curl_token = 'curl-' + secrets.token_hex(12)
        curl_proc = subprocess.run(
            ['curl', '-sS', '--max-time', '5', '-o', '/dev/null',
             f'http://127.0.0.1:8080/{curl_token}'],
            capture_output=True,
            timeout=8,
        )
        assert curl_proc.returncode == 0, f"curl to Nginx failed: {curl_proc.stderr.decode(errors='ignore')}"

        entries = wait_for_redis_token(curl_token)
        assert any(curl_token.encode() in entry for entry in entries), \
            "The Nginx request was not routed from access.log through log_ingest.sh into Redis raw_logs"

        nonce = secrets.token_hex(12)
        evil_token = 'evil-' + nonce
        clean_token = 'clean-' + nonce
        evil_line = f'198.51.100.2 - - [11/Sep/2026:12:40:00 +0000] "GET /{evil_token}/../private HTTP/1.1" 200 1 "-" "Verifier"\n'.encode()
        clean_line = f'198.51.100.3 - - [11/Sep/2026:12:40:01 +0000] "GET /{clean_token} HTTP/1.1" 200 1 "-" "Verifier"\n'.encode()
        with open(access_log, 'ab', buffering=0) as log:
            log.write(evil_line)
            log.write(clean_line)

        entries = wait_for_redis_token(clean_token)
        assert any(clean_token.encode() in entry for entry in entries), \
            "A clean line appended after a malicious line did not reach Redis"
        assert not any(evil_token.encode() in entry for entry in entries), \
            "log_ingest.sh pushed a malicious line to Redis instead of using the sanitizer output"
    finally:
        try:
            os.killpg(os.getpgid(ingest.pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            ingest.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(ingest.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        subprocess.run(['nginx', '-s', 'stop'], capture_output=True)
        subprocess.run(['redis-cli', '-p', '6379', 'shutdown', 'nosave'], capture_output=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
