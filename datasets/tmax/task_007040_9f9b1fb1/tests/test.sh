#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest

WORKSPACE_DIR = "/home/user/gateway-pr"
REVIEW_FILE = "/home/user/pr_review.json"
GATEWAY_BIN = os.path.join(WORKSPACE_DIR, "gateway")
ROUTES_FILE = os.path.join(WORKSPACE_DIR, "routes.json")
SOURCE_BIN = "/tmp/gateway-built-from-main"
PORT = 8080


def test_pr_review_json():
    assert os.path.isfile(REVIEW_FILE), f"Review file {REVIEW_FILE} does not exist."
    with open(REVIEW_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REVIEW_FILE} is not valid JSON.")

    expected = {
        "builds_successfully": True,
        "handles_concurrency": True,
        "benchmark_completed": True,
    }
    assert data == expected, f"Content of {REVIEW_FILE} does not match expected exact structure."


def test_gateway_executable_exists_and_is_go_binary():
    assert os.path.isfile(GATEWAY_BIN), f"Gateway executable {GATEWAY_BIN} was not built."
    assert os.access(GATEWAY_BIN, os.X_OK), f"Gateway executable {GATEWAY_BIN} is not executable."
    with open(GATEWAY_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "gateway is not an ELF executable."
    result = subprocess.run(
        ["go", "version", "-m", GATEWAY_BIN],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0 and "go1" in result.stdout, \
        f"gateway is not a Go executable:\n{result.stdout}"


def listening_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
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


def clear_port():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listening_pids(PORT)
        if not pids:
            return
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        deadline = time.time() + 2
        while time.time() < deadline and listening_pids(PORT):
            time.sleep(0.05)
    assert not listening_pids(PORT), f"Could not clear port {PORT}."


def request(path, timeout=3):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}{path}", timeout=timeout) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")


def start_server(binary):
    clear_port()
    proc = subprocess.Popen(
        [binary],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"{binary} exited before serving requests (status {proc.returncode}).")
        try:
            request("/__verifier_readiness__", timeout=0.3)
            time.sleep(1.15)  # Clear the readiness request from the sliding window.
            return proc
        except Exception:
            time.sleep(0.05)
    stop_server(proc)
    pytest.fail(f"{binary} did not start listening on port {PORT}.")


def stop_server(proc):
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=2)
    clear_port()


def write_config(token):
    dynamic_path = f"/verify/{token}"
    dynamic_target = f"dynamic-service-{token}"
    config = {
        "version": f"verify-{token}",
        "routes": [
            {"path": "/api/v1/users", "target_service": "user-service-backend"},
            {"path": "/api/v1/orders", "target_service": "order-service-backend"},
            {"path": dynamic_path, "target_service": dynamic_target},
        ],
    }
    with open(ROUTES_FILE, "w") as f:
        json.dump(config, f)
    return dynamic_path, dynamic_target


def assert_routes_and_limit(binary, token, burst_size):
    dynamic_path, dynamic_target = write_config(token)
    proc = start_server(binary)
    try:
        # Preserve the original 404 assertion and also use an unpredictable path.
        status, _ = request(f"/invalid-{token}")
        assert status == 404, f"Expected HTTP 404 for unknown route, got {status}."

        time.sleep(1.15)
        status, body = request("/api/v1/users")
        assert status == 200, f"Expected HTTP 200, got {status}."
        assert body == "Routed to user-service-backend", f"Unexpected response body: {body}"

        status, body = request(dynamic_path)
        assert status == 200, f"Expected HTTP 200 for generated route, got {status}."
        assert body == f"Routed to {dynamic_target}", f"Generated route was not parsed: {body}"

        time.sleep(1.15)
        with concurrent.futures.ThreadPoolExecutor(max_workers=burst_size) as pool:
            results = list(pool.map(lambda _: request("/api/v1/orders")[0], range(burst_size)))

        assert results.count(200) == 5, \
            f"Expected exactly 5 successful requests, got {results.count(200)}. Results: {results}"
        assert results.count(429) == burst_size - 5, \
            f"Expected {burst_size - 5} rate-limited requests, got {results.count(429)}. Results: {results}"
        assert all(code in (200, 429) for code in results), f"Unexpected results: {results}"
        assert proc.poll() is None, "Gateway crashed during concurrent requests."
        return proc
    except Exception:
        stop_server(proc)
        raise


def test_submitted_binary_source_and_benchmark():
    with open(ROUTES_FILE, "rb") as f:
        original_routes = f.read()

    active = None
    try:
        # Launch and exercise the submitted artifact itself on verifier-generated routes.
        active = assert_routes_and_limit(GATEWAY_BIN, secrets.token_hex(8), 10)

        time.sleep(1.15)
        benchmark = subprocess.run(
            ["bash", os.path.join(WORKSPACE_DIR, "bench.sh")],
            cwd=WORKSPACE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
        assert benchmark.returncode == 0, f"bench.sh failed:\n{benchmark.stdout}"
        assert "Benchmark finished." in benchmark.stdout, \
            f"bench.sh did not complete normally:\n{benchmark.stdout}"
        assert active.poll() is None, "Gateway crashed while running bench.sh."
        stop_server(active)
        active = None

        # Independently build main.go and execute that result, so a separate dummy
        # gateway artifact cannot hide broken or nonfunctional submitted Go source.
        build = subprocess.run(
            ["go", "build", "-o", SOURCE_BIN, "main.go"],
            cwd=WORKSPACE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"main.go does not build successfully:\n{build.stdout}"
        assert os.path.isfile(SOURCE_BIN) and os.access(SOURCE_BIN, os.X_OK)

        active = assert_routes_and_limit(SOURCE_BIN, secrets.token_hex(8), 8)
        stop_server(active)
        active = None
    finally:
        if active is not None:
            stop_server(active)
        with open(ROUTES_FILE, "wb") as f:
            f.write(original_routes)
        clear_port()
        # Restore the required final state with the submitted Go executable serving
        # the original routing configuration.
        subprocess.Popen(
            [GATEWAY_BIN],
            cwd=WORKSPACE_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.time() + 5
        while time.time() < deadline and not listening_pids(PORT):
            time.sleep(0.05)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
