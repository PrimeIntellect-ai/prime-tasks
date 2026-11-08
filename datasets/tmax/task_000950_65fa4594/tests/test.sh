#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import re
import socket
import time
import urllib.error
import urllib.request
import pytest

GENERATED_LOG_OFFSET = 0


def b64url(value):
    raw = json.dumps(value, separators=(",", ":"), sort_keys=True).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def make_token(header, payload):
    # A nonempty signature is sufficient here: the required policy is based on
    # algorithm/key type and issuer integrity, and no verification key is supplied.
    return f"{b64url(header)}.{b64url(payload)}.c2ln"


def request_token(token, cookie=False, url="http://127.0.0.1:80/api/data"):
    req = urllib.request.Request(url)
    if cookie:
        req.add_header("Cookie", f"session_token={token}")
    else:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            return resp.getcode(), resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def assert_json_success(status, body):
    assert status == 200
    parsed = json.loads(body.decode())
    assert parsed.get("status") == "success"
    assert parsed.get("data") == "dummy"


def test_required_artifacts_and_configuration():
    required = [
        "/home/user/waf/waf.py",
        "/home/user/nginx/nginx.conf",
        "/home/user/api/app.py",
        "/home/user/start_services.sh",
    ]
    for path in required:
        assert os.path.isfile(path), f"Missing required artifact: {path}"
        assert os.path.getsize(path) > 0, f"Required artifact is empty: {path}"

    with open("/home/user/nginx/nginx.conf", encoding="utf-8") as f:
        nginx = f.read()
    assert re.search(r"\blisten\s+80(?:\s|;)", nginx), "Nginx must listen on port 80"
    assert re.search(r"\blocation\s+(?:\^~\s+)?/api/", nginx), "Nginx must configure /api/"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:8080(?:[/;\s])", nginx), \
        "Nginx /api/ traffic must proxy to the WAF at 127.0.0.1:8080"

    with open("/home/user/api/app.py", encoding="utf-8") as f:
        app_source = f.read().lower()
    compact_app = re.sub(r"\s+", "", app_source)
    assert "redis" in app_source, "Flask app is not configured to use Redis"
    assert "127.0.0.1" in compact_app and "6379" in compact_app, \
        "Flask Redis connection must target 127.0.0.1:6379"

    with open("/home/user/waf/waf.py", encoding="utf-8") as f:
        waf_source = f.read()
    assert "/home/user/data/valid_issuers.sha256" in waf_source, \
        "WAF must use the issuer integrity file"
    assert not re.search(r"^\s*(?:from\s+jwt\s+import|import\s+jwt\b)", waf_source, re.MULTILINE), \
        "JWT inspection must not rely on PyJWT"

    with open("/home/user/start_services.sh", encoding="utf-8") as f:
        startup = f.read().lower()
    for marker in ("redis", "flask", "waf", "nginx"):
        assert marker in startup, f"Startup script does not start {marker}"

    syntax_status = os.system("bash -n /home/user/start_services.sh")
    assert syntax_status == 0, "Startup script has invalid shell syntax"

    expected_hashes = {
        hashlib.sha256(b"trusted-corp.com").hexdigest(),
        hashlib.sha256(b"internal-auth.net").hexdigest(),
    }
    with open("/home/user/data/valid_issuers.sha256", encoding="utf-8") as f:
        configured_hashes = {line.strip().lower() for line in f if line.strip()}
    assert expected_hashes.issubset(configured_hashes), "Required valid issuer hashes are missing"


