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
import os
import re
import socket
import subprocess
import time

import pytest
import requests

SRC = "/home/user/server_src"
SERVER = os.path.join(SRC, "http_server")


def request_with_retry(url, auth, retries=5):
    for i in range(retries):
        try:
            return requests.get(url, auth=auth, timeout=2)
        except requests.exceptions.ConnectionError:
            if i == retries - 1:
                pytest.fail(f"Could not connect to the server at {url}.")
            time.sleep(1)


def test_01_server_running_and_auth_works():
    response = request_with_retry(
        "http://127.0.0.1:8080/secure", ("admin", "sunflower")
    )
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}."
    )
    assert "Access Granted" in response.text, (
        f"Expected 'Access Granted' in response body, got: {response.text}"
    )


def test_02_server_rejects_bad_auth():
    response = request_with_retry(
        "http://127.0.0.1:8080/secure", ("admin", "wrongpassword"), retries=1
    )
    assert response.status_code != 200, (
        "Server should not return 200 OK for incorrect credentials."
    )


def test_03_auth_h_updated():
    path = os.path.join(SRC, "auth.h")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "sunflower" in content.lower(), (
        f"Passphrase 'sunflower' not found in {path}."
    )
    definitions = re.findall(
        r'^\s*#\s*define\s+SECRET_PASSPHRASE\s+"([^"]*)"\s*$',
        content,
        flags=re.MULTILINE,
    )
    assert definitions == ["sunflower"], (
        "SECRET_PASSPHRASE must be defined exactly once as lowercase sunflower."
    )


def test_04_bench_results_exist():
    path = "/home/user/bench_results.txt"
    assert os.path.isfile(path), f"Benchmark results file {path} does not exist."
    assert os.path.getsize(path) > 0, f"Benchmark results file {path} is empty."


def test_05_clean_build_tests_benchmark_and_compiled_server():
    for name in (
        "main.o", "http.o", "crypto.o", "test.o", "bench.o",
        "http_server", "test_suite", "bench_suite",
    ):
        try:
            os.remove(os.path.join(SRC, name))
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["make", "all"], cwd=SRC, text=True, capture_output=True, timeout=60
    )
    assert build.returncode == 0, (
        "A clean `make all` failed:\n" + build.stdout + build.stderr
    )

    for name in ("http_server", "test_suite", "bench_suite"):
        path = os.path.join(SRC, name)
        assert os.path.isfile(path), f"Build did not create {path}."
        assert os.access(path, os.X_OK), f"{path} is not executable."
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{path} is not an ELF executable."

    unit = subprocess.run(
        ["make", "test"], cwd=SRC, text=True, capture_output=True, timeout=30
    )
    assert unit.returncode == 0, (
        "`make test` failed:\n" + unit.stdout + unit.stderr
    )
    assert "Tests passed." in unit.stdout, "Unit test success output was missing."

    direct_unit = subprocess.run(
        [os.path.join(SRC, "test_suite")],
        cwd=SRC,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert direct_unit.returncode == 0
    assert "Tests passed." in direct_unit.stdout

    bench = subprocess.run(
        ["make", "bench"], cwd=SRC, text=True, capture_output=True, timeout=30
    )
    assert bench.returncode == 0, (
        "`make bench` failed:\n" + bench.stdout + bench.stderr
    )

    direct_bench = subprocess.run(
        [os.path.join(SRC, "bench_suite")],
        cwd=SRC,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert direct_bench.returncode == 0
    benchmark_output = direct_bench.stdout.strip()
    assert benchmark_output, "Benchmark suite produced no output."
    assert "Benchmark complete." in benchmark_output

    with open("/home/user/bench_results.txt", "r") as f:
        saved_output = f.read()
    assert benchmark_output in saved_output, (
        "bench_results.txt does not contain the benchmark suite's actual output."
    )

    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]

    proc = subprocess.Popen(
        [SERVER, str(port)], cwd=SRC,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        good = request_with_retry(
            f"http://127.0.0.1:{port}/secure", ("admin", "sunflower")
        )
        assert good.status_code == 200
        assert "Access Granted" in good.text

        bad = request_with_retry(
            f"http://127.0.0.1:{port}/secure", ("admin", "wrongpassword"), retries=1
        )
        assert bad.status_code != 200
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
