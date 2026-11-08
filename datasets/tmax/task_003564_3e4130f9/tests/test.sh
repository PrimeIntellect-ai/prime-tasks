#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import time

import pytest
import requests

BINARY = "/app/calculator/target/release/calculator"
PROJECT = "/app/calculator"
BASE_URL = "http://127.0.0.1:8888"
ENDPOINT = f"{BASE_URL}/calculate"


def wait_for_server(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    return False


def post_number(number):
    try:
        resp = requests.post(ENDPOINT, json={"number": number}, timeout=3)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"POST request to {ENDPOINT} failed: {exc}")
    assert resp.status_code == 200, f"Expected status code 200, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {resp.text}")
    assert "result" in data, f"Expected 'result' key in JSON response, got: {data}"
    return data["result"]


def blueprint_constant():
    proc = subprocess.run(
        ["tesseract", "/app/blueprint.png", "stdout", "--psm", "7"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, f"Could not OCR blueprint: {proc.stderr}"
    match = re.search(r"CONSTANT\s*=\s*(-?\d+)", proc.stdout, re.IGNORECASE)
    assert match, f"Could not extract CONSTANT from blueprint OCR output: {proc.stdout!r}"
    return int(match.group(1))


def test_rust_binary_exists_and_runs():
    assert os.path.isfile(BINARY), f"Compiled Rust binary not found at {BINARY}. Did you compile in release mode?"

    # Force the submitted Rust project to compile rather than trusting a file placed
    # at the expected output path.
    clean = subprocess.run(["cargo", "clean"], cwd=PROJECT, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert clean.returncode == 0, f"cargo clean failed: {clean.stderr}"
    build = subprocess.run(["cargo", "build", "--release"], cwd=PROJECT, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    assert build.returncode == 0, f"Rust release build failed: {build.stderr}"

    assert os.path.isfile(BINARY), f"Release build did not create {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Release binary is not executable: {BINARY}"
    with open(BINARY, "rb") as fh:
        assert fh.read(4) == b"\x7fELF", "Release calculator is not an ELF binary"

    constant = blueprint_constant()
    rng = random.SystemRandom()
    values = [rng.randrange(-100000, 100001) for _ in range(8)]
    for number in values:
        proc = subprocess.run([BINARY, str(number)], text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
        assert proc.returncode == 0, f"Calculator failed for {number}: {proc.stderr}"
        try:
            result = int(proc.stdout.strip())
        except ValueError:
            pytest.fail(f"Calculator returned a non-integer for {number}: {proc.stdout!r}")
        assert result == number * constant, f"Wrong binary result for input {number}: {result}"


def test_http_server_calculate_endpoint():
    assert wait_for_server(BASE_URL, timeout=5), f"Could not connect to HTTP server at {BASE_URL}"

    # Preserve the original fixed assertions.
    assert post_number(4) == 420, "Expected result 420 for input 4"
    assert post_number(-2) == -210, "Expected result -210 for input -2"
    assert post_number(0) == 0, "Expected result 0 for input 0"

    # Exercise unpredictable inputs using the constant extracted from the blueprint.
    constant = blueprint_constant()
    rng = random.SystemRandom()
    for _ in range(8):
        number = rng.randrange(-100000, 100001)
        assert post_number(number) == number * constant, f"Wrong HTTP result for input {number}"

    # Replace the binary briefly with a probe. The endpoint must return the probe's
    # output, proving that each request actually invokes the requested artifact.
    saved_binary = BINARY + ".verifier-real"
    assert not os.path.exists(saved_binary), f"Unexpected file blocks verifier probe: {saved_binary}"
    os.replace(BINARY, saved_binary)
    try:
        with open(BINARY, "w", encoding="utf-8") as fh:
            fh.write("#!/bin/sh\necho $(( $1 * 17 + 987654321 ))\n")
        os.chmod(BINARY, 0o755)
        probe_input = rng.randrange(-50000, 50001)
        expected = probe_input * 17 + 987654321
        assert post_number(probe_input) == expected, "HTTP server did not invoke the compiled-binary path"
    finally:
        if os.path.lexists(BINARY):
            os.unlink(BINARY)
        os.replace(saved_binary, BINARY)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
