#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest

SERVER = "/home/user/math_service/server"
SOURCE = "/home/user/math_service/server.cpp"
MAKEFILE = "/home/user/math_service/Makefile"
PROJECT = "/home/user/math_service"
NGINX_CONFIG = "/home/user/proxy/nginx.conf"


def true_f(x):
    return 2.5 * math.sin(x) + 1.2 * math.cos(x) + 0.3 * (x ** 2)


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            try:
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if local_port == port:
                result.add(fields[9])
    return result


def pids_holding(inodes):
    holders = set()
    if not inodes:
        return holders
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        holders.add(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return holders


def stop_port(port):
    pids = pids_holding(listener_inodes(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_inodes(port):
        time.sleep(0.05)
    for pid in pids_holding(listener_inodes(port)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_inodes(port):
        time.sleep(0.05)
    assert not listener_inodes(port), f"Could not free port {port} to run the rebuilt submission"


def assert_nginx_owns_proxy_port():
    inodes = listener_inodes(8080)
    assert inodes, "Nothing is listening on reverse-proxy port 8080"
    holders = pids_holding(inodes)
    assert holders, "Could not identify the process listening on port 8080"
    executables = []
    for pid in holders:
        try:
            executables.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert any(os.path.basename(path) == "nginx" for path in executables), (
        f"Port 8080 is not being served by Nginx; listener executables were {executables}"
    )


def query(x):
    req = urllib.request.Request("http://127.0.0.1:8080/compute", method="POST")
    req.add_header("Content-Type", "application/json")
    data = json.dumps({"x": x}).encode("utf-8")
    try:
        response = urllib.request.urlopen(req, data=data, timeout=2)
        assert response.status == 200, f"The API returned HTTP {response.status} for x={x}"
        response_body = response.read().decode("utf-8")
    except urllib.error.URLError as e:
        pytest.fail(
            f"Failed to connect to the reverse proxy at 127.0.0.1:8080 for x={x}. "
            f"Error: {e}. Ensure both the C++ server and Nginx proxy are running."
        )
    except Exception as e:
        pytest.fail(f"Unexpected error when querying the API for x={x}: {e}")

    try:
        result_json = json.loads(response_body)
    except json.JSONDecodeError:
        pytest.fail(f"The API response was not valid JSON: {response_body}")
    assert isinstance(result_json, dict), f"The API response was not a JSON object: {result_json}"
    assert "result" in result_json, f"The JSON response is missing the 'result' key: {result_json}"
    try:
        predicted = float(result_json["result"])
    except (ValueError, TypeError):
        pytest.fail(
            f"The 'result' value in the JSON response could not be converted to a float: "
            f"{result_json['result']}"
        )
    assert math.isfinite(predicted), f"The API returned a non-finite result for x={x}: {predicted}"
    return predicted


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_run_submission():
    assert os.path.isfile(SERVER), (
        "The C++ server executable was not found at /home/user/math_service/server. "
        "Make sure you fixed the Makefile and compiled the code successfully."
    )
    assert os.path.isfile(NGINX_CONFIG), (
        "The Nginx configuration file was not found at /home/user/proxy/nginx.conf."
    )
    assert os.path.isfile(SOURCE), "The required C++ implementation server.cpp is missing"
    assert os.path.isfile(MAKEFILE), "The required Makefile is missing"

    config_check = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONFIG, "-p", "/home/user/proxy/"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert config_check.returncode == 0, f"Nginx rejected nginx.conf:\n{config_check.stdout}"
    assert_nginx_owns_proxy_port()

    dry_run = subprocess.run(
        ["make", "-B", "-n"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10,
    )
    assert dry_run.returncode == 0, f"The Makefile could not produce a build plan:\n{dry_run.stdout}"
    plan = dry_run.stdout
    assert re.search(r"(^|[ /])(g\+\+|c\+\+)(\s|$)", plan), (
        f"The Makefile does not compile the service as C++:\n{plan}"
    )
    assert "server.cpp" in plan, f"The Makefile does not compile server.cpp:\n{plan}"
    assert "-pthread" in plan, f"The Makefile is still missing the required -pthread flag:\n{plan}"
    assert "libfastmath.a" in plan, f"The Makefile does not link libfastmath.a:\n{plan}"

    stop_port(9090)
    os.remove(SERVER)
    build = subprocess.run(
        ["make", "-B"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
    )
    assert build.returncode == 0, f"make failed to build the submitted service:\n{build.stdout}"
    assert os.path.isfile(SERVER), "make completed without producing the server executable"
    assert os.access(SERVER, os.X_OK), "The server produced by make is not executable"
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The server produced by the C++ build is not an ELF executable"

    log = open("/tmp/rebuilt_math_server.log", "ab", buffering=0)
    process = subprocess.Popen(
        [SERVER], cwd=PROJECT, stdout=log, stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline and not listener_inodes(9090):
        if process.poll() is not None:
            break
        time.sleep(0.05)
    assert process.poll() is None, "The rebuilt C++ server exited instead of remaining running"
    backend_holders = pids_holding(listener_inodes(9090))
    assert process.pid in backend_holders, (
        "The rebuilt /home/user/math_service/server process is not the process serving port 9090"
    )
    assert os.path.realpath(f"/proc/{process.pid}/exe") == os.path.realpath(SERVER), (
        "Port 9090 is not being served by the rebuilt server executable"
    )
    yield


def test_server_executable_exists():
    assert os.path.isfile(SERVER), (
        "The C++ server executable was not found at /home/user/math_service/server. "
        "Make sure you fixed the Makefile and compiled the code successfully."
    )


def test_nginx_config_exists():
    assert os.path.isfile(NGINX_CONFIG), (
        "The Nginx configuration file was not found at /home/user/proxy/nginx.conf."
    )


def test_api_mse_threshold():
    test_points = [0.0, 1.0, 2.5, 3.14, -1.5, 10.0]
    mse = 0.0
    threshold = 0.001
    for x in test_points:
        predicted = query(x)
        actual = true_f(x)
        mse += (predicted - actual) ** 2
    mse /= len(test_points)
    assert mse < threshold, (
        f"The Mean Squared Error (MSE) of your API's responses is {mse:.6f}, "
        f"which is not below the required threshold of {threshold}. "
        "Check your mathematical formula and extracted coefficients."
    )


def test_api_on_unpredictable_inputs_and_processes():
    rng = secrets.SystemRandom()
    points = [rng.uniform(-25.0, 25.0) for _ in range(32)]
    mse = sum((query(x) - true_f(x)) ** 2 for x in points) / len(points)
    assert mse < 0.001, (
        f"The API's MSE on verifier-generated inputs is {mse:.6f}, which is not below 0.001"
    )
    assert_nginx_owns_proxy_port()
    holders = pids_holding(listener_inodes(9090))
    executables = []
    for pid in holders:
        try:
            executables.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert os.path.realpath(SERVER) in executables, (
        f"The rebuilt server executable is not serving backend port 9090: {executables}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
