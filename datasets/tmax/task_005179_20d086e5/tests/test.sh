#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import pwd
import re
import secrets
import socket
import string
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

BACKEND_URL = "http://127.0.0.1:9337/process"
NGINX_URL = "http://127.0.0.1:8080/process"
NO_PROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def request(url, data, timeout=5):
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with NO_PROXY.open(req, timeout=timeout) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def assert_status(url, payload, expected):
    try:
        status = request(url, payload)
    except Exception as exc:
        pytest.fail(f"Request to {url} failed: {exc}")
    assert status == expected, f"{url} returned HTTP {status}, expected {expected}, for {payload!r}"


def user_systemctl(*args):
    account = pwd.getpwnam("user")
    runtime = f"/run/user/{account.pw_uid}"
    env_args = [
        f"XDG_RUNTIME_DIR={runtime}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus",
    ]
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", *env_args, "systemctl", "--user", *args],
        text=True,
        capture_output=True,
        timeout=10,
    )


def test_nginx_running_and_configured():
    result = subprocess.run(["systemctl", "is-active", "nginx"], text=True, capture_output=True)
    assert result.returncode == 0 and result.stdout.strip() == "active", "Nginx is not running"

    config_path = "/etc/nginx/sites-available/default"
    assert os.path.isfile(config_path), f"Missing {config_path}"
    config = open(config_path, encoding="utf-8", errors="replace").read()
    assert re.search(r"\blisten\s+[^;]*\b8080\b", config), "Nginx is not configured to listen on port 8080"
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):9337(?:[/;]|\s)", config), \
        "Nginx does not proxy to the memo-specified backend port 9337"


