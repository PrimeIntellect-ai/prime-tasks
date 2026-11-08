#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import pytest


def test_nginx_config_fixed():
    conf_path = "/app/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config not found at {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8081;" in content, "Nginx config not correctly updated to proxy to 127.0.0.1:8081."
    proc = subprocess.run(
        ["nginx", "-t", "-c", conf_path], text=True, capture_output=True, timeout=10
    )
    assert proc.returncode == 0, f"Nginx configuration is invalid: {proc.stderr}"


def test_backend_env_fixed():
    env_path = "/app/backend/.env"
    assert os.path.isfile(env_path), f"Backend .env not found at {env_path}"
    with open(env_path, "r") as f:
        content = f.read()
    assert "REDIS_URL=redis://127.0.0.1:6379" in content, "Backend .env not correctly updated to point to local Redis."
    active = []
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            if key.strip() == "REDIS_URL":
                active.append(value.strip().strip("\"'"))
    assert active == ["redis://127.0.0.1:6379"], "REDIS_URL must be an active, unambiguous local Redis setting."


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def get_without_redirect(url):
    opener = urllib.request.build_opener(NoRedirectHandler())
    try:
        response = opener.open(url, timeout=5)
        return response.status, response.getheader("Location")
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Location")


def test_redis_is_running():
    proc = subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "ping"],
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert proc.returncode == 0 and proc.stdout.strip() == "PONG", "Redis is not running on 127.0.0.1:6379."


def test_end_to_end_flow():
    try:
        status, location = get_without_redirect(
            "http://127.0.0.1:8080/api/login?redirect=http://example.com"
        )
    except Exception as e:
        pytest.fail(f"Failed to perform end-to-end request. Are the services running? Error: {e}")

    assert status == 302, f"Expected HTTP 302 Found, got {status}"
    assert location == "http://example.com", f"Expected Location header 'http://example.com', got '{location}'"


def test_services_handle_unseen_redirects_through_nginx_and_backend():
    token = secrets.token_hex(10)
    redirects = [
        f"https://example.org/continue/{token}?state={secrets.token_hex(5)}",
        f"/dashboard/{token}?next=profile",
        f"https://myapp.com/session/{secrets.token_hex(8)}",
    ]
    for redirect in redirects:
        query = urllib.parse.urlencode({"redirect": redirect})
        for port in (8081, 8080):
            try:
                status, location = get_without_redirect(
                    f"http://127.0.0.1:{port}/api/login?{query}"
                )
            except Exception as e:
                pytest.fail(f"Service on port {port} did not handle a login request: {e}")
            assert status == 302, f"Service on port {port} returned {status}, expected 302"
            assert location == redirect, f"Service on port {port} returned incorrect Location {location!r}"


def test_waf_filter_binary_exists():
    binary_path = "/home/user/waf_filter/target/release/waf_filter"
    assert os.path.isfile(binary_path), f"WAF filter binary not found at {binary_path}. Did you compile with --release?"
    assert os.access(binary_path, os.X_OK), f"WAF filter binary at {binary_path} is not executable"


def test_waf_filter_corpus():
    binary_path = "/home/user/waf_filter/target/release/waf_filter"
    if not os.path.isfile(binary_path):
        pytest.skip("WAF filter binary not found, skipping corpus test.")

    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"
    evil_failed = []
    clean_failed = []
    evil_total = 0
    clean_total = 0

    for root, _, files in os.walk(evil_dir):
        for file in files:
            file_path = os.path.join(root, file)
            with open(file_path, "r") as f:
                urls = f.read().splitlines()
            for url in urls:
                if not url.strip():
                    continue
                evil_total += 1
                proc = subprocess.run([binary_path], input=url.strip(), text=True, capture_output=True)
                output = proc.stdout.strip()
                if output != "EVIL":
                    evil_failed.append((file, url, output))

    for root, _, files in os.walk(clean_dir):
        for file in files:
            file_path = os.path.join(root, file)
            with open(file_path, "r") as f:
                urls = f.read().splitlines()
            for url in urls:
                if not url.strip():
                    continue
                clean_total += 1
                proc = subprocess.run([binary_path], input=url.strip(), text=True, capture_output=True)
                output = proc.stdout.strip()
                if output != "CLEAN":
                    clean_failed.append((file, url, output))

    error_msg = []
    if evil_failed:
        offending_files = ", ".join(set(f[0] for f in evil_failed))
        error_msg.append(f"{len(evil_failed)} of {evil_total} evil bypassed. Offending files: {offending_files}")
    if clean_failed:
        offending_files = ", ".join(set(f[0] for f in clean_failed))
        error_msg.append(f"{len(clean_failed)} of {clean_total} clean modified/rejected. Offending files: {offending_files}")
    if error_msg:
        pytest.fail(" | ".join(error_msg))


def test_waf_filter_unseen_generated_cases():
    binary_path = "/home/user/waf_filter/target/release/waf_filter"
    token = secrets.token_hex(12)
    host = token + ".invalid"
    octet = secrets.randbelow(200) + 2
    decimal_loopback = 2130706432 + octet
    hex_loopback = f"0x7f0000{octet:02x}"

    clean = [
        f"https://myapp.com/dashboard/{token}",
        f"https://myapp.com/settings/profile?state={token}",
        f"/account/{token}",
        f"/settings/profile?tab={token}",
        f"https://expected-domain.com/continue/{token}",
    ]
    evil = [
        f"http://169.254.169.254/latest/meta-data/{token}",
        f"http://2852039166/latest/{token}",
        f"http://0xa9fea9fe/latest/{token}",
        f"http://127.0.0.{octet}/{token}",
        f"http://{decimal_loopback}/{token}",
        f"http://{hex_loopback}/{token}",
        f"http://0177.0.0.{octet}/{token}",
        f"http://localhost/{token}",
        f"http://[::1]/{token}",
        f"https://expected-domain.com@{host}/{token}",
        f"//{host}/{token}",
        f"file:///etc/passwd#{token}",
        f"gopher://127.0.0.1:6379/_{token}",
        f"dict://127.0.0.1:6379/{token}",
        f"javascript:location='https://{host}/{token}'",
    ]

    cases = [(url, "CLEAN") for url in clean] + [(url, "EVIL") for url in evil]
    # Shuffle with runtime entropy so a program cannot rely on input position.
    for i in range(len(cases) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        cases[i], cases[j] = cases[j], cases[i]

    proc = subprocess.run(
        [binary_path],
        input="\n".join(url for url, _ in cases) + "\n",
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"WAF exited with status {proc.returncode}: {proc.stderr}"
    outputs = proc.stdout.splitlines()
    assert len(outputs) == len(cases), "WAF must emit exactly one output line per input URL."
    for (url, expected), actual in zip(cases, outputs):
        assert actual == expected, f"Expected {expected} for unseen URL {url!r}, got {actual!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
