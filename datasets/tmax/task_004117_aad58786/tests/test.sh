#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import subprocess
from collections import Counter

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"


def get_no_redirect(path, **kwargs):
    try:
        return requests.get(BASE_URL + path, allow_redirects=False, timeout=5, **kwargs)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")


def test_open_redirect_fixed():
    url = BASE_URL + "/login"

    # Test malicious URL
    try:
        res = requests.get(url, params={"redirect_url": "http://malicious.com"}, allow_redirects=False, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert res.status_code == 302, f"Expected HTTP 302, got {res.status_code} for malicious URL"
    assert res.headers.get("Location") == "/home", f"Expected redirect to /home, got {res.headers.get('Location')}"

    # Test valid relative URL
    try:
        res2 = requests.get(url, params={"redirect_url": "/dashboard"}, allow_redirects=False, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert res2.status_code == 302, f"Expected HTTP 302, got {res2.status_code} for valid relative URL"
    assert res2.headers.get("Location") == "/dashboard", f"Expected redirect to /dashboard, got {res2.headers.get('Location')}"


def test_open_redirect_single_slash_policy_on_varied_inputs():
    token = secrets.token_hex(10)
    valid_paths = [
        "/",
        f"/{token}",
        f"/{token}/section",
        f"/account-{token}/settings",
    ]
    invalid_values = [
        "",
        token,
        f"http://{token}.invalid/path",
        f"https://{token}.invalid/path",
        f"//{token}.invalid/path",
        f"///{token}",
    ]

    for value in valid_paths:
        res = get_no_redirect("/login", params={"redirect_url": value})
        assert res.status_code == 302, f"Expected HTTP 302 for valid path {value!r}"
        assert res.headers.get("Location") == value, (
            f"Valid single-slash path {value!r} was not preserved; "
            f"got {res.headers.get('Location')!r}"
        )

    for value in invalid_values:
        res = get_no_redirect("/login", params={"redirect_url": value})
        assert res.status_code == 302, f"Expected HTTP 302 for invalid redirect {value!r}"
        assert res.headers.get("Location") == "/home", (
            f"Invalid redirect {value!r} did not default to /home; "
            f"got {res.headers.get('Location')!r}"
        )


def test_xss_fixed():
    url = BASE_URL + "/error"
    payload = "<script>alert(1)</script>"
    try:
        res = requests.get(url, params={"error_msg": payload}, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    assert res.status_code == 200, f"Expected HTTP 200, got {res.status_code}"
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in res.text, "XSS payload was not properly HTML-entity encoded in the response"
    assert "<script>" not in res.text, "Unescaped '<script>' tag found in the response, XSS vulnerability still present"


def test_all_required_html_characters_are_escaped():
    marker = secrets.token_hex(8)
    accepted_entities = {
        "<": {"&lt;", "&#60;", "&#x3c;", "&#x3C;"},
        ">": {"&gt;", "&#62;", "&#x3e;", "&#x3E;"},
        "&": {"&amp;", "&#38;", "&#x26;"},
        '\"': {"&quot;", "&#34;", "&#x22;"},
        "'": {"&apos;", "&#39;", "&#x27;"},
    }

    for character, entities in accepted_entities.items():
        payload = marker + character + marker
        res = requests.get(BASE_URL + "/error", params={"error_msg": payload}, timeout=5)
        assert res.status_code == 200, f"Expected HTTP 200 while testing {character!r}"

        match = re.search(r"Error: (.*?)</body>", res.text, flags=re.DOTALL)
        assert match, "Could not locate the reflected error message in the response"
        reflected = match.group(1)
        expected_values = {marker + entity + marker for entity in entities}
        assert reflected in expected_values, (
            f"Character {character!r} was not HTML-entity encoded correctly; "
            f"reflected value was {reflected!r}"
        )


def test_csp_header():
    url = BASE_URL + "/login"
    try:
        res = requests.get(url, allow_redirects=False, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")

    expected_csp = "default-src 'self'; script-src 'self'; style-src 'self'; object-src 'none'; frame-ancestors 'none';"
    csp = res.headers.get("Content-Security-Policy")
    assert csp is not None, "Content-Security-Policy header is missing from the response"
    assert csp == expected_csp, f"CSP header mismatch.\nExpected: {expected_csp}\nGot: {csp}"


def malicious_ip_from_log():
    log_path = "/home/user/app/logs/auth.log"
    with open(log_path, "r") as f:
        counts = Counter(re.findall(r"Failed login.*? from ([0-9a-fA-F:.]+)\s*$", f.read(), re.MULTILINE))
    offenders = [ip for ip, count in counts.items() if count > 10]
    assert offenders, "No IP with more than 10 failed login attempts was found in auth.log"
    assert len(offenders) == 1, f"Expected one offending IP, found {offenders}"
    return offenders[0]


def test_nginx_block_config():
    block_conf_path = "/home/user/app/nginx/block.conf"
    assert os.path.exists(block_conf_path), f"{block_conf_path} does not exist"

    with open(block_conf_path, "r") as f:
        content = f.read()

    assert "deny 198.51.100.42;" in content, "The malicious IP 198.51.100.42 is not denied in block.conf"

    offender = malicious_ip_from_log()
    active_lines = []
    for line in content.splitlines():
        active_lines.append(line.split("#", 1)[0])
    active_content = "\n".join(active_lines)
    directive = re.compile(rf"^\s*deny\s+{re.escape(offender)}\s*;\s*$", re.MULTILINE)
    assert directive.search(active_content), (
        f"block.conf does not contain an active deny directive for {offender}; "
        "a commented directive is not sufficient"
    )

    result = subprocess.run(
        ["nginx", "-t", "-c", "/home/user/app/nginx/nginx.conf"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert result.returncode == 0, f"Nginx configuration is invalid:\n{result.stdout}"


def test_offending_ip_is_actually_denied():
    offender = malicious_ip_from_log()
    ip_cmd = ["ip", "addr", "add", f"{offender}/32", "dev", "lo"]
    show = subprocess.run(
        ["ip", "-o", "addr", "show", "dev", "lo"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    added = offender not in show.stdout
    if added:
        subprocess.run(ip_cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    sock = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.bind((offender, 0))
        sock.connect(("127.0.0.1", 8080))
        sock.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        response = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response += chunk
        status_line = response.split(b"\r\n", 1)[0]
        assert re.match(br"HTTP/1\.[01] 403(?:\s|$)", status_line), (
            f"A request sourced from denied IP {offender} was not rejected with 403; "
            f"got {status_line!r}"
        )
    finally:
        if sock is not None:
            sock.close()
        if added:
            subprocess.run(
                ["ip", "addr", "del", f"{offender}/32", "dev", "lo"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )


def test_redis_bound_to_localhost():
    redis_conf_path = "/home/user/app/redis/redis.conf"
    assert os.path.exists(redis_conf_path), f"{redis_conf_path} does not exist"

    with open(redis_conf_path, "r") as f:
        content = f.read()

    assert "bind 127.0.0.1" in content, "Redis is not bound to 127.0.0.1 in redis.conf"
    assert "bind 0.0.0.0" not in content, "Redis is still bound to 0.0.0.0 in redis.conf"

    # Verify via socket that Redis is listening on 127.0.0.1
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    result = s.connect_ex(('127.0.0.1', 6379))
    s.close()
    assert result == 0, "Redis is not listening on 127.0.0.1:6379"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
