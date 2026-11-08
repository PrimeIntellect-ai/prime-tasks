#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import string
import subprocess
import time
import urllib.error
import urllib.request

import pytest

ROOT = "/home/user/auth_util"
API = ROOT + "/api/target/release/api"
CONFIG = ROOT + "/nginx.conf"
START = "/home/user/start.sh"
CLIB_DIR = ROOT + "/clib"


def run_checked(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {args}\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def api_pids():
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if os.path.realpath(f"/proc/{entry}/exe") == os.path.realpath(API):
                result.append(int(entry))
        except OSError:
            pass
    return result


def nginx_uses_custom_config():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ")
        except OSError:
            continue
        if b"nginx" in raw and CONFIG.encode() in raw:
            return True
    return False


def request(path, token=None):
    url = "http://localhost:8080" + path
    data = None
    headers = {}
    if token is not None:
        data = json.dumps({"token": token}).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        response = urllib.request.urlopen(req, timeout=4)
        body = response.read()
        return response.status, {k.lower(): v for k, v in response.getheaders()}, body
    except urllib.error.HTTPError as exc:
        body = exc.read()
        return exc.code, {k.lower(): v for k, v in exc.headers.items()}, body
    except urllib.error.URLError as exc:
        pytest.fail(f"Request to {url} failed: {exc}")


def assert_secure_header(headers):
    assert "x-proxy-secure" in headers, "Header 'X-Proxy-Secure' is missing."
    assert headers["x-proxy-secure"].lower() == "true"


def setup_module(module):
    assert os.path.exists(START), f"{START} does not exist."
    assert os.access(START, os.X_OK), f"{START} is not executable."
    assert os.path.exists(CONFIG), f"Nginx configuration {CONFIG} is missing."

    # Build from the submitted Rust source, rather than trusting a pre-created executable.
    run_checked(["cargo", "clean"], cwd=ROOT + "/api", timeout=60)
    run_checked(["cargo", "build", "--release"], cwd=ROOT + "/api", timeout=240)
    assert os.path.isfile(API) and os.access(API, os.X_OK)

    # The resulting executable must dynamically use the supplied C FFI symbol/library.
    dynamic = run_checked(["readelf", "-d", API], timeout=20).stdout
    symbols = run_checked(["readelf", "-Ws", API], timeout=20).stdout
    assert re.search(r"NEEDED.*\[libtoken\.so\]", dynamic), "Rust binary is not linked to libtoken.so"
    assert re.search(r"\bUND\b.*\bvalidate_token\b", symbols), "Rust binary does not import validate_token"

    source = open(ROOT + "/api/src/main.rs", encoding="utf-8").read()
    assert re.search(r"fn\s+validate_token\s*\(\s*token\s*:\s*\*const\s+c_char\s*\)\s*->\s*i32", source), (
        "Required C FFI signature was changed"
    )

    run_checked(["nginx", "-t", "-c", CONFIG], timeout=20)

    # Remove stale processes so the submitted startup script must launch this build.
    subprocess.run(["pkill", "-TERM", "-f", API], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-TERM", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)

    result = subprocess.run([START], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, (
        f"start.sh failed with return code {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    time.sleep(3)

    pids = api_pids()
    assert pids, "start.sh did not leave the compiled Rust API running"
    found_library_path = False
    for pid in pids:
        try:
            env = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
        except OSError:
            continue
        for item in env:
            if item.startswith(b"LD_LIBRARY_PATH="):
                paths = item.split(b"=", 1)[1].decode(errors="replace").split(":")
                if CLIB_DIR in paths:
                    found_library_path = True
    assert found_library_path, "Rust API process lacks the required LD_LIBRARY_PATH entry"
    assert nginx_uses_custom_config(), "Nginx was not started with the submitted custom configuration"


def test_nginx_config_exists():
    assert os.path.exists(CONFIG), f"Nginx configuration {CONFIG} is missing."


def test_valid_token():
    status, headers, raw = request("/validate", "SECURE_123")
    assert status == 200
    assert_secure_header(headers)
    body = json.loads(raw.decode("utf-8"))
    assert body.get("valid") is True, f"Expected {{'valid': true}}, got {body}."


def test_invalid_token():
    status, headers, raw = request("/validate", "INVALID_123")
    assert status == 200
    assert_secure_header(headers)
    body = json.loads(raw.decode("utf-8"))
    assert body.get("valid") is False, f"Expected {{'valid': false}}, got {body}."


def test_random_tokens_against_c_library():
    oracle = ctypes.CDLL(ROOT + "/clib/libtoken.so")
    oracle.validate_token.argtypes = [ctypes.c_char_p]
    oracle.validate_token.restype = ctypes.c_int

    nonce = "".join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=24))
    tokens = [
        "SECURE_" + nonce,
        "SECURE_" + nonce[::-1],
        "SECURE_",
        "secure_" + nonce,
        "INVALID_" + nonce,
        nonce + "SECURE_",
        "",
    ]
    for token in tokens:
        expected = oracle.validate_token(token.encode("utf-8")) == 1
        status, headers, raw = request("/validate", token)
        assert status == 200, f"Unexpected status for token {token!r}: {status}"
        assert_secure_header(headers)
        body = json.loads(raw.decode("utf-8"))
        assert set(body) == {"valid"}, f"Response schema changed: {body}"
        assert body["valid"] is expected, f"Wrong result for generated token {token!r}: {body}"


def test_admin_blocked():
    for path in ["/admin", "/admin/", "/admin/settings", "/admin/users/42"]:
        status, headers, _ = request(path)
        assert status == 403, f"Expected HTTP 403 for {path}, got {status}."
        assert_secure_header(headers)


def test_other_paths_are_proxied_with_security_header():
    suffix = "".join(random.SystemRandom().choices(string.ascii_lowercase, k=18))
    status, headers, _ = request("/" + suffix)
    assert status == 404
    assert_secure_header(headers)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
