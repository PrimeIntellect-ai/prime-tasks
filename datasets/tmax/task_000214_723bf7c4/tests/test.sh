#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import re
import subprocess
import time
import urllib.error
import urllib.request

import pytest

URL = "http://127.0.0.1:8080/api/determinant"


def determinant(values):
    a, b, c, d, e, f, g, h, i = values
    return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)


def encoded_payload(values):
    raw = " ".join(str(value) for value in values).encode("ascii")
    return base64.b64encode(raw).decode("ascii")


def post(payload):
    data = json.dumps({"payload": payload}).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except urllib.error.URLError as exc:
        pytest.fail(f"Could not connect to server on port 8080: {exc.reason}")


def listening_processes(port):
    socket_inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1] == wanted_port and fields[3] == "0A":
                        socket_inodes.add(fields[9])
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
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def test_server_binary_exists():
    """Check if the compiled server binary exists and is executable."""
    binary_path = "/home/user/server_bin"
    assert os.path.isfile(binary_path), f"Server binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Server binary at {binary_path} is not executable"
    with open(binary_path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "server_bin is not a compiled ELF executable"


def test_cpp_source_and_binary_are_the_running_server():
    source_path = "/home/user/server.cpp"
    binary_path = "/home/user/server_bin"
    assert os.path.isfile(source_path), f"C++ source not found at {source_path}"

    binary_stat = os.stat(binary_path)
    pids = listening_processes(8080)
    assert pids, "No process is listening on port 8080"

    matching = False
    for pid in pids:
        try:
            executable_stat = os.stat(f"/proc/{pid}/exe")
            if (executable_stat.st_dev, executable_stat.st_ino) == (binary_stat.st_dev, binary_stat.st_ino):
                matching = True
                break
        except (FileNotFoundError, PermissionError):
            pass
    assert matching, "The process listening on port 8080 is not /home/user/server_bin"


def test_verification_log_exists():
    """Check if the verification log file exists."""
    log_path = "/home/user/verification.log"
    assert os.path.isfile(log_path), f"Verification log not found at {log_path}"


def test_test_script_executes_and_writes_status_codes():
    script_path = "/home/user/test_server.sh"
    log_path = "/home/user/verification.log"
    assert os.path.isfile(script_path), f"Verification script not found at {script_path}"

    script = open(script_path, "r", encoding="utf-8", errors="replace").read()
    assert "curl" in script, "test_server.sh must use curl"
    assert "MiAwIDAgMCAyIDAgMCAwIDI=" in script, "test_server.sh does not use the required valid payload"
    assert "/home/user/verification.log" in script, "test_server.sh does not write the required log"

    time.sleep(1.1)
    before = time.time_ns()
    result = subprocess.run(
        ["bash", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, (
        f"test_server.sh failed with exit code {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(log_path), "test_server.sh did not create verification.log"
    assert os.stat(log_path).st_mtime_ns >= before, "test_server.sh did not refresh verification.log"

    log = open(log_path, "r", encoding="utf-8", errors="replace").read()
    codes = [int(code) for code in re.findall(r"(?<!\d)([1-5]\d\d)(?!\d)", log)]
    assert len(codes) >= 6, f"Expected status codes for at least six requests, found: {codes}"
    assert 200 in codes, f"verification.log contains no successful request: {codes}"
    assert 400 in codes, f"verification.log contains no invalid-shape response: {codes}"
    assert 429 in codes, f"verification.log contains no rate-limit response: {codes}"


def test_api_valid_determinant():
    """Retain the original fixed determinant assertion."""
    time.sleep(1.1)
    status, body = post("MSAyIDMgMCAxIDQgNSA2IDA=")
    assert status == 200, f"Expected HTTP 200, got {status}: {body.decode('utf-8', errors='replace')}"
    response = json.loads(body.decode("utf-8"))
    assert response.get("determinant") == 1, f"Expected determinant 1, got {response.get('determinant')}"


def test_api_randomized_determinants_and_base64_decoding():
    """Exercise unpredictable matrices whose answers are derived by the verifier."""
    rng = random.SystemRandom()
    matrices = []
    while len(matrices) < 8:
        values = [rng.randint(-50, 50) for _ in range(9)]
        if values not in matrices:
            matrices.append(values)

    for offset in range(0, len(matrices), 2):
        time.sleep(1.1)
        for values in matrices[offset:offset + 2]:
            status, body = post(encoded_payload(values))
            assert status == 200, f"Expected HTTP 200 for {values}, got {status}"
            try:
                response = json.loads(body.decode("utf-8"))
            except Exception as exc:
                pytest.fail(f"Response for {values} is not valid JSON: {exc}; body={body!r}")
            expected = determinant(values)
            assert response.get("determinant") == expected, (
                f"Wrong determinant for {values}: expected {expected}, got {response.get('determinant')}"
            )


def test_api_invalid_shape():
    """Retain the original invalid matrix assertion."""
    time.sleep(1.1)
    status, _ = post("MSAy")
    assert status == 400, f"Expected HTTP 400, got {status}"


def test_api_randomized_invalid_shape():
    rng = random.SystemRandom()
    count = rng.choice([1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13])
    values = [rng.randint(-100, 100) for _ in range(count)]
    time.sleep(1.1)
    status, _ = post(encoded_payload(values))
    assert status == 400, f"Expected HTTP 400 for {count} integers, got {status}"


def test_api_rate_limiting():
    """Test the original exact two-success/two-rejection rate-limit assertion with unpredictable inputs."""
    time.sleep(1.1)
    rng = random.SystemRandom()
    matrices = [[rng.randint(-20, 20) for _ in range(9)] for _ in range(4)]

    statuses = []
    for values in matrices:
        status, body = post(encoded_payload(values))
        statuses.append(status)
        if status == 200:
            response = json.loads(body.decode("utf-8"))
            assert response.get("determinant") == determinant(values), (
                f"Wrong determinant during rate-limit test for {values}"
            )

    count_200 = statuses.count(200)
    count_429 = statuses.count(429)
    assert count_200 == 2, f"Expected exactly two 200 OK responses, got {count_200}. Statuses: {statuses}"
    assert count_429 == 2, f"Expected exactly two 429 Too Many Requests responses, got {count_429}. Statuses: {statuses}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
