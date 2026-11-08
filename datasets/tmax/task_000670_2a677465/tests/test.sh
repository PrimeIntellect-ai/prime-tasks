#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import py_compile
import secrets
import string
import subprocess
import tempfile

import pytest
import requests

GATEWAY_URL = "http://127.0.0.1:9090/build"
SEED_VALUE = b"K3yV4lUe99"


def compile_and_hash(source_code):
    with tempfile.TemporaryDirectory() as td:
        asm_file = os.path.join(td, "input.asm")
        obj_file = os.path.join(td, "input.o")
        with open(asm_file, "w", encoding="utf-8") as f:
            f.write(source_code)

        result = subprocess.run(
            ["nasm", "-f", "elf64", asm_file, "-o", obj_file],
            capture_output=True,
            check=False,
        )
        assert result.returncode == 0, (
            "Local nasm compilation failed during test setup: "
            + result.stderr.decode(errors="replace")
        )
        with open(obj_file, "rb") as f:
            obj_bytes = f.read()

    return hashlib.sha256(obj_bytes + SEED_VALUE).hexdigest()


def post_source(source_code):
    try:
        return requests.post(
            GATEWAY_URL, json={"source": source_code}, timeout=5
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the gateway at {GATEWAY_URL}: {e}")


def assert_compilation_failed(source_code):
    response = post_source(source_code)
    assert response.status_code == 400, (
        f"Expected HTTP 400 for invalid assembly, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "error" in data, "Response JSON is missing the 'error' key."
    assert data["error"] == "compilation failed", (
        f"Expected error 'compilation failed', got '{data['error']}'."
    )


def assert_valid_hash(source_code):
    expected_hash = compile_and_hash(source_code)
    response = post_source(source_code)
    assert response.status_code == 200, (
        f"Expected HTTP 200 for valid assembly, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "hash" in data, "Response JSON is missing the 'hash' key."
    assert data["hash"] == expected_hash, (
        f"Hash mismatch. Expected {expected_hash}, but got {data['hash']}."
    )


def test_gateway_artifact_exists():
    path = "/home/user/gateway.py"
    assert os.path.isfile(path), f"Required gateway artifact does not exist: {path}"
    assert os.path.getsize(path) > 0, "gateway.py is empty"
    py_compile.compile(path, doraise=True)


def test_gateway_invalid_payload():
    # Preserve the original invalid-input assertion.
    assert_compilation_failed("invalid_instruction_test xyz")


def test_gateway_valid_payload():
    # Preserve the original valid-input and digest assertion.
    source_code = "global _start\n_start:\nmov rax, 60\nxor rdi, rdi\nsyscall\n"
    assert_valid_hash(source_code)


def test_gateway_unpredictable_sequential_payloads():
    # Generate inputs only after the agent has finished, so a fixed lookup table
    # cannot satisfy the verifier. Expected values are independently assembled.
    alphabet = string.ascii_lowercase
    for index in range(6):
        token = "".join(secrets.choice(alphabet) for _ in range(14))
        imm1 = secrets.randbelow(0x7ffffffe) + 1
        imm2 = secrets.randbelow(0x7ffffffe) + 1
        shift = secrets.randbelow(63) + 1
        source_code = (
            "bits 64\n"
            "section .text\n"
            f"global entry_{token}\n"
            f"entry_{token}:\n"
            f"    mov rax, {imm1}\n"
            f"    mov rbx, {imm2}\n"
            "    xor rax, rbx\n"
            f"    rol rax, {shift}\n"
            f"    add rax, {index + 3}\n"
            "    ret\n"
        )
        assert_valid_hash(source_code)

        bad_token = "".join(secrets.choice(alphabet) for _ in range(18))
        invalid_source = (
            "bits 64\nsection .text\n_start:\n"
            f"    impossible_opcode_{bad_token} rax, rbx\n"
        )
        assert_compilation_failed(invalid_source)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
