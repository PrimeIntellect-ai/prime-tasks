#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH=/usr/local/go/bin:$PATH

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

BINARY = "/home/user/release/math-api"
WORKSPACE = "/home/user/workspace"
BASE_URL = "http://127.0.0.1:8080"


def request(path, method="GET"):
    req = urllib.request.Request(BASE_URL + path, method=method)
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status, response.read().decode("utf-8").strip(), response.headers
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8").strip(), error.headers


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Release binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"File at {BINARY} is not executable"
    with open(BINARY, "rb") as artifact:
        assert artifact.read(4) == b"\x7fELF", "Release artifact is not an ELF executable"
    result = subprocess.run(["go", "version", "-m", BINARY], capture_output=True, text=True)
    assert result.returncode == 0, f"Release artifact is not a Go executable:\n{result.stdout}\n{result.stderr}"


def test_go_test_passes():
    result = subprocess.run(["go", "test"], cwd=WORKSPACE, capture_output=True, text=True)
    assert result.returncode == 0, f"'go test' failed. Output:\n{result.stdout}\n{result.stderr}"


def test_gcd_is_the_greatest_common_divisor():
    cases = [
        (0, 0), (0, 37), (37, 0), (0, -37), (-37, 0),
        (1, 1), (-1, 1), (1, -1), (-1, -1),
        (48, 18), (-21, 14), (21, -14), (-21, -14),
        (17, 19), (270, 192), (4611686018427387902, 2147483646),
    ]
    rng = secrets.SystemRandom()
    for _ in range(80):
        cases.append((rng.randrange(-(1 << 62), 1 << 62),
                      rng.randrange(-(1 << 62), 1 << 62)))

    entries = ",\n".join(
        f"{{a: {a}, b: {b}, want: {math.gcd(a, b)}}}" for a, b in cases
    )
    source = f'''package main

import "testing"

func TestVerifierExactGCD(t *testing.T) {{
    cases := []struct {{ a, b, want int64 }}{{
{entries}
    }}
    for _, tc := range cases {{
        if got := GCD(tc.a, tc.b); got != tc.want {{
            t.Fatalf("GCD(%d, %d) = %d; want %d", tc.a, tc.b, got, tc.want)
        }}
    }}
}}
'''
    test_path = os.path.join(WORKSPACE, f"verifier_{secrets.token_hex(8)}_test.go")
    try:
        with open(test_path, "w", encoding="utf-8") as test_file:
            test_file.write(source)
        result = subprocess.run(
            ["go", "test", "-count=1"], cwd=WORKSPACE, capture_output=True, text=True
        )
        assert result.returncode == 0, (
            f"GCD failed exact randomized checks:\n{result.stdout}\n{result.stderr}"
        )
    finally:
        if os.path.exists(test_path):
            os.unlink(test_path)


def test_api_routing_and_logic():
    process = subprocess.Popen(
        [BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            assert process.poll() is None, "Release binary exited before serving requests"
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            pytest.fail("API did not start listening on port 8080")

        # Preserve the original fixed behavior checks.
        status, body, _ = request("/gcd/-21/14")
        assert status == 200, f"Expected status 200, got {status}"
        assert body == "7", f"Expected GCD 7 for inputs -21 and 14, got '{body}'"

        status2, body2, _ = request("/gcd/48/18")
        assert status2 == 200, f"Expected status 200, got {status2}"
        assert body2 == "6", f"Expected GCD 6 for inputs 48 and 18, got '{body2}'"

        # Exercise values selected only at verification time and derive each answer.
        api_cases = [
            (0, 0), (0, -91), (-91, 0), (17, 19),
            (-270, -192), (999999937, 999999937),
        ]
        rng = secrets.SystemRandom()
        for _ in range(30):
            api_cases.append((rng.randrange(-10**12, 10**12),
                              rng.randrange(-10**12, 10**12)))
        for a, b in api_cases:
            status, body, _ = request(f"/gcd/{a}/{b}")
            expected = str(math.gcd(a, b))
            assert status == 200, f"GET /gcd/{a}/{b} returned status {status}"
            assert body == expected, (
                f"GET /gcd/{a}/{b} returned '{body}', expected '{expected}'"
            )

        # The method-qualified Go 1.22 route must reject other methods.
        status, _, headers = request("/gcd/48/18", method="POST")
        assert status == 405, f"POST to the GCD route should return 405, got {status}"
        assert "GET" in headers.get("Allow", ""), "405 response does not advertise GET"

        # Matched routes with invalid int64 parameters must return Bad Request.
        for path in ("/gcd/not-a-number/5", "/gcd/5/nope", "/gcd/9223372036854775808/1"):
            status, _, _ = request(path)
            assert status == 400, f"Invalid request {path} should return 400, got {status}"

        # Similar but unmatched paths must not be handled as GCD requests.
        for path in ("/gcd", "/gcd/1", "/gcd/1/2/3", "/other/1/2"):
            status, _, _ = request(path)
            assert status == 404, f"Unmatched path {path} should return 404, got {status}"
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
