#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'MOCK_EOF' > /tmp/audit_observer.py
import asyncio
import json
import sys
from aiohttp import web

port = int(sys.argv[1])
expected_token = sys.argv[2]
stats = {"audit_requests": 0, "valid_requests": 0}

async def audit(request):
    stats["audit_requests"] += 1
    if request.headers.get("Authorization") == f"Bearer {expected_token}":
        stats["valid_requests"] += 1
        return web.Response(status=200)
    return web.Response(status=403)

async def get_stats(request):
    return web.json_response(stats)

app = web.Application()
app.router.add_post('/audit', audit)
app.router.add_get('/__stats', get_stats)
web.run_app(app, host='127.0.0.1', port=port, access_log=None, print=None)
MOCK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest


def discover_service_port():
    for port in range(8000, 9001):
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}/health",
            headers={"X-Legacy-Ping": "ping"},
        )
        try:
            with urllib.request.urlopen(request, timeout=0.05) as response:
                if response.status == 200:
                    return port
        except (urllib.error.URLError, TimeoutError, OSError):
            pass
    pytest.fail("No authentication service was discovered in the required port range.")


def rotate_and_get_token(port):
    body = json.dumps({"legacy_password": "SuperSecretLegacy99"}).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/rotate",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        assert response.status == 200, "Credential rotation did not return HTTP 200."
        payload = json.loads(response.read().decode())
    assert isinstance(payload.get("new_token"), str) and payload["new_token"], \
        "Credential rotation did not return a valid new_token."
    return payload["new_token"]


def stop_original_service():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as handle:
                cmdline = handle.read().replace(b"\x00", b" ")
            if b"/app/server.py" in cmdline:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass


def wait_for_stats(port, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/__stats", timeout=0.2
            ) as response:
                return json.loads(response.read().decode())
        except (urllib.error.URLError, TimeoutError, OSError):
            time.sleep(0.02)
    pytest.fail("The audit request observer did not start or respond.")


def test_new_token_saved():
    token_path = "/home/user/new_token.txt"
    assert os.path.isfile(token_path), f"The file {token_path} is missing."

    with open(token_path, "r") as f:
        token = f.read().strip()

    expected_token = "TOK_abc123_Secure"
    assert expected_token in token, f"The file {token_path} does not contain the expected rotated token. Found: {token}"

    discovered_port = discover_service_port()
    rotated_token = rotate_and_get_token(discovered_port)
    assert token == rotated_token, \
        "new_token.txt does not exactly match the token returned by the rotation endpoint."


def test_service_config_csp():
    config_path = "/app/service_config.json"
    assert os.path.isfile(config_path), f"The file {config_path} is missing."

    with open(config_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {config_path} does not contain valid JSON.")

    assert "csp" in data, "The 'csp' key is missing from the JSON root in /app/service_config.json."

    expected_csp = "default-src 'self'; script-src 'none'; object-src 'none';"
    assert data["csp"] == expected_csp, f"The 'csp' value is incorrect. Expected: {expected_csp}, Got: {data['csp']}"


def test_fast_audit_performance():
    script_path = "/home/user/fast_audit.py"
    assert os.path.isfile(script_path), f"The auditing script {script_path} is missing."

    token_path = "/home/user/new_token.txt"
    discovered_port = discover_service_port()
    with open(token_path, "rb") as handle:
        original_token_contents = handle.read()

    challenge_token = "VERIFY_" + secrets.token_urlsafe(24)
    observer = None
    try:
        stop_original_service()
        time.sleep(0.2)

        with open(token_path, "w") as handle:
            handle.write(challenge_token)

        observer = subprocess.Popen(
            ["python3", "/tmp/audit_observer.py", str(discovered_port), challenge_token],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        wait_for_stats(discovered_port)

        start = time.time()
        result = subprocess.run(
            ["python3", script_path], capture_output=True, text=True, timeout=10
        )
        end = time.time()
        duration = end - start

        assert result.returncode == 0, f"The script {script_path} failed to execute. Error: {result.stderr}"
        assert "5000" in result.stdout, f"The script did not output '5000' indicating successful responses. Output: {result.stdout}"

        stats = wait_for_stats(discovered_port)
        assert stats["audit_requests"] == 5000, \
            f"Expected exactly 5000 POST requests to /audit, observed {stats['audit_requests']}."
        assert stats["valid_requests"] == 5000, \
            f"Only {stats['valid_requests']} of 5000 audit requests used the token from new_token.txt."

        threshold = 2.0
        assert duration <= threshold, f"Performance test failed: Execution time was {duration:.2f} seconds, which exceeds the threshold of {threshold} seconds."
    finally:
        with open(token_path, "wb") as handle:
            handle.write(original_token_contents)
        if observer is not None:
            observer.terminate()
            try:
                observer.wait(timeout=2)
            except subprocess.TimeoutExpired:
                observer.kill()
                observer.wait()
        subprocess.Popen(
            ["python3", "/app/server.py"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
