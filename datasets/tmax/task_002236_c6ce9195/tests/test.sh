#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import zlib
import pytest

CONF_PATH = "/home/user/nginx_ws.conf"
BIN_PATH = "/home/user/runner_id.bin"
C_FILE_PATH = "/home/user/calc_proxy.c"
COMPILED_PATH = "/tmp/calc_proxy_verifier"


def run_program():
    result = subprocess.run(
        [COMPILED_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled C program failed with exit code {result.returncode}:\n"
        f"{result.stderr.decode(errors='replace')}"
    )
    try:
        return result.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        pytest.fail(f"C program did not print a text Nginx configuration: {exc}")


def assert_required_content(conf_content, expected_crc32):
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9090/?\s*;", conf_content, re.IGNORECASE), \
        "proxy_pass to http://127.0.0.1:9090 is missing or incorrect."
    assert re.search(r"proxy_set_header\s+Upgrade\s+", conf_content, re.IGNORECASE), \
        "WebSocket Upgrade header configuration is missing."
    assert re.search(r"proxy_set_header\s+Connection\s+", conf_content, re.IGNORECASE), \
        "WebSocket Connection header configuration is missing."
    checksum_regex = rf"proxy_set_header\s+X-Runner-Checksum\s+[\"']?{expected_crc32}[\"']?\s*;"
    assert re.search(checksum_regex, conf_content, re.IGNORECASE), \
        f"X-Runner-Checksum header with value {expected_crc32} is missing or incorrect."
    assert re.search(r"listen\s+8080\s*;", conf_content, re.IGNORECASE), \
        "A server listening on port 8080 is missing."
    assert re.search(r"location\s+(?:=\s*)?/logs(?:\s|\{)", conf_content, re.IGNORECASE), \
        "The location /logs block is missing."


def assert_nginx_valid(conf_content):
    fd, path = tempfile.mkstemp(prefix="generated_proxy_", suffix=".conf", dir="/tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(conf_content)
        result = subprocess.run(
            ["nginx", "-t", "-c", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, f"Generated Nginx configuration test failed:\n{result.stderr}"
    finally:
        if os.path.exists(path):
            os.unlink(path)


@pytest.fixture(scope="session", autouse=True)
def compile_and_verify_generator():
    assert os.path.isfile(C_FILE_PATH), f"C program not found at {C_FILE_PATH}"
    result = subprocess.run(
        ["gcc", "-Wall", "-Wextra", C_FILE_PATH, "-o", COMPILED_PATH, "-lz"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30
    )
    assert result.returncode == 0, f"Failed to compile calc_proxy.c with zlib:\n{result.stderr}"

    symbols = subprocess.run(
        ["nm", "-D", COMPILED_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10
    )
    assert symbols.returncode == 0, f"Could not inspect compiled program:\n{symbols.stderr}"
    assert re.search(r"\bU\s+crc32(?:_z)?(?:@[^\s]+)?\s*$", symbols.stdout, re.MULTILINE), \
        "The compiled C program does not use zlib's crc32 function."

    generated = run_program()
    assert os.path.isfile(CONF_PATH), f"Nginx configuration file not found at {CONF_PATH}"
    with open(CONF_PATH, "r") as f:
        saved = f.read()
    assert generated == saved, \
        "nginx_ws.conf is not the configuration produced by the compiled calc_proxy.c program."


def test_c_file_exists():
    assert os.path.isfile(C_FILE_PATH), f"C program not found at {C_FILE_PATH}"


def test_nginx_conf_exists():
    assert os.path.isfile(CONF_PATH), f"Nginx configuration file not found at {CONF_PATH}"


def test_nginx_conf_content():
    assert os.path.isfile(BIN_PATH), f"File {BIN_PATH} is missing."
    with open(BIN_PATH, "rb") as f:
        content = f.read()

    expected_crc32 = zlib.crc32(content) & 0xFFFFFFFF

    with open(CONF_PATH, "r") as f:
        conf_content = f.read()

    # Check proxy_pass
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9090/?\s*;", conf_content, re.IGNORECASE), \
        "proxy_pass to http://127.0.0.1:9090 is missing or incorrect."

    # Check WebSocket Upgrade headers
    assert re.search(r"proxy_set_header\s+Upgrade\s+", conf_content, re.IGNORECASE), \
        "WebSocket Upgrade header configuration is missing."
    assert re.search(r"proxy_set_header\s+Connection\s+", conf_content, re.IGNORECASE), \
        "WebSocket Connection header configuration is missing."

    # Check X-Runner-Checksum header
    checksum_regex = rf"proxy_set_header\s+X-Runner-Checksum\s+[\"']?{expected_crc32}[\"']?\s*;"
    assert re.search(checksum_regex, conf_content, re.IGNORECASE), \
        f"X-Runner-Checksum header with value {expected_crc32} is missing or incorrect."


def test_nginx_conf_validity():
    assert os.path.isfile(CONF_PATH), f"Nginx configuration file not found at {CONF_PATH}"

    result = subprocess.run(
        ["nginx", "-t", "-c", CONF_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    assert result.returncode == 0, f"Nginx configuration test failed:\n{result.stderr}"


def test_program_recomputes_crc32_for_binary_inputs():
    with open(BIN_PATH, "rb") as f:
        original = f.read()

    cases = [
        b"",
        b"verifier-random-prefix\x00\xff" + os.urandom(73),
        os.urandom(4097),
    ]
    try:
        for payload in cases:
            with open(BIN_PATH, "wb") as f:
                f.write(payload)
            generated = run_program()
            expected_crc32 = zlib.crc32(payload) & 0xFFFFFFFF
            assert_required_content(generated, expected_crc32)
            assert_nginx_valid(generated)
    finally:
        with open(BIN_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
