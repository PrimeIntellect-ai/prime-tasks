#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import subprocess
import time

import pytest

FLOAT4 = re.compile(r"^-?(?:0|[1-9][0-9]*)\.[0-9]{4}$")


def covariance(rows):
    n = len(rows)
    assert n >= 2
    means = [sum(row[j] for row in rows) / n for j in range(3)]
    return [
        [sum((row[i] - means[i]) * (row[j] - means[j]) for row in rows) / (n - 1)
         for j in range(3)]
        for i in range(3)
    ]


def assert_matrix(text, expected, strict_lines=False):
    lines = text.splitlines() if strict_lines else [line.strip() for line in text.splitlines() if line.strip()]
    assert len(lines) == 3, f"Expected exactly 3 matrix lines, got: {text!r}"
    for i, line in enumerate(lines):
        fields = line.split(',')
        assert len(fields) == 3, f"Line does not contain 3 comma-separated values: {line!r}"
        for j, field in enumerate(fields):
            assert FLOAT4.fullmatch(field), f"Value is not formatted to exactly 4 decimal places: {field!r}"
            actual = float(field)
            assert abs(actual - expected[i][j]) <= 0.000051, (
                f"Wrong covariance at ({i},{j}): expected {expected[i][j]}, got {actual}"
            )


def random_rows():
    rng = secrets.SystemRandom()
    n = rng.randint(3, 9)
    rows = []
    for k in range(n):
        # Mixed independent and correlated terms make hardcoded constant matrices fail.
        a = rng.randint(-30, 30)
        b = rng.randint(-20, 20) + 2 * k
        c = rng.randint(-25, 25) - a + 3 * b
        rows.append((a, b, c))
    return rows


def wait_for_port(port, host='127.0.0.1', timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            if sock.connect_ex((host, port)) == 0:
                return True
        time.sleep(0.1)
    return False


@pytest.fixture(scope="session", autouse=True)
def ensure_service_running():
    script_path = "/home/user/start_service.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    proc = None
    if not wait_for_port(8888, timeout=1):
        proc = subprocess.Popen([script_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert wait_for_port(8888, timeout=5), "Service did not start listening on port 8888"
    yield
    if proc is not None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()


def send_payload(payload: str) -> str:
    deadline = time.time() + 4
    while True:
        try:
            sock = socket.create_connection(('127.0.0.1', 8888), timeout=2)
            break
        except OSError:
            if time.time() >= deadline:
                raise
            time.sleep(0.1)

    with sock:
        sock.settimeout(8)
        sock.sendall(payload.encode('utf-8'))
        sock.shutdown(socket.SHUT_WR)
        response = b""
        while True:
            data = sock.recv(4096)
            if not data:
                break
            response += data
    return response.decode('utf-8').strip()


def test_files_exist():
    assert os.path.exists("/home/user/covar.cpp"), "C++ source file /home/user/covar.cpp is missing"
    assert os.path.isfile("/home/user/covar.cpp"), "/home/user/covar.cpp is not a regular file"
    assert os.path.exists("/home/user/covar"), "Compiled binary /home/user/covar is missing"
    assert os.path.isfile("/home/user/covar"), "/home/user/covar is not a regular file"
    assert os.access("/home/user/covar", os.X_OK), "/home/user/covar is not executable"
    with open("/home/user/covar", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/covar is not a compiled ELF binary"


def test_covar_binary_recomputes_varied_inputs():
    for _ in range(6):
        rows = random_rows()
        csv_data = ''.join(','.join(str(value) for value in row) + '\n' for row in rows)
        result = subprocess.run(
            ["/home/user/covar"],
            input=csv_data,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert result.returncode == 0, f"covar exited {result.returncode}: {result.stderr}"
        assert_matrix(result.stdout, covariance(rows), strict_lines=True)


def test_valid_schema():
    payload = "featA,featB,featC\n1.0,2.0,3.0\n4.0,5.0,6.0\n7.0,8.0,9.0\n"
    expected = "9.0000,9.0000,9.0000\n9.0000,9.0000,9.0000\n9.0000,9.0000,9.0000"
    response = send_payload(payload)
    response_lines = [line.strip() for line in response.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected.splitlines() if line.strip()]
    assert response_lines == expected_lines, f"Expected covariance matrix:\n{expected}\nGot:\n{response}"


def test_service_recomputes_varied_valid_payloads_sequentially():
    seen = set()
    for _ in range(5):
        rows = random_rows()
        payload = "featA,featB,featC\n" + ''.join(
            ','.join(f"{value}.0" for value in row) + '\n' for row in rows
        )
        response = send_payload(payload)
        assert response != "ERR_SCHEMA", f"Validator rejected a valid payload: {payload!r}"
        assert_matrix(response, covariance(rows))
        seen.add(response)
    assert len(seen) >= 2, "Service returned the same hardcoded response for varied datasets"


def test_invalid_schema_wrong_header():
    payload = "f1,f2,f3\n1.0,2.0,3.0\n"
    expected = "ERR_SCHEMA"
    response = send_payload(payload)
    assert response == expected, f"Expected {expected} for wrong header, got: {response}"


def test_invalid_schema_missing_columns():
    payload = "featA,featB,featC\n1.0,2.0\n"
    expected = "ERR_SCHEMA"
    response = send_payload(payload)
    assert response == expected, f"Expected {expected} for missing columns, got: {response}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
