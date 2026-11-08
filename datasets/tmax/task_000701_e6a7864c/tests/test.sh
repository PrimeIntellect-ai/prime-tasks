#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest

BINARY = "/home/user/token_validator"


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def fetch_without_redirect(url, timeout=5):
    opener = urllib.request.build_opener(NoRedirectHandler)
    try:
        response = opener.open(url, timeout=timeout)
        return response.getcode(), response.info()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers


def test_nginx_proxy_works():
    """
    Preserve the original fixed end-to-end assertion.
    """
    url = "http://127.0.0.1:8080/auth?next=/settings"
    try:
        status, headers = fetch_without_redirect(url)
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to nginx on port 8080. Is it running? Error: {exc}")

    assert status == 302, f"Expected HTTP 302 redirect, but got {status}"
    set_cookie = headers.get("Set-Cookie", "")
    assert "auth_token=" in set_cookie, "Expected 'Set-Cookie: auth_token=' in the response headers."


def test_nginx_configuration_contains_auth_proxy_pass():
    config_path = "/app/nginx/nginx.conf"
    assert os.path.isfile(config_path), f"Missing nginx configuration: {config_path}"

    result = subprocess.run(
        ["nginx", "-T", "-c", config_path], capture_output=True, text=True
    )
    assert result.returncode == 0, f"nginx rejected the configuration: {result.stderr}"

    text = re.sub(r"#.*", "", result.stdout + "\n" + result.stderr)
    auth_blocks = []
    for match in re.finditer(r"\blocation\s+([^{}]+)\{", text):
        if "/auth" not in match.group(1):
            continue
        start = match.end()
        depth = 1
        pos = start
        while pos < len(text) and depth:
            if text[pos] == "{":
                depth += 1
            elif text[pos] == "}":
                depth -= 1
            pos += 1
        if depth == 0:
            auth_blocks.append(text[start:pos - 1])

    assert auth_blocks, "No nginx location handling /auth was found."
    assert any(re.search(r"\bproxy_pass\s+[^;]+;", block) for block in auth_blocks), (
        "The nginx /auth location does not contain an active proxy_pass directive."
    )


def test_nginx_forwards_unpredictable_requests_to_flask():
    nonce = secrets.token_hex(12)
    redirects = [
        f"/dashboard-{nonce}",
        f"/users/{nonce}/settings",
        f"/continue/{nonce}?tab=security",
    ]

    for target in redirects:
        query = urllib.parse.urlencode({"next": target, "probe": secrets.token_hex(6)})
        nginx_url = f"http://127.0.0.1:8080/auth?{query}"
        flask_url = f"http://127.0.0.1:5000/auth?{query}"
        try:
            nginx_status, nginx_headers = fetch_without_redirect(nginx_url)
            flask_status, flask_headers = fetch_without_redirect(flask_url)
        except urllib.error.URLError as exc:
            pytest.fail(f"Could not exercise nginx and Flask: {exc}")

        assert flask_status == 302
        assert nginx_status == flask_status
        assert nginx_headers.get("Location") == target
        assert nginx_headers.get("Location") == flask_headers.get("Location")
        assert "auth_token=" in nginx_headers.get("Set-Cookie", "")


def _listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as stream:
                next(stream, None)
                for line in stream:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


def test_nginx_auth_depends_on_port_5000_service():
    """A static nginx 302 must not pass as a Flask proxy."""
    target = f"/dependency-{secrets.token_hex(10)}"
    url = "http://127.0.0.1:8080/auth?" + urllib.parse.urlencode({"next": target})
    status, headers = fetch_without_redirect(url)
    assert status == 302 and headers.get("Location") == target

    pids = _listener_pids(5000)
    assert pids, "No Flask-side service is listening on port 5000."
    for pid in pids:
        os.kill(pid, signal.SIGTERM)

    deadline = time.time() + 3
    while time.time() < deadline and _listener_pids(5000):
        time.sleep(0.05)

    try:
        status, headers = fetch_without_redirect(url, timeout=3)
        still_static = status == 302 and headers.get("Location") == target
    except Exception:
        still_static = False
    assert not still_static, "nginx still served the expected static 302 after the port 5000 service stopped."


def test_token_validator_compiled():
    """Preserve the original existence and executable assertions."""
    assert os.path.isfile(BINARY), f"The compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"The file {BINARY} is not executable."
    with open(BINARY, "rb") as stream:
        assert stream.read(4) == b"\x7fELF", "token_validator is not a compiled executable."


def test_token_validator_clean_corpus():
    """Preserve the original clean-corpus assertions."""
    clean_dir = "/app/corpora/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "rb") as stream:
            result = subprocess.run([BINARY], stdin=stream, capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "VALID":
            failed_files.append((filename, result.returncode, output))

    if failed_files:
        details = ", ".join(f"{name} (code={code}, out='{out}')" for name, code, out in failed_files)
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean tokens modified/rejected: {details}")


def test_token_validator_evil_corpus():
    """Preserve the original evil-corpus assertions."""
    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "rb") as stream:
            result = subprocess.run([BINARY], stdin=stream, capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 1 or output != "INVALID":
            failed_files.append((filename, result.returncode, output))

    if failed_files:
        details = ", ".join(f"{name} (code={code}, out='{out}')" for name, code, out in failed_files)
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil tokens bypassed: {details}")


def _token(user, redirect, signature):
    raw = user.encode() + b"|" + redirect + b"|" + signature.encode()
    return base64.b64encode(raw)


def _run_validator(token):
    return subprocess.run([BINARY], input=token, capture_output=True)


def test_token_validator_generated_adversarial_cases():
    """Exercise fresh tokens whose expected classifications are derived here."""
    nonce = secrets.token_hex(16)
    user = "user-" + secrets.token_hex(8)
    signature = secrets.token_hex(32)

    safe_redirects = [
        b"/",
        f"/dashboard-{nonce}".encode(),
        f"/profile/{nonce}/settings".encode(),
        f"/continue/{nonce}?url=http://example.invalid".encode(),
        f"/javascript:{nonce}".encode(),
    ]
    invalid_redirects = [
        f"//evil-{nonce}.invalid/path".encode(),
        f"http://attacker-{nonce}.invalid".encode(),
        f"https://attacker-{nonce}.invalid".encode(),
        f"javascript:alert-{nonce}".encode(),
        f"dashboard-{nonce}".encode(),
        b"",
        f"/safe/{nonce}\nInjected".encode(),
        f"/safe/{nonce}\rInjected".encode(),
        b"/safe/" + nonce.encode() + b"\x01bad",
    ]

    cases = []
    cases.extend((_token(user, redirect, signature), 0, b"VALID") for redirect in safe_redirects)
    cases.extend((_token(user, redirect, signature), 1, b"INVALID") for redirect in invalid_redirects)
    cases.append((_token(user, f"/short-{nonce}".encode(), signature[:-1]), 1, b"INVALID"))
    cases.append((_token(user, f"/long-{nonce}".encode(), signature + "a"), 1, b"INVALID"))

    secrets.SystemRandom().shuffle(cases)
    for token, expected_code, expected_output in cases:
        result = _run_validator(token)
        assert result.returncode == expected_code, (
            f"Unexpected exit code {result.returncode}; expected {expected_code} for generated token"
        )
        assert result.stdout.strip() == expected_output, (
            f"Unexpected output {result.stdout!r}; expected {expected_output.decode()}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
