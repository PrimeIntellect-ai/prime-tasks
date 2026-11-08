#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import string
import subprocess
import time
import urllib.request


def test_admin_password_cracked():
    path = "/home/user/admin_password.txt"
    assert os.path.isfile(path), f"Missing password file at {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "apple", "The cracked password is incorrect."


def test_nginx_config_updated():
    path = "/app/nginx/nginx.conf"
    assert os.path.isfile(path), f"Missing Nginx config at {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:5000/;" in content or "proxy_pass http://localhost:5000/;" in content, "Nginx config does not contain the correct proxy_pass directive."


def test_flask_config_updated():
    path = "/app/flask/config.py"
    assert os.path.isfile(path), f"Missing Flask config at {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "os.environ.get" in content and "AUTH_SECRET" in content, "Flask config does not read SECRET_KEY from the AUTH_SECRET environment variable."


def _nginx_is_running():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/comm", "r") as f:
                if f.read().strip() == "nginx":
                    return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return False


def _fetch_json(url):
    last_error = None
    for _ in range(10):
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                assert response.status == 200
                return json.loads(response.read().decode("utf-8"))
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)
    raise AssertionError(f"Could not reach {url}: {last_error}")


def test_services_are_running_and_proxying():
    assert _nginx_is_running(), "Nginx is not running"

    direct = _fetch_json("http://127.0.0.1:5000/")
    proxied = _fetch_json("http://127.0.0.1:8080/auth/")

    assert isinstance(direct.get("token"), str) and direct["token"], "Flask did not return a JWT token"
    assert isinstance(proxied.get("token"), str) and proxied["token"], "Nginx did not proxy /auth/ to Flask"


def expected_permission(token, resource):
    token_sum = sum(int(token[i:i + 2], 16) for i in range(0, 16, 2))
    resource_sum = sum(ord(c) for c in resource)
    return "ALLOW" if abs(token_sum - resource_sum) % 7 == 0 else "DENY"


def test_perm_check_equivalence():
    agent_script = "/home/user/perm_check.py"
    assert os.path.isfile(agent_script), f"Missing agent script at {agent_script}"

    with open(agent_script, "rb") as f:
        assert f.readline() == b"#!/usr/bin/env python3\n", "perm_check.py has the wrong shebang"

    random.seed(42)

    for _ in range(5000):
        token = ''.join(random.choices(string.hexdigits.lower(), k=16))
        res_len = random.randint(4, 12)
        resource = ''.join(random.choices(string.ascii_letters + string.digits, k=res_len))
        expected = expected_permission(token, resource)

        agent_res = subprocess.run(
            ["python3", agent_script, token, resource],
            capture_output=True,
            text=True,
            timeout=5,
        )
        agent_out = agent_res.stdout.strip()

        assert agent_res.returncode == 0, f"Agent exited with status {agent_res.returncode} on token='{token}', resource='{resource}'"
        assert agent_out == expected, f"Mismatch on input token='{token}', resource='{resource}'. Expected: '{expected}', Agent: '{agent_out}'"
        assert agent_res.stdout == expected + "\n", f"Output must be exactly {expected!r} followed by one newline"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
