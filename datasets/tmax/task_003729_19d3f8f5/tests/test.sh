#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import os
import random
import re
import secrets
import shutil
import socket
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest
import redis

CLASSIFIER = "/home/user/classifier"
API_DIR = "/home/user/workspace/api"
NGINX_CONF = "/home/user/workspace/nginx/nginx.conf"
TOKENS = ("EXEC_PAYLOAD", "DROP_DB")


def check_port(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("127.0.0.1", port)) == 0


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            if int(fields[1].rsplit(":", 1)[1], 16) == port:
                inodes.add(fields[9])

    found = set()
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            for fd in os.listdir(os.path.join(proc, "fd")):
                target = os.readlink(os.path.join(proc, "fd", fd))
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    found.add(int(os.path.basename(proc)))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def proc_exe(pid):
    try:
        return os.path.basename(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        return ""


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def proc_environ(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            entries = f.read().split(b"\0")
        return {
            item.split(b"=", 1)[0].decode("utf-8", "replace"):
            item.split(b"=", 1)[1].decode("utf-8", "replace")
            for item in entries if b"=" in item
        }
    except OSError:
        return {}


def encode_value(value, force_escape=False):
    out = []
    forced = False
    for ch in value:
        if ch == "\n":
            out.append(r"\n")
        elif ch == "\t":
            out.append(r"\t")
        elif ch == "\\":
            out.append(r"\\")
        elif 32 <= ord(ch) <= 126 and (secrets.randbelow(3) != 0 or ch == "="):
            out.append(ch)
        else:
            out.append("\\x%02x" % ord(ch))
            forced = True
    if force_escape and not forced and value:
        out[0] = "\\x%02X" % ord(value[0])
    return "".join(out)


def make_payload(evil):
    nonce = secrets.token_hex(10)
    values = [f"safe-{nonce}", "tabs\tand\nnewlines\\end"]
    if evil:
        token = secrets.choice(TOKENS)
        values.insert(secrets.randbelow(len(values) + 1), f"pre{token}post")
    else:
        values.extend(["EXEC-PAYLOAD", "DROPX_DB", "ordinary_value"])

    lines = []
    for i, value in enumerate(values):
        key = f"k_{secrets.token_hex(5)}_{i}"
        lines.append(key + "=" + encode_value(value, force_escape=evil and any(t in value for t in TOKENS)))
    if not evil:
        # Blacklisted text in a key is not a blacklisted value.
        lines.append("EXEC_PAYLOAD_" + secrets.token_hex(4) + "=harmless")
    expected = any(token in value for value in values for token in TOKENS)
    assert expected == evil
    return ("\n".join(lines)).encode()


def run_classifier(payload):
    fd, path = tempfile.mkstemp(prefix=secrets.token_hex(6) + "_", suffix=".dat")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(payload)
        return subprocess.run([CLASSIFIER, path], capture_output=True, timeout=3).returncode
    finally:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def post_payload(url, payload):
    req = urllib.request.Request(url, data=payload, method="POST")
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200
        return json.loads(response.read().decode())


def test_classifier_executable():
    classifier_path = "/home/user/classifier"
    assert os.path.isfile(classifier_path), f"Classifier not found at {classifier_path}"
    assert os.access(classifier_path, os.X_OK), f"Classifier at {classifier_path} is not executable"


def test_classifier_corpus():
    classifier_path = "/home/user/classifier"
    clean_dir = "/home/user/workspace/corpus/clean"
    evil_dir = "/home/user/workspace/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    clean_modified = []
    for f in clean_files:
        res = subprocess.run([classifier_path, f], capture_output=True)
        if res.returncode != 0:
            clean_modified.append(os.path.basename(f))

    evil_bypassed = []
    for f in evil_files:
        res = subprocess.run([classifier_path, f], capture_output=True)
        if res.returncode != 1:
            evil_bypassed.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not errors, " | ".join(errors)


def test_classifier_randomized_parser_cases():
    cases = [(make_payload(False), 0) for _ in range(18)]
    cases += [(make_payload(True), 1) for _ in range(18)]
    random.SystemRandom().shuffle(cases)
    for payload, expected in cases:
        assert run_classifier(payload) == expected, f"wrong classification for generated payload {payload!r}"


def test_extension_build_and_install():
    assert os.path.isfile(os.path.join(API_DIR, "setup.py"))
    assert os.path.isfile(os.path.join(API_DIR, "fastparser.c"))

    # Verify the editable installation is currently importable as a native extension.
    code = (
        "import fastparser, importlib.machinery; "
        "assert fastparser.__file__.endswith(tuple(importlib.machinery.EXTENSION_SUFFIXES)); "
        "assert fastparser.parse('probe') == 'probe'"
    )
    installed = subprocess.run(["python3", "-c", code], capture_output=True, text=True, timeout=10)
    assert installed.returncode == 0, installed.stdout + installed.stderr

    # Rebuild from a fresh copy so a stale prebuilt object cannot satisfy the check.
    with tempfile.TemporaryDirectory() as td:
        shutil.copy2(os.path.join(API_DIR, "setup.py"), os.path.join(td, "setup.py"))
        shutil.copy2(os.path.join(API_DIR, "fastparser.c"), os.path.join(td, "fastparser.c"))
        built = subprocess.run(
            ["python3", "setup.py", "build_ext", "--inplace"],
            cwd=td, capture_output=True, text=True, timeout=60
        )
        assert built.returncode == 0, built.stdout + built.stderr
        check = subprocess.run(["python3", "-c", code], cwd=td, capture_output=True, text=True, timeout=10)
        assert check.returncode == 0, check.stdout + check.stderr


def test_services_running():
    assert check_port(6379), "Redis is not listening on port 6379"
    assert check_port(5000), "Python API is not listening on port 5000"
    assert check_port(8080), "Nginx is not listening on port 8080"


def test_service_identities_and_environment():
    redis_pids = listener_pids(6379)
    api_pids = listener_pids(5000)
    nginx_pids = listener_pids(8080)
    assert redis_pids and any(proc_exe(pid).startswith("redis-server") for pid in redis_pids)
    assert api_pids and any("uvicorn" in proc_cmdline(pid) and "main:app" in proc_cmdline(pid) for pid in api_pids)
    assert nginx_pids and any(proc_exe(pid) == "nginx" for pid in nginx_pids)

    matching_api = [pid for pid in api_pids if "uvicorn" in proc_cmdline(pid) and "main:app" in proc_cmdline(pid)]
    assert any(proc_environ(pid).get("REDIS_URL") == "redis://127.0.0.1:6379/0" for pid in matching_api)
    assert any(proc_environ(pid).get("CLASSIFIER_CMD") == CLASSIFIER for pid in matching_api)

    pong = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2).ping()
    assert pong is True


def test_nginx_configuration():
    checked = subprocess.run(
        ["nginx", "-T", "-c", NGINX_CONF], capture_output=True, text=True, timeout=10
    )
    combined = checked.stdout + checked.stderr
    assert checked.returncode == 0, combined
    assert re.search(r"\blisten\s+8080\s*;", combined)
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;", combined)


def test_nginx_proxy():
    # Test that Nginx is proxying to the API
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/")
        with urllib.request.urlopen(req, timeout=2) as response:
            pass # Just checking if it responds without Nginx 502 Bad Gateway
    except urllib.error.HTTPError as e:
        # 404 or 405 is fine, it means the API responded
        assert e.code in [404, 405, 422], f"Expected API response, got HTTP {e.code}"
    except Exception as e:
        pytest.fail(f"Failed to connect to Nginx proxy: {e}")


def test_api_classifier_redis_and_proxy_integration():
    client = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    clean_before = int(client.get("clean_payloads") or 0)
    evil_before = int(client.get("evil_payloads") or 0)

    direct_clean = post_payload("http://127.0.0.1:5000/submit", make_payload(False))
    direct_evil = post_payload("http://127.0.0.1:5000/submit", make_payload(True))
    proxy_clean = post_payload("http://127.0.0.1:8080/submit", make_payload(False))
    proxy_evil = post_payload("http://127.0.0.1:8080/submit", make_payload(True))

    assert direct_clean == {"status": "clean"}
    assert direct_evil == {"status": "evil"}
    assert proxy_clean == {"status": "clean"}
    assert proxy_evil == {"status": "evil"}
    assert int(client.get("clean_payloads") or 0) >= clean_before + 2
    assert int(client.get("evil_payloads") or 0) >= evil_before + 2
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
