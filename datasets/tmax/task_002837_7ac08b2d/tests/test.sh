#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import secrets
import socket
import subprocess
import tempfile
import urllib.error
import urllib.request


def recover_key():
    root = "/home/user/forensics/proc_dump"
    for dirpath, _, filenames in os.walk(root):
        if "cmdline" not in filenames:
            continue
        data = open(os.path.join(dirpath, "cmdline"), "rb").read()
        for arg in data.split(b"\0"):
            if arg.startswith(b"--secret-key="):
                return arg.split(b"=", 1)[1]
    raise AssertionError("Secret key was not recoverable from proc_dump")


def encode_token(obj, key, sort_keys=False):
    raw = json.dumps(obj, separators=(",", ":"), sort_keys=sort_keys).encode()
    encrypted = bytes(value ^ key[i % len(key)] for i, value in enumerate(raw))
    return base64.b64encode(encrypted).decode()


def run_classifier(input_path, expected):
    classifier_path = "/home/user/classifier.py"
    assert os.path.isfile(classifier_path), f"Classifier script missing at {classifier_path}"
    fd, output_path = tempfile.mkstemp(prefix="classifier-output-")
    os.close(fd)
    try:
        result = subprocess.run(
            ["python3", classifier_path, input_path, output_path],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Classifier failed: {result.stderr}"
        with open(output_path) as f:
            actual = f.read().splitlines()
        assert len(actual) == len(expected), (
            f"Output length mismatch. Expected {len(expected)}, got {len(actual)}"
        )
        assert [line.strip() for line in actual] == expected, (
            f"Incorrect classifications: expected {expected}, got {actual}"
        )
    finally:
        if os.path.exists(output_path):
            os.remove(output_path)


def test_classifier_script_on_provided_corpora():
    clean_file = "/home/user/corpus/clean/tokens.txt"
    evil_file = "/home/user/corpus/evil/tokens.txt"
    assert os.path.isfile(clean_file), f"Clean corpus missing: {clean_file}"
    assert os.path.isfile(evil_file), f"Evil corpus missing: {evil_file}"
    with open(clean_file) as f:
        clean_count = len(f.read().splitlines())
    with open(evil_file) as f:
        evil_count = len(f.read().splitlines())
    run_classifier(clean_file, ["CLEAN"] * clean_count)
    run_classifier(evil_file, ["EVIL"] * evil_count)


def test_classifier_on_fresh_mixed_tokens():
    key = recover_key()
    nonce = secrets.token_hex(12)
    entries = []
    expected = []
    for i in range(6):
        role = "user" if i % 2 == 0 else "admin"
        obj = {
            "user": f"runtime-{nonce}-{i}",
            "role": role,
            "exp": 2000000000 + secrets.randbelow(500000000),
        }
        entries.append(encode_token(obj, key, sort_keys=bool(i % 3)))
        expected.append("CLEAN" if role == "user" else "EVIL")

    fd, input_path = tempfile.mkstemp(prefix="unseen-token-input-", suffix=".txt")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(entries) + "\n")
        run_classifier(input_path, expected)
    finally:
        if os.path.exists(input_path):
            os.remove(input_path)


def listener_owners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[3] == "0A":
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
    owners = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if not any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
            continue
        try:
            cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
            owners.append((exe, cmdline))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def request_status(port, path="/api/data", token=None):
    request = urllib.request.Request(f"http://127.0.0.1:{port}{path}")
    if token is not None:
        request.add_header("Cookie", f"auth_token={token}")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except urllib.error.URLError as error:
        raise AssertionError(f"Failed to connect to port {port}: {error.reason}")


def auth_request_uri():
    config_path = "/home/user/app/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx config missing: {config_path}"
    config = open(config_path).read()
    uncommented = re.sub(r"#.*", "", config)
    matches = re.findall(r"\bauth_request\s+([^;\s]+)\s*;", uncommented)
    matches = [value for value in matches if value != "off"]
    assert matches, "nginx.conf does not contain an enabled auth_request directive"
    result = subprocess.run(
        ["nginx", "-t", "-c", config_path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Invalid nginx.conf: {result.stderr}"
    return matches[0]


def find_auth_service_path(clean_token, configured_uri):
    candidates = []
    if configured_uri.startswith("/") and "$" not in configured_uri:
        candidates.append(configured_uri)
    candidates.extend(["/", "/auth", "/verify", "/validate"])
    for path in dict.fromkeys(candidates):
        if request_status(8080, path, clean_token) == 200:
            return path
    raise AssertionError("Auth service did not accept a fresh valid user token on port 8080")


def test_services_and_nginx_auth_request():
    auth_path = "/home/user/auth_service.py"
    assert os.path.isfile(auth_path), f"Auth service missing at {auth_path}"

    nginx_owners = listener_owners(8000)
    assert nginx_owners, "Nothing is listening on port 8000"
    assert any("nginx" in exe.lower() or "nginx" in cmd.lower() for exe, cmd in nginx_owners), (
        f"Port 8000 is not owned by Nginx: {nginx_owners}"
    )

    auth_owners = listener_owners(8080)
    assert auth_owners, "Nothing is listening on port 8080"
    assert any("auth_service" in cmd for _, cmd in auth_owners), (
        f"Port 8080 is not served by auth_service.py: {auth_owners}"
    )

    configured_uri = auth_request_uri()
    key = recover_key()
    nonce = secrets.token_hex(16)
    clean_token = encode_token(
        {"user": f"fresh-user-{nonce}", "role": "user", "exp": 2200000000}, key, True
    )
    evil_token = encode_token(
        {"exp": 2200000001, "role": "admin", "user": f"fresh-admin-{nonce}"}, key
    )
    malformed_token = base64.b64encode(secrets.token_bytes(31)).decode()

    direct_path = find_auth_service_path(clean_token, configured_uri)
    assert request_status(8080, direct_path, evil_token) == 401
    assert request_status(8080, direct_path, malformed_token) == 401
    assert request_status(8080, direct_path) == 401

    assert request_status(8000, "/api/data", clean_token) == 200
    assert request_status(8000, "/api/data", evil_token) == 401
    assert request_status(8000, "/api/data", malformed_token) == 401
    assert request_status(8000, "/api/data") == 401

    with open("/home/user/corpus/clean/tokens.txt") as f:
        fixture_clean = f.readline().strip()
    with open("/home/user/corpus/evil/tokens.txt") as f:
        fixture_evil = f.readline().strip()
    assert request_status(8000, "/api/data", fixture_clean) == 200
    assert request_status(8000, "/api/data", fixture_evil) == 401
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
