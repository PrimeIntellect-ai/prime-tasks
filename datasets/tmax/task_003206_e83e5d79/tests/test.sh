#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import importlib.util
import os
import secrets
import ssl
import string
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest


def load_token_generator():
    loader = importlib.machinery.SourcelessFileLoader(
        "verifier_token_oracle", "/app/bin/token_generator.pyc"
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module.generate_token


GENERATE_TOKEN = load_token_generator()


def random_label(length=18):
    alphabet = string.ascii_lowercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def run_filter(token):
    path = None
    try:
        with tempfile.NamedTemporaryFile("w", delete=False, prefix="token-test-") as f:
            f.write(token)
            path = f.name
        return subprocess.run(
            ["python3", "/home/user/filter.py", path],
            capture_output=True,
            timeout=5,
        )
    finally:
        if path and os.path.exists(path):
            os.unlink(path)


def request_status(token):
    cmd = [
        "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
        "--key", "/app/certs/client.key",
        "--cert", "/app/certs/client.crt",
        "--cacert", "/app/certs/ca.crt",
        "--get", "--data-urlencode", f"token={token}",
        "https://127.0.0.1:8443/login",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def test_filter_script_exists():
    assert os.path.isfile('/home/user/filter.py'), "/home/user/filter.py is missing"


def test_corpus_validation():
    clean_dir = '/app/corpus/clean/'
    evil_dir = '/app/corpus/evil/'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for f in clean_files:
        result = subprocess.run(['python3', '/home/user/filter.py', f], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(f))

    evil_failed = []
    for f in evil_files:
        result = subprocess.run(['python3', '/home/user/filter.py', f], capture_output=True)
        if result.returncode == 0:
            evil_failed.append(os.path.basename(f))

    error_msgs = []
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")

    assert not error_msgs, " | ".join(error_msgs)


def test_filter_on_fresh_randomized_tokens():
    clean_urls = [
        f"https://internal.corp.local/{random_label()}/{random_label(10)}?id={random_label(12)}"
        for _ in range(12)
    ]
    evil_urls = []
    for _ in range(6):
        evil_urls.extend([
            f"http://{random_label()}.attacker.invalid/{random_label()}",
            f"https://{random_label()}.example.net/{random_label()}",
            f"https://internal.corp.local.{random_label()}.invalid/{random_label()}",
            f"https://internal.corp.local{random_label()}/{random_label()}",
            f"https://INTERNAL.corp.local/{random_label()}",
        ])

    for url in clean_urls:
        result = run_filter(GENERATE_TOKEN(url))
        assert result.returncode == 0, f"Fresh valid internal URL was rejected: {url!r}"

    for url in evil_urls:
        result = run_filter(GENERATE_TOKEN(url))
        assert result.returncode == 1, f"Fresh non-internal URL was accepted: {url!r}"

    malformed = [
        "",
        secrets.token_hex(10) + "z",
        secrets.token_hex(10) + "f",
        "not-hex-" + random_label(),
    ]
    for token in malformed:
        result = run_filter(token)
        assert result.returncode == 1, f"Malformed token was not rejected: {token!r}"


def test_nginx_mtls_and_flask_integration():
    # Test 1: No client cert -> should fail
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        urllib.request.urlopen("https://127.0.0.1:8443/login?token=dummy", context=ctx, timeout=5)
        pytest.fail("Nginx accepted connection without client certificate")
    except urllib.error.HTTPError as e:
        assert e.code == 400, f"Expected HTTP 400 for missing client cert, got {e.code}"
    except urllib.error.URLError:
        pass

    # Test 2: Valid client cert, clean token -> should redirect (302)
    url = "https://internal.corp.local/dashboard"
    key = "N3tw0rkS3cur1tyK3y"
    encrypted = bytes(ord(url[i]) ^ ord(key[i % len(key)]) for i in range(len(url))).hex()

    curl_cmd_valid = [
        "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
        "--key", "/app/certs/client.key",
        "--cert", "/app/certs/client.crt",
        "--cacert", "/app/certs/ca.crt",
        f"https://127.0.0.1:8443/login?token={encrypted}"
    ]

    result = subprocess.run(curl_cmd_valid, capture_output=True, text=True)
    assert result.stdout.strip() in ["302", "301"], f"Expected redirect (302) for valid token, got HTTP {result.stdout.strip()}"

    # Test 3: Valid client cert, evil token -> should be 403 Forbidden
    evil_url = "http://evil.attacker.com/phish"
    encrypted_evil = bytes(ord(evil_url[i]) ^ ord(key[i % len(key)]) for i in range(len(evil_url))).hex()

    curl_cmd_evil = [
        "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
        "--key", "/app/certs/client.key",
        "--cert", "/app/certs/client.crt",
        "--cacert", "/app/certs/ca.crt",
        f"https://127.0.0.1:8443/login?token={encrypted_evil}"
    ]

    result_evil = subprocess.run(curl_cmd_evil, capture_output=True, text=True)
    assert result_evil.stdout.strip() == "403", f"Expected 403 Forbidden for evil token, got HTTP {result_evil.stdout.strip()}"


def test_flask_integration_on_fresh_randomized_tokens():
    for _ in range(8):
        clean_url = f"https://internal.corp.local/{random_label()}/{random_label()}"
        assert request_status(GENERATE_TOKEN(clean_url)) in ["301", "302"]

        evil_url = f"https://internal.corp.local.{random_label()}.invalid/{random_label()}"
        assert request_status(GENERATE_TOKEN(evil_url)) == "403"

        external_url = f"https://{random_label()}.example.org/{random_label()}"
        assert request_status(GENERATE_TOKEN(external_url)) == "403"

    assert request_status("invalid-" + random_label()) == "403"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
