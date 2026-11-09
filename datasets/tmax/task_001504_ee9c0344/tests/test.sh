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
import json
import os
import random
import secrets
import signal
import socket
import subprocess
import tempfile
import time

import pytest
import requests

APP = "/home/user/app"
BACKEND_DIR = os.path.join(APP, "backend")
PROXY_DIR = os.path.join(APP, "proxy")
BACKEND = os.path.join(BACKEND_DIR, "backend_server")
PROXY = os.path.join(PROXY_DIR, "proxy_server")


def get_redis_list(list_name):
    result = subprocess.run(
        ["redis-cli", "LRANGE", list_name, "0", "-1"],
        capture_output=True, text=True, check=True
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def listener_pids(ports):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port in ports:
                            inodes.add(fields[9])
        except FileNotFoundError:
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
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_existing_services():
    for pid in listener_pids({8080, 8081}):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids({8080, 8081}):
        time.sleep(0.05)
    for pid in listener_pids({8080, 8081}):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.1)


def wait_for_port(port, process):
    deadline = time.time() + 4
    while time.time() < deadline:
        assert process.poll() is None, f"Service for port {port} exited early"
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail(f"Service did not listen on 127.0.0.1:{port}")


def wait_for_lists(expected_valid, expected_invalid):
    deadline = time.time() + 4
    while time.time() < deadline:
        valid = get_redis_list("releases:valid")
        invalid = get_redis_list("releases:invalid")
        if valid == expected_valid and invalid == expected_invalid:
            return valid, invalid
        time.sleep(0.05)
    pytest.fail(
        f"Redis contents did not match. Expected valid={expected_valid}, "
        f"invalid={expected_invalid}; actual valid={get_redis_list('releases:valid')}, "
        f"invalid={get_redis_list('releases:invalid')}"
    )


def classify(version):
    raw = version[1:] if version.startswith("v") else version
    major, minor, patch = (int(part) for part in raw.split("."))
    return "releases:valid" if (major, minor, patch) >= (2, 0, 0) else "releases:invalid"


def make_dynamic_cases(count=24):
    rng = random.SystemRandom()
    cases = []
    boundary_versions = ["0.0.0", "1.999.999", "1.0.200", "2.0.0", "v2.0.1", "v10.0.0"]
    for version in boundary_versions:
        data = "dynamic_" + secrets.token_hex(10)
        cases.append((f"{version}|{data}", classify(version), data))
    while len(cases) < count:
        major = rng.randrange(0, 15)
        minor = rng.randrange(0, 1000)
        patch = rng.randrange(0, 1000)
        prefix = "v" if rng.randrange(2) else ""
        version = f"{prefix}{major}.{minor}.{patch}"
        data = "dynamic_" + secrets.token_hex(10)
        cases.append((f"{version}|{data}", classify(version), data))
    rng.shuffle(cases)
    return cases


def reset_redis():
    subprocess.run(
        ["redis-cli", "DEL", "releases:valid", "releases:invalid"],
        check=True, capture_output=True, text=True
    )


def test_end_to_end_telemetry():
    with open(os.path.join(PROXY_DIR, "config.json")) as f:
        cfg = json.load(f)
    assert cfg.get("listen_addr") == "127.0.0.1:8080"
    assert cfg.get("backend_addr") == "127.0.0.1:8081"

    with open(os.path.join(BACKEND_DIR, "Makefile")) as f:
        makefile = f.read()
    assert "-lhiredis" in makefile, "Makefile must link the backend with -lhiredis"

    stop_existing_services()
    try:
        os.remove(BACKEND)
    except FileNotFoundError:
        pass
    build = subprocess.run(
        ["make"], cwd=BACKEND_DIR, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(BACKEND) and os.access(BACKEND, os.X_OK)
    assert os.path.isfile(PROXY) and os.access(PROXY, os.X_OK)
    with open(BACKEND, "rb") as f:
        assert f.read(4) == b"\x7fELF", "backend_server must be a compiled executable"
    with open(PROXY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "proxy_server must be a compiled executable"

    linked = subprocess.run(["ldd", BACKEND], capture_output=True, text=True, check=True)
    assert "libhiredis" in linked.stdout, "backend_server is not linked against hiredis"

    with tempfile.TemporaryDirectory() as td:
        source_check = subprocess.run(
            ["gcc", "server.c", "-o", os.path.join(td, "source_backend"), "-lhiredis"],
            cwd=BACKEND_DIR, capture_output=True, text=True, timeout=30
        )
        assert source_check.returncode == 0, (
            f"server.c does not compile with hiredis:\n{source_check.stdout}\n{source_check.stderr}"
        )

    backend_proc = subprocess.Popen(
        [BACKEND], cwd=BACKEND_DIR, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    wait_for_port(8081, backend_proc)
    proxy_proc = subprocess.Popen(
        [PROXY], cwd=PROXY_DIR, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    wait_for_port(8080, proxy_proc)

    # Exercise the compiled C backend directly with unpredictable versions/data.
    direct_cases = make_dynamic_cases()
    reset_redis()
    expected_valid = []
    expected_invalid = []
    for payload, expected_list, data in direct_cases:
        with socket.create_connection(("127.0.0.1", 8081), timeout=2) as conn:
            conn.sendall(payload.encode())
            conn.shutdown(socket.SHUT_WR)
        (expected_valid if expected_list == "releases:valid" else expected_invalid).append(data)
    wait_for_lists(expected_valid, expected_invalid)

    # Preserve the original fixed end-to-end cases and add randomized cases.
    fixed_cases = [
        ("v2.5.0|success_deploy", "releases:valid", "success_deploy"),
        ("1.1.9|fail_deploy", "releases:invalid", "fail_deploy"),
        ("2.0.0|edge_valid", "releases:valid", "edge_valid"),
        ("v1.9.9|edge_invalid", "releases:invalid", "edge_invalid"),
        ("10.0.0|future_deploy", "releases:valid", "future_deploy"),
    ]
    test_cases = fixed_cases + make_dynamic_cases()
    reset_redis()
    expected_valid = []
    expected_invalid = []
    for payload, expected_list, expected_data in test_cases:
        try:
            resp = requests.post("http://127.0.0.1:8080/", data=payload, timeout=2)
            assert resp.status_code == 200, (
                f"Expected HTTP 200 from proxy, got {resp.status_code} for payload: {payload}"
            )
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to the Go proxy on 127.0.0.1:8080: {e}")
        (expected_valid if expected_list == "releases:valid" else expected_invalid).append(expected_data)

    valid_list, invalid_list = wait_for_lists(expected_valid, expected_invalid)

    # Retain the original membership assertions as well as exact-list validation.
    for payload, expected_list, expected_data in test_cases:
        if expected_list == "releases:valid":
            assert expected_data in valid_list, (
                f"Expected '{expected_data}' in Redis list 'releases:valid' (from payload '{payload}'). "
                f"Actual contents: {valid_list}"
            )
        else:
            assert expected_data in invalid_list, (
                f"Expected '{expected_data}' in Redis list 'releases:invalid' (from payload '{payload}'). "
                f"Actual contents: {invalid_list}"
            )

    assert backend_proc.poll() is None, "backend_server stopped running"
    assert proxy_proc.poll() is None, "proxy_server stopped running"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