def test_waf_behavior():
    global GENERATED_LOG_OFFSET

    evil_tokens_path = "/home/user/test_data/evil_tokens.json"
    clean_tokens_path = "/home/user/test_data/clean_tokens.json"

    assert os.path.exists(evil_tokens_path), f"Missing evil corpus at {evil_tokens_path}"
    assert os.path.exists(clean_tokens_path), f"Missing clean corpus at {clean_tokens_path}"

    with open(evil_tokens_path, 'r') as f:
        evil_tokens = json.load(f)

    with open(clean_tokens_path, 'r') as f:
        clean_tokens = json.load(f)

    evil_bypassed = []
    clean_modified = []

    # Preserve evaluation of any image-provided corpus.
    for idx, token in enumerate(evil_tokens):
        req = urllib.request.Request("http://127.0.0.1:80/api/data")
        req.add_header("Authorization", f"Bearer {token}")
        try:
            urllib.request.urlopen(req, timeout=2)
            evil_bypassed.append(f"evil_token_{idx}")
        except urllib.error.HTTPError as e:
            if e.code != 403:
                evil_bypassed.append(f"evil_token_{idx} (got {e.code} instead of 403)")
        except Exception as e:
            evil_bypassed.append(f"evil_token_{idx} (unexpected error {e})")

    for idx, token in enumerate(clean_tokens):
        req = urllib.request.Request("http://127.0.0.1:80/api/data")
        req.add_header("Authorization", f"Bearer {token}")
        try:
            resp = urllib.request.urlopen(req, timeout=2)
            if resp.getcode() != 200:
                clean_modified.append(f"clean_token_{idx} (got {resp.getcode()} instead of 200)")
        except urllib.error.HTTPError as e:
            clean_modified.append(f"clean_token_{idx} (got HTTPError {e.code})")
        except Exception as e:
            clean_modified.append(f"clean_token_{idx} (unexpected error {e})")

    err_msg = []
    if evil_bypassed:
        err_msg.append(f"{len(evil_bypassed)} of {len(evil_tokens)} evil bypassed: {evil_bypassed}")
    if clean_modified:
        err_msg.append(f"{len(clean_modified)} of {len(clean_tokens)} clean modified: {clean_modified}")
    if err_msg:
        pytest.fail(" | ".join(err_msg))

    log_file = "/home/user/logs/waf_blocks.log"
    GENERATED_LOG_OFFSET = os.path.getsize(log_file) if os.path.exists(log_file) else 0
    nonce = os.urandom(12).hex()
    trusted = {"iss": "trusted-corp.com", "nonce": nonce}

    generated_evil = [
        (make_token({"alg": "none", "typ": "JWT"}, trusted), False, "alg_none"),
        (make_token({"alg": "None", "typ": "JWT"}, trusted), False, "alg_none"),
        (make_token({"alg": "NONE", "typ": "JWT"}, trusted), True, "alg_none"),
        (make_token({"alg": "", "typ": "JWT"}, trusted), False, "alg_none"),
        (make_token({"alg": "RS256", "typ": "JWT"}, {"iss": "attacker.example", "nonce": nonce}), True, "invalid_issuer"),
        (make_token({"alg": "HS256", "typ": "JWT", "jwk": {"kty": "RSA", "n": "cHVibGljLWtleQ", "e": "AQAB"}}, trusted), False, "key_confusion"),
    ]

    for token, via_cookie, reason in generated_evil:
        status, _ = request_token(token, cookie=via_cookie)
        assert status == 403, f"Generated {reason} token was not rejected through Nginx (got {status})"

    clean_auth = make_token({"alg": "RS256", "typ": "JWT"}, trusted)
    clean_cookie = make_token({"alg": "RS256", "typ": "JWT"}, {"iss": "internal-auth.net", "nonce": nonce})
    assert_json_success(*request_token(clean_auth, cookie=False))
    assert_json_success(*request_token(clean_cookie, cookie=True))

    # Exercise the WAF directly as well as through Nginx, proving port 8080 is
    # the HTTP proxy rather than an unrelated listener.
    assert_json_success(*request_token(clean_auth, url="http://127.0.0.1:8080/api/data"))


def test_waf_logging():
    log_file = "/home/user/logs/waf_blocks.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist. The WAF must log rejected requests."

    with open(log_file, 'r') as f:
        content = f.read()

    assert "REJECTED: IP=" in content, "WAF blocks log does not contain the required 'REJECTED: IP=' format."
    assert "REASON=" in content, "WAF blocks log does not contain the required 'REASON=' format."

    deadline = time.time() + 2
    fresh = content[GENERATED_LOG_OFFSET:]
    while time.time() < deadline and not all(f"REASON={r}" in fresh for r in ("alg_none", "invalid_issuer", "key_confusion")):
        time.sleep(0.1)
        with open(log_file, encoding="utf-8") as f:
            fresh = f.read()[GENERATED_LOG_OFFSET:]

    for reason in ("alg_none", "invalid_issuer", "key_confusion"):
        assert f"REASON={reason}" in fresh, f"Generated rejection was not logged with REASON={reason}"

    matching = [line for line in fresh.splitlines() if "REJECTED:" in line]
    assert matching, "No fresh rejection log entries were produced by the generated requests"
    pattern = re.compile(r"^\[[^\]\n]+\] REJECTED: IP=[^\s]+ REASON=(alg_none|invalid_issuer|key_confusion)$")
    assert all(pattern.match(line) for line in matching), "Fresh rejection entries do not use the required format"


def test_services_running():
    services = {
        "Nginx": 80,
        "WAF": 8080,
        "Flask": 5000,
        "Redis": 6379
    }

    for name, port in services.items():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            result = s.connect_ex(('127.0.0.1', port))
            assert result == 0, f"Service {name} is not listening on port {port}."

    # Verify that port 6379 is Redis rather than merely an open socket.
    with socket.create_connection(("127.0.0.1", 6379), timeout=2) as s:
        s.sendall(b"*1\r\n$4\r\nPING\r\n")
        reply = s.recv(64)
    assert reply.startswith(b"+PONG"), f"Port 6379 did not answer as Redis: {reply!r}"

    # Verify the Flask backend itself remains functional.
    with urllib.request.urlopen("http://127.0.0.1:5000/api/data", timeout=2) as resp:
        assert_json_success(resp.getcode(), resp.read())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
