#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import stat
import json
import base64
import hmac
import hashlib
import time
import subprocess
import importlib.util
from urllib.parse import quote

import pytest

VENDORED = "/app/pyjwt-2.4.0"
SECRET = "supersecret_key_123"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_token(payload, alg="HS256", secret=SECRET):
    header = {"alg": alg, "typ": "JWT"}
    head = b64url(json.dumps(header, separators=(",", ":")).encode())
    body = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = (head + "." + body).encode("ascii")
    if alg == "none":
        signature = ""
    else:
        signature = b64url(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
    return head + "." + body + "." + signature


def load_app_module():
    sys.path.insert(0, VENDORED)
    spec = importlib.util.spec_from_file_location("verified_server_app", "/app/server/app.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_vendored_jwt():
    for name in list(sys.modules):
        if name == "jwt" or name.startswith("jwt."):
            del sys.modules[name]
    sys.path.insert(0, VENDORED)
    import jwt
    assert os.path.realpath(jwt.__file__).startswith(os.path.realpath(VENDORED) + os.sep)
    return jwt


def test_security_score_metric():
    result = subprocess.run(
        ["python3", "/app/tester/run_tests.py", "--score-only"],
        capture_output=True, text=True, check=True
    )
    try:
        score = float(result.stdout.strip())
    except ValueError:
        pytest.fail(f"Testing script did not output a numeric score: {result.stdout!r}")
    assert score >= 100


def test_open_redirect_is_fixed_behaviorally():
    module = load_app_module()
    client = module.app.test_client()

    for target in (None, "https://evil.example/x", "http://evil.example/x", "//evil.example/x", "javascript:alert(1)", "ftp://evil.example/x", "dashboard"):
        url = "/login" if target is None else "/login?next=" + quote(target, safe="")
        response = client.get(url, follow_redirects=False)
        assert response.status_code in (301, 302, 303, 307, 308)
        assert response.headers.get("Location") == "/dashboard", (target, response.headers.get("Location"))

    for target in ("/", "/dashboard", "/account?tab=security"):
        response = client.get("/login?next=" + quote(target, safe=""), follow_redirects=False)
        assert response.status_code in (301, 302, 303, 307, 308)
        assert response.headers.get("Location") == target


def test_none_algorithm_rejected_with_key():
    jwt = load_vendored_jwt()
    token = make_token({"user": "attacker", "exp": int(time.time()) + 3600}, alg="none")
    with pytest.raises(Exception):
        jwt.decode(token, SECRET, algorithms=["HS256"])
    with pytest.raises(Exception):
        jwt.decode(token, SECRET, algorithms=["none", "HS256"])


def test_normal_signature_and_expiry_validation_still_work():
    jwt = load_vendored_jwt()
    valid = make_token({"user": "alice", "exp": int(time.time()) + 3600})
    assert jwt.decode(valid, SECRET, algorithms=["HS256"])["user"] == "alice"

    bad_signature = make_token({"user": "mallory", "exp": int(time.time()) + 3600}, secret="wrong-secret")
    with pytest.raises(Exception):
        jwt.decode(bad_signature, SECRET, algorithms=["HS256"])

    expired = make_token({"user": "old", "exp": int(time.time()) - 3600})
    with pytest.raises(Exception):
        jwt.decode(expired, SECRET, algorithms=["HS256"])


def test_analyze_logs_exists_and_functions_on_derived_fixture():
    script = "/home/user/analyze_logs.py"
    log_path = "/app/logs/access.log"
    output_path = "/home/user/valid_tokens_count.txt"
    assert os.path.isfile(script), f"Missing {script}"

    now = int(time.time())
    valid_auth = make_token({"user": "auth", "exp": now + 3600})
    valid_query = make_token({"user": "query", "exp": now + 7200})
    expired = make_token({"user": "expired", "exp": now - 3600})
    bad_signature = make_token({"user": "bad", "exp": now + 3600}, secret="not-the-server-secret")
    none_token = make_token({"user": "none", "exp": now + 3600}, alg="none")
    fixture = (
        f'GET /api/protected HTTP/1.1 Authorization: Bearer {valid_auth}\n'
        f'GET /callback?token={valid_query}&x=1 HTTP/1.1\n'
        f'Authorization: Bearer {expired}\n'
        f'GET /?token={bad_signature} HTTP/1.1 Authorization: Bearer {none_token}\n'
        'irrelevant line without a token\n'
    )

    with open(log_path, "rb") as f:
        original_log = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    try:
        with open(log_path, "w") as f:
            f.write(fixture)
        if os.path.exists(output_path):
            os.unlink(output_path)
        result = subprocess.run([sys.executable, script], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(output_path), "Analyzer did not create its output file"
        with open(output_path) as f:
            content = f.read()
        assert content.strip() == "2", f"Expected analyzer count 2, got {content!r}"
        assert content.strip().isdigit(), "Output must be a plain integer"
    finally:
        with open(log_path, "wb") as f:
            f.write(original_log)
        if original_output is None:
            if os.path.exists(output_path):
                os.unlink(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)


def test_valid_tokens_count_for_shipped_log():
    log_path = "/app/logs/access.log"
    output_path = "/home/user/valid_tokens_count.txt"
    assert os.path.isfile(log_path)
    assert os.path.isfile(output_path)
    jwt = load_vendored_jwt()
    import re
    pattern = re.compile(r'(?:Authorization:\s*Bearer\s+|token=)([A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]*)')
    count = 0
    with open(log_path) as f:
        for token in pattern.findall(f.read()):
            try:
                jwt.decode(token, SECRET, algorithms=["HS256"])
                count += 1
            except Exception:
                pass
    with open(output_path) as f:
        content = f.read().strip()
    assert content and content.isdigit()
    assert int(content) == count


def test_file_permissions():
    assert os.path.isdir("/app/logs")
    assert os.path.isfile("/app/logs/access.log")
    assert stat.S_IMODE(os.stat("/app/logs").st_mode) == 0o700
    assert stat.S_IMODE(os.stat("/app/logs/access.log").st_mode) == 0o600
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
