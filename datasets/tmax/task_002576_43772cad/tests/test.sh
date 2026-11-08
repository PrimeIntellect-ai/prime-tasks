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
import concurrent.futures
import os
import re
import secrets
import subprocess
import tempfile

import pytest
import requests

BINARY = "/home/user/math_engine/target/release/math_engine"
URL = "http://127.0.0.1:8080/compute"


def read_spec():
    result = subprocess.run(
        ["tesseract", "/app/system_spec.png", "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=15,
    )
    constant_match = re.search(r"MATH_MAGIC_CONSTANT\s*:\s*([0-9]+(?:\.[0-9]+)?)", result.stdout)
    token_match = re.search(r"API_TOKEN\s*:\s*([^\s]+)", result.stdout)
    assert constant_match, f"Could not extract MATH_MAGIC_CONSTANT from specification: {result.stdout!r}"
    assert token_match, f"Could not extract API_TOKEN from specification: {result.stdout!r}"
    return float(constant_match.group(1)), token_match.group(1)


def test_rust_binary_compiled():
    assert os.path.isfile(BINARY), f"Rust binary not found at {BINARY}. Did you compile it in release mode?"
    assert os.access(BINARY, os.X_OK), f"Rust binary at {BINARY} is not executable."
    with open(BINARY, "rb") as binary_file:
        assert binary_file.read(4) == b"\x7fELF", "The release artifact is not a compiled Linux executable."


def test_rust_binary_computes_random_inputs():
    constant, _ = read_spec()
    values = []
    while len(values) < 6:
        value = secrets.randbelow(20001) - 10000
        if value not in values and value not in (5, 10):
            values.append(value)

    for value in values:
        result = subprocess.run(
            [BINARY, str(value)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        )
        assert result.returncode == 0, f"Rust binary failed for {value}: {result.stderr}"
        try:
            actual = float(result.stdout.strip())
        except ValueError:
            pytest.fail(f"Rust binary produced a non-numeric result for {value}: {result.stdout!r}")
        expected = value * constant
        assert abs(actual - expected) <= max(1e-9, abs(expected) * 1e-12), (
            f"Rust binary returned {actual} for {value}; expected {expected}"
        )


def test_go_server_files_exist():
    assert os.path.isfile("/home/user/go_server/main.go"), "Go server source main.go is missing."
    assert os.path.isfile("/home/user/go_server/go.mod"), "Go module was not initialized (go.mod is missing)."


def test_go_server_unauthorized():
    # Test missing auth header
    try:
        response = requests.post(URL, json={"value": 5}, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Go server at {URL}: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth header, got {response.status_code}"

    # Test invalid auth header
    headers = {"Authorization": "Bearer InvalidToken"}
    response = requests.post(URL, json={"value": 5}, headers=headers, timeout=2)
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid auth header, got {response.status_code}"


def test_go_server_authorized_compute():
    headers = {"Authorization": "Bearer Sigma77Omega"}

    # Test N = 10
    payload = {"value": 10}
    try:
        response = requests.post(URL, json=payload, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Go server at {URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "computed" in data, f"Response missing 'computed' key: {data}"
    expected = 27.182818
    assert abs(data["computed"] - expected) < 1e-6, f"Expected computed value close to {expected}, got {data['computed']}"

    # Test N = 5
    response = requests.post(URL, json={"value": 5}, headers=headers, timeout=2)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "computed" in data, f"Response missing 'computed' key: {data}"
    expected = 13.591409
    assert abs(data["computed"] - expected) < 1e-6, f"Expected computed value close to {expected}, got {data['computed']}"


def test_go_server_randomized_concurrent_compute():
    constant, token = read_spec()
    headers = {"Authorization": f"Bearer {token}"}
    values = []
    while len(values) < 8:
        value = secrets.randbelow(10001) - 5000
        if value not in values and value not in (5, 10):
            values.append(value)

    def request_value(value):
        response = requests.post(URL, json={"value": value}, headers=headers, timeout=4)
        return value, response

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(request_value, values))

    for value, response in results:
        assert response.status_code == 200, f"Concurrent request for {value} returned {response.status_code}: {response.text}"
        data = response.json()
        assert "computed" in data, f"Response missing 'computed' key: {data}"
        expected = value * constant
        assert abs(data["computed"] - expected) < 1e-6, (
            f"Expected computed value close to {expected} for randomized input {value}, got {data['computed']}"
        )


def test_server_executes_release_binary_for_each_request():
    # Temporarily install a different valid Rust executable at the required path.
    # A server that really invokes this path per request must return its output.
    _, token = read_spec()
    value = secrets.randbelow(8000) + 1001
    coefficient = 6.0 + secrets.randbelow(1000000) / 1000000.0
    offset = 0.314159
    expected = value * coefficient + offset
    backup = BINARY + ".verifier_backup"
    assert not os.path.exists(backup), f"Unexpected pre-existing verifier backup at {backup}"

    source_fd, source_path = tempfile.mkstemp(suffix=".rs", prefix="binary_probe_")
    os.close(source_fd)
    with open(source_path, "w") as source_file:
        source_file.write(
            "use std::env;\n"
            "fn main() {\n"
            "  let n: f64 = env::args().nth(1).unwrap().parse().unwrap();\n"
            f"  println!(\"{{}}\", n * {coefficient!r}f64 + {offset!r}f64);\n"
            "}\n"
        )

    os.replace(BINARY, backup)
    try:
        compile_result = subprocess.run(
            ["rustc", "-O", source_path, "-o", BINARY],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"Could not build verifier probe binary: {compile_result.stderr}"
        response = requests.post(
            URL,
            json={"value": value},
            headers={"Authorization": f"Bearer {token}"},
            timeout=4,
        )
        assert response.status_code == 200, f"Probe request returned {response.status_code}: {response.text}"
        data = response.json()
        assert "computed" in data, f"Probe response missing 'computed' key: {data}"
        assert abs(data["computed"] - expected) < 1e-6, (
            "The API did not use the executable at /home/user/math_engine/target/release/math_engine "
            f"for this request: expected {expected}, got {data['computed']}"
        )
    finally:
        try:
            if os.path.exists(BINARY):
                os.unlink(BINARY)
            if os.path.exists(backup):
                os.replace(backup, BINARY)
        finally:
            if os.path.exists(source_path):
                os.unlink(source_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
