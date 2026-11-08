#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import re
import socket
import stat
import subprocess
import time
import urllib.request
import uuid

import pytest

DEPLOY = "/home/user/deploy.sh"
CONFIG = "/home/user/nginx/nginx.conf"
SOCKET = "/home/user/run/python.sock"


def stop_existing_services():
    # Stop known service processes so the verifier tests deploy.sh itself rather
    # than services the agent may have started manually before verification.
    for sig in ("-TERM", "-KILL"):
        for command in (
            ["pkill", sig, "-x", "nginx"],
            ["pkill", sig, "-x", "node"],
            ["pkill", sig, "-f", "gunicorn.*python_api"],
        ):
            subprocess.run(command, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=False)
        time.sleep(0.3)

    try:
        if os.path.lexists(SOCKET) and not os.path.isdir(SOCKET):
            os.unlink(SOCKET)
    except FileNotFoundError:
        pass


def request(url, timeout=1.0):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.getcode(), response.read()


def unix_request(path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(2)
    try:
        client.connect(path)
        client.sendall(
            b"GET /python HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        )
        chunks = []
        while True:
            data = client.recv(65536)
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks)
    finally:
        client.close()


def real_nginx_is_running():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            executable = os.path.realpath(f"/proc/{entry}/exe")
            command = open(f"/proc/{entry}/comm", encoding="utf-8").read().strip()
            if command == "nginx" and executable == "/usr/sbin/nginx":
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return False


@pytest.fixture(scope="session", autouse=True)
def deployed_services():
    assert os.path.isfile(DEPLOY), f"Deploy script not found at {DEPLOY}"
    assert os.access(DEPLOY, os.X_OK), f"Deploy script at {DEPLOY} is not executable"
    assert os.path.isfile("/home/user/bench.py"), "Benchmark script missing at /home/user/bench.py"

    stop_existing_services()
    try:
        result = subprocess.run(
            ["/bin/bash", DEPLOY],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=20,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("deploy.sh did not return; all services must be started in the background")

    assert result.returncode == 0, f"deploy.sh exited with status {result.returncode}"

    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            py_status, _ = request("http://127.0.0.1:8080/python", 0.5)
            node_status, _ = request("http://127.0.0.1:8080/node", 0.5)
            if py_status == 200 and node_status == 200:
                break
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    else:
        pytest.fail(f"Services did not become ready after deploy.sh: {last_error}")

    yield


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(DEPLOY), f"Deploy script not found at {DEPLOY}"
    assert os.access(DEPLOY, os.X_OK), f"Deploy script at {DEPLOY} is not executable"


def test_nginx_configuration_has_diagram_upstreams():
    assert os.path.isfile(CONFIG), f"Nginx configuration missing at {CONFIG}"
    text = open(CONFIG, encoding="utf-8").read()

    python_location = re.search(r"location\s+/python\s*\{([^{}]*)\}", text, re.S)
    node_location = re.search(r"location\s+/node\s*\{([^{}]*)\}", text, re.S)
    assert python_location, "Nginx location /python is missing"
    assert node_location, "Nginx location /node is missing"
    assert re.search(
        r"proxy_pass\s+http://unix:/home/user/run/python\.sock\s*;",
        python_location.group(1),
    ), "location /python does not use the Unix socket from the architecture diagram"
    assert re.search(
        r"proxy_pass\s+http://127\.0\.0\.1:8081\s*;",
        node_location.group(1),
    ), "location /node does not use port 8081 from the architecture diagram"

    checked = subprocess.run(
        ["nginx", "-t", "-c", CONFIG],
        capture_output=True,
        text=True,
        check=False,
    )
    assert checked.returncode == 0, f"Nginx configuration is invalid: {checked.stderr}"


def test_real_upstreams_and_nginx_remain_running():
    assert real_nginx_is_running(), "A real Nginx process is not running"

    info = os.stat(SOCKET)
    assert stat.S_ISSOCK(info.st_mode), f"Python upstream path is not a Unix socket: {SOCKET}"
    python_response = unix_request(SOCKET)
    assert python_response.startswith(b"HTTP/1.1 200"), "Python Unix-socket upstream did not return HTTP 200"
    assert b"Hello from Python" in python_response

    node_status, node_body = request("http://127.0.0.1:8081/node")
    assert node_status == 200, "Node upstream is not listening successfully on port 8081"
    assert b"Hello from Node" in node_body


def test_benchmark_success_rate():
    # Compute the metric independently; do not trust output from the agent-writable bench.py.
    def one_pair(_):
        nonce = uuid.uuid4().hex
        try:
            py_status, _ = request(f"http://127.0.0.1:8080/python?verify={nonce}")
            node_status, _ = request(f"http://127.0.0.1:8080/node?verify={nonce}")
            return py_status == 200 and node_status == 200
        except Exception:
            return False

    total = 100
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
        successes = sum(pool.map(one_pair, range(total)))

    success_rate = successes / total
    threshold = 0.95
    assert success_rate >= threshold, (
        f"Success rate {success_rate} is below the required threshold of {threshold}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