@pytest.fixture(scope="session")
def backend_service():
    service_path = "/home/user/.config/systemd/user/backend.service"
    source_path = "/home/user/backend/server.cpp"
    assert os.path.isfile(service_path), f"backend.service not found at {service_path}"
    assert os.path.isfile(source_path), f"Backend source not found at {source_path}"

    active = user_systemctl("is-active", "backend.service")
    assert active.returncode == 0 and active.stdout.strip() == "active", \
        f"backend.service is not an active user service: {active.stderr.strip()}"

    shown = user_systemctl(
        "show", "backend.service",
        "--property=MainPID", "--property=Restart", "--property=ExecStart", "--property=FragmentPath",
    )
    assert shown.returncode == 0, f"Could not inspect backend.service: {shown.stderr.strip()}"
    props = {}
    for line in shown.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            props[key] = value

    assert props.get("Restart") in {"always", "on-failure", "on-abnormal", "on-abort"}, \
        "backend.service is not configured to restart after failure"
    assert os.path.realpath(props.get("FragmentPath", "")) == os.path.realpath(service_path), \
        "The running backend.service is not the required user unit"

    try:
        pid = int(props.get("MainPID", "0"))
    except ValueError:
        pid = 0
    assert pid > 0 and os.path.exists(f"/proc/{pid}"), "backend.service has no live main process"

    try:
        executable = os.path.realpath(os.readlink(f"/proc/{pid}/exe"))
    except OSError as exc:
        pytest.fail(f"Cannot inspect backend.service executable: {exc}")
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Backend main process is not an executable"
    with open(executable, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "backend.service is not running a compiled ELF backend"
    assert os.path.getmtime(executable) >= os.path.getmtime(source_path), \
        "The running backend binary predates server.cpp and was not rebuilt from the submitted source"

    with tempfile.TemporaryDirectory() as directory:
        probe_binary = os.path.join(directory, "backend-build-check")
        compiled = subprocess.run(
            ["g++", "-std=c++17", source_path, "-o", probe_binary],
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert compiled.returncode == 0, f"server.cpp does not compile: {compiled.stderr}"

    return pid


def test_original_adversarial_corpus(backend_service):
    clean_files = glob.glob("/app/corpus/clean/*")
    evil_files = glob.glob("/app/corpus/evil/*")
    assert clean_files or evil_files, "Corpus directories are empty or missing"

    failures = []
    for path in clean_files:
        if not os.path.isfile(path):
            continue
        data = open(path, "rb").read()
        try:
            status = request(NGINX_URL, data)
        except Exception as exc:
            failures.append(f"{os.path.basename(path)} (Error: {exc})")
        else:
            if status != 200:
                failures.append(f"{os.path.basename(path)} (HTTP {status}, expected 200)")

    for path in evil_files:
        if not os.path.isfile(path):
            continue
        data = open(path, "rb").read()
        try:
            status = request(NGINX_URL, data)
        except Exception as exc:
            failures.append(f"{os.path.basename(path)} (Error: {exc})")
        else:
            if status != 403:
                failures.append(f"{os.path.basename(path)} (HTTP {status}, expected 403)")

    assert not failures, "Corpus classification failures: " + ", ".join(failures)


def test_generated_classifier_cases_through_backend_and_nginx(backend_service):
    alphabet = string.ascii_letters + string.digits
    token = "".join(secrets.choice(alphabet) for _ in range(18))
    number = secrets.randbelow(1_000_000_000) + 1

    clean = [
        json.dumps({"user": f"user_{token}", "pass": f"safe_{token}"}).encode(),
        json.dumps({"action": f"ping_{token}", "timestamp": number}).encode(),
    ]
    evil = [
        json.dumps({"user": token, "pass": f"x'; DROP TABLE audit_{token};--"}).encode(),
        json.dumps({"cmd": f"$(printf {token})"}).encode(),
        json.dumps({"file": f"../../../../tmp/{token}/etc/passwd"}).encode(),
    ]

    for url in (BACKEND_URL, NGINX_URL):
        for payload in clean:
            assert_status(url, payload, 200)
        for payload in evil:
            assert_status(url, payload, 403)


def non_loopback_ipv4():
    candidates = []
    try:
        candidates.extend(socket.gethostbyname_ex(socket.gethostname())[2])
    except OSError:
        pass
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("8.8.8.8", 53))
        candidates.append(probe.getsockname()[0])
        probe.close()
    except OSError:
        pass
    for address in candidates:
        if address and not address.startswith("127.") and address != "0.0.0.0":
            return address
    pytest.fail("Could not determine a non-loopback address for firewall verification")


def test_firewall_and_direct_access_restriction(backend_service):
    ufw = subprocess.run(["ufw", "status"], text=True, capture_output=True, timeout=10)
    ufw_text = ufw.stdout
    ufw_active = re.search(r"^Status:\s+active\s*$", ufw_text, re.MULTILINE | re.IGNORECASE)
    ufw_open_8080 = re.search(r"^8080(?:/tcp)?\s+ALLOW", ufw_text, re.MULTILINE | re.IGNORECASE)
    ufw_block_9337 = re.search(r"^9337(?:/tcp)?\s+(?:DENY|REJECT)", ufw_text, re.MULTILINE | re.IGNORECASE)

    saved = subprocess.run(["iptables-save"], text=True, capture_output=True, timeout=10)
    rules = saved.stdout.splitlines()
    ipt_open_8080 = any(re.search(r"--dport 8080\b", line) and re.search(r"-j ACCEPT\b", line) for line in rules)
    ipt_block_9337 = any(re.search(r"--dport 9337\b", line) and re.search(r"-j (?:DROP|REJECT)\b", line) for line in rules)
    ipt_loopback = any(re.search(r"(?:-i lo\b|-s 127\.0\.0\.1(?:/32)?)", line) and re.search(r"-j ACCEPT\b", line) for line in rules)

    configured = bool(
        (ufw_active and ufw_open_8080 and ufw_block_9337)
        or (ipt_open_8080 and ipt_block_9337 and ipt_loopback)
    )
    assert configured, "No active firewall policy opens 8080 while blocking external access to 9337"

    address = non_loopback_ipv4()
    token = secrets.token_hex(8)
    benign = json.dumps({"action": f"ping_{token}", "timestamp": int(time.time())}).encode()
    assert_status(f"http://{address}:8080/process", benign, 200)

    try:
        status = request(f"http://{address}:9337/process", benign, timeout=2)
    except (OSError, urllib.error.URLError, TimeoutError, socket.timeout):
        status = None
    assert status is None, f"Backend port 9337 is externally reachable on {address} (HTTP {status})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
