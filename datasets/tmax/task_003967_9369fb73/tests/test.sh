#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest

APP_DIR = "/home/user/app"
BUILD_SH = os.path.join(APP_DIR, "build.sh")
NGINX_CONF = "/home/user/nginx.conf"


def request(url, timeout=5):
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read(), response.headers
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), exc.headers


def listening_socket_inodes(port):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and local.rsplit(":", 1)[1].upper() == wanted:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def socket_owner_pids(port):
    inodes = listening_socket_inodes(port)
    owners = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(proc + "/fd"):
                try:
                    target = os.readlink(proc + "/fd/" + fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(pid)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def cmdline(pid):
    try:
        raw = open(f"/proc/{pid}/cmdline", "rb").read()
        if raw:
            return raw.replace(b"\0", b" ").decode(errors="replace")
        return open(f"/proc/{pid}/comm").read().strip()
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return ""


def parent_pid(pid):
    try:
        for line in open(f"/proc/{pid}/status"):
            if line.startswith("PPid:"):
                return int(line.split()[1])
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass
    return 0


def process_lineage(pid):
    result = []
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        result.append(cmdline(pid))
        pid = parent_pid(pid)
    return result


def test_build_sh_exists_and_executable_and_rebuilds_extension():
    assert os.path.isfile(BUILD_SH), f"{BUILD_SH} does not exist"
    assert os.access(BUILD_SH, os.X_OK), f"{BUILD_SH} is not executable"

    text = open(BUILD_SH).read()
    assert re.search(r"(?:pip3?|python3?\s+-m\s+pip)\s+install(?:\s+[^\n;]+)*\s+-r\s+(?:/home/user/app/)?requirements\.txt", text), \
        "build.sh does not install requirements.txt"
    assert re.search(r"python3?\s+(?:/home/user/app/)?setup\.py\s+build_ext\s+--inplace", text), \
        "build.sh does not build the C extension in place"

    for artifact in glob.glob(os.path.join(APP_DIR, "processor*.so")):
        os.remove(artifact)

    completed = subprocess.run(
        [BUILD_SH], cwd=APP_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=180
    )
    assert completed.returncode == 0, f"build.sh failed:\n{completed.stdout}"

    artifacts = glob.glob(os.path.join(APP_DIR, "processor*.so"))
    assert artifacts, "build.sh did not produce an in-place processor extension"
    assert all(open(path, "rb").read(4) == b"\x7fELF" for path in artifacts), \
        "processor build output is not a native ELF extension"

    check = subprocess.run(
        [sys.executable, "-c",
         "import importlib.machinery, processor; "
         "assert isinstance(processor.__loader__, importlib.machinery.ExtensionFileLoader); "
         "assert processor.process('verification') == 'processed'; print(processor.__file__)"],
        cwd=APP_DIR, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert check.returncode == 0, f"built processor extension cannot be imported:\n{check.stderr}"
    assert os.path.realpath(check.stdout.strip()).startswith(os.path.realpath(APP_DIR) + os.sep)


def test_test_result_txt():
    path = "/home/user/test_result.txt"
    assert os.path.isfile(path), f"{path} does not exist"
    with open(path, "r") as f:
        content = f.read()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"{path} does not contain valid JSON")
    assert data.get("status") == "secure", f"{path} does not contain the correct status"


def test_nginx_configuration_and_live_listener():
    assert os.path.isfile(NGINX_CONF), f"{NGINX_CONF} does not exist"
    conf = open(NGINX_CONF).read()
    uncommented = re.sub(r"#.*", "", conf)
    assert re.search(r"\blisten\s+8080\b", uncommented), "nginx.conf does not listen on port 8080"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:8000\s*;", uncommented), \
        "nginx.conf does not proxy to 127.0.0.1:8000"
    assert re.search(r"\badd_header\s+X-Security-Protection\s+active(?:\s+always)?\s*;", uncommented), \
        "nginx.conf does not inject the required security header"
    assert re.search(r"\berror_log\s+/home/user/nginx_error\.log(?:\s+\w+)?\s*;", uncommented), \
        "nginx.conf does not use /home/user/nginx_error.log"

    owners = socket_owner_pids(8080)
    assert owners, "no process is listening on port 8080"
    lineages = [entry for pid in owners for entry in process_lineage(pid)]
    assert any("nginx" in entry.lower() for entry in lineages), \
        f"port 8080 is not owned by Nginx: {lineages}"
    assert any("nginx" in entry.lower() and NGINX_CONF in entry for entry in lineages), \
        "the Nginx listener was not started with /home/user/nginx.conf"
    assert socket_owner_pids(8000), "no application process is listening on port 8000"


def test_status_endpoint_and_headers_and_real_proxying():
    nonce = secrets.token_hex(12)
    backend_url = f"http://127.0.0.1:8000/status?probe={nonce}"
    proxy_url = f"http://127.0.0.1:8080/status?probe={nonce}"

    try:
        backend_status, backend_body, _ = request(backend_url)
        proxy_status, proxy_body, headers = request(proxy_url)
    except Exception as exc:
        pytest.fail(f"Failed to access status endpoint: {exc}")

    assert backend_status == 200
    assert proxy_status == backend_status and proxy_body == backend_body, \
        "the response on port 8080 does not match the FastAPI backend"
    try:
        data = json.loads(proxy_body.decode("utf-8"))
    except json.JSONDecodeError:
        pytest.fail(f"Response from {proxy_url} is not valid JSON")
    assert data.get("status") == "secure", f"Response from {proxy_url} is incorrect: {data}"
    assert headers.get("X-Security-Protection") == "active", \
        f"Expected X-Security-Protection: active, got {headers.get('X-Security-Protection')}"

    missing = "/verification-missing-" + secrets.token_hex(16)
    backend_missing = request("http://127.0.0.1:8000" + missing)
    proxy_missing = request("http://127.0.0.1:8080" + missing)
    assert proxy_missing[0] == backend_missing[0]
    assert proxy_missing[1] == backend_missing[1], "Nginx did not proxy an unpredictable path"
    assert proxy_missing[2].get("X-Security-Protection") == "active", \
        "security header is missing from a non-success response"


def test_ssrf_protection_for_derived_local_urls():
    targets = [
        f"http://127.0.0.1:{secrets.randbelow(20000) + 20000}/{secrets.token_hex(10)}",
        f"http://localhost:{secrets.randbelow(20000) + 20000}/{secrets.token_hex(10)}?q={secrets.token_hex(6)}",
        "http://127.0.0.1/admin",
    ]
    for target in targets:
        query = urllib.parse.urlencode({"url": target})
        for base in ("http://127.0.0.1:8000", "http://127.0.0.1:8080"):
            url = f"{base}/fetch?{query}"
            try:
                status, body, headers = request(url)
            except Exception as exc:
                pytest.fail(f"Failed to access {url}: {exc}")
            assert status == 200, f"Unexpected status for blocked URL {target}: {status}"
            try:
                data = json.loads(body.decode("utf-8"))
            except json.JSONDecodeError:
                pytest.fail(f"Response from {url} is not valid JSON")
            assert data.get("error") == "SSRF blocked", f"SSRF protection failed for {target}: {data}"
            if base.endswith(":8080"):
                assert headers.get("X-Security-Protection") == "active"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
