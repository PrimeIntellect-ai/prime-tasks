#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

START_SCRIPT = "/app/start.sh"
EXPECTED_START_SCRIPT = """#!/bin/bash
cd /app
python3 app.py &
sleep 2
nginx -c /app/nginx.conf
"""


def stop_services():
    subprocess.run(["pkill", "-TERM", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-f", "python3 app.py"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.5)


def fetch(url, host=None):
    headers = {"Host": host} if host is not None else {}
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=3)


def wait_for_http(url, attempts=30):
    last_error = None
    for _ in range(attempts):
        try:
            with fetch(url) as response:
                return response.status
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Service did not become ready at {url}: {last_error}")


def test_part1_nginx_flask_integration():
    assert os.path.isfile(START_SCRIPT), f"{START_SCRIPT} is missing"
    with open(START_SCRIPT, "r", encoding="utf-8") as f:
        assert f.read() == EXPECTED_START_SCRIPT, "/app/start.sh must not be replaced or modified"

    stop_services()
    subprocess.run([START_SCRIPT], check=True, timeout=15)
    time.sleep(2)

    try:
        req = urllib.request.Request("http://127.0.0.1:8080/login")
        with urllib.request.urlopen(req, timeout=3) as response:
            assert response.getcode() == 200, "Expected HTTP 200 for /login"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to access /login: {e}")

    try:
        req = urllib.request.Request("http://127.0.0.1:8080/admin")
        with urllib.request.urlopen(req, timeout=3):
            pytest.fail("Expected HTTP 403 for /admin, but got success")
    except urllib.error.HTTPError as e:
        assert e.code == 403, f"Expected HTTP 403 for /admin, got {e.code}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to access /admin: {e}")
    finally:
        stop_services()


def test_part1_all_paths_are_proxied_and_host_is_preserved():
    token = secrets.token_hex(16)
    random_path = "/verify-" + secrets.token_hex(12) + "?q=" + secrets.token_hex(5)
    requested_host = "host-" + secrets.token_hex(8) + ".local:8080"
    observations = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            observations.append((self.path, self.headers.get("Host")))
            body = (token + "|" + self.path).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    class ReusableServer(ThreadingHTTPServer):
        allow_reuse_address = True

    stop_services()
    server = ReusableServer(("127.0.0.1", 5000), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    nginx = subprocess.Popen(
        ["nginx", "-c", "/app/nginx.conf", "-g", "daemon off;"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        last_error = None
        for _ in range(30):
            if nginx.poll() is not None:
                pytest.fail("Nginx failed to start: " + nginx.stderr.read())
            try:
                with fetch("http://127.0.0.1:8080" + random_path, requested_host) as response:
                    body = response.read().decode()
                    assert response.status == 200
                    assert body == token + "|" + random_path
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        else:
            pytest.fail(f"Random path was not proxied through Nginx: {last_error}")

        with fetch("http://127.0.0.1:8080/", requested_host) as response:
            assert response.read().decode() == token + "|/"

        assert (random_path, requested_host) in observations, "Nginx did not preserve the Host header"
        assert ("/", requested_host) in observations, "The root request was not proxied"

        try:
            with fetch("http://127.0.0.1:8080/admin", requested_host):
                pytest.fail("Expected Nginx to return 403 for /admin")
        except urllib.error.HTTPError as e:
            assert e.code == 403
        assert not any(path == "/admin" for path, _ in observations), "/admin reached the upstream"
    finally:
        nginx.terminate()
        try:
            nginx.wait(timeout=3)
        except subprocess.TimeoutExpired:
            nginx.kill()
            nginx.wait(timeout=3)
        server.shutdown()
        server.server_close()
        stop_services()


def test_part2_url_filter_script():
    script_path = "/home/user/url_filter.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No evil corpus files found"
    assert len(clean_files) > 0, "No clean corpus files found"

    evil_bypassed = []
    clean_modified = []
    for evil_file in evil_files:
        result = subprocess.run([script_path, evil_file], capture_output=True, text=True)
        if result.stdout.strip():
            evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        with open(clean_file, "r", encoding="utf-8") as f:
            expected_output = f.read().strip()
        result = subprocess.run([script_path, clean_file], capture_output=True, text=True)
        if result.stdout.strip() != expected_output:
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))

    nonce = secrets.token_hex(10)
    safe = [
        "/dashboard-" + nonce,
        "/profile/" + nonce + "?user=" + secrets.token_hex(4),
        "https://myapp.local/settings/" + nonce,
        "https://myapp.local/?v=" + secrets.token_hex(5),
    ]
    evil_domain = secrets.token_hex(8) + ".example"
    evil = [
        "http://" + evil_domain + "/" + nonce,
        "https://" + evil_domain + "/login/" + nonce,
        "https://myapp.local." + evil_domain + "/" + nonce,
        "//" + evil_domain + "/" + nonce,
        "javascript:alert('" + nonce + "')",
        "data:text/plain," + nonce,
        "http://myapp.local/" + nonce,
        "https://myapp.local@" + evil_domain + "/" + nonce,
    ]

    mixed = [(value, True) for value in safe] + [(value, False) for value in evil]
    random.SystemRandom().shuffle(mixed)
    expected = [value for value, is_safe in mixed if is_safe]

    with tempfile.TemporaryDirectory(prefix="url-verification-", dir="/var/tmp") as directory:
        input_path = os.path.join(directory, secrets.token_hex(8) + ".txt")
        with open(input_path, "w", encoding="utf-8") as f:
            f.write("\n".join(value for value, _ in mixed) + "\n")
        result = subprocess.run([script_path, input_path], capture_output=True, text=True, timeout=10)

    assert result.returncode == 0, f"Filter exited with status {result.returncode}: {result.stderr}"
    assert result.stdout.splitlines() == expected, (
        "Filter did not preserve exactly the safe URLs from a randomized mixed corpus"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
