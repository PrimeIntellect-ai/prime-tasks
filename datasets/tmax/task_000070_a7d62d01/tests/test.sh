#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import subprocess
import sys
import tempfile
import textwrap

import pytest
import requests

WORKSPACE = "/app/pr_workspace"
URL = "http://127.0.0.1:8080/mask"


def call_api(raw_bytes, key):
    payload_b64 = base64.b64encode(raw_bytes).decode("utf-8")
    req_json = {"payload": payload_b64, "key": key}

    try:
        resp = requests.post(URL, json=req_json, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {URL} or request timed out: {e}")

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}. Response: {resp.text}"

    try:
        resp_json = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {resp.text}")

    assert "masked_base64" in resp_json, f"Response JSON missing 'masked_base64' key. Response: {resp_json}"

    masked_b64 = resp_json["masked_base64"]
    try:
        masked_bytes = base64.b64decode(masked_b64)
    except Exception as e:
        pytest.fail(f"Failed to decode base64 response: {masked_b64}. Error: {e}")

    assert len(masked_bytes) == len(raw_bytes), "Masked payload length does not match original payload length"
    expected_bytes = bytes(b ^ key for b in raw_bytes)
    assert masked_bytes == expected_bytes, f"Masked payload incorrect for key {key}."


def test_server_running_and_correct():
    test_cases = [
        (b"Hello", 42),
        (b"Testing 123", 255),
        (b"\x00\x01\x02", 0),
        (b"", 12),
        (b"A" * 1000, 128),
    ]
    for raw_bytes, key in test_cases:
        call_api(raw_bytes, key)


def test_server_randomized_cases():
    rng = random.Random(0xFA57)
    for _ in range(25):
        raw = bytes(rng.getrandbits(8) for _ in range(rng.randrange(0, 4097)))
        call_api(raw, rng.randrange(0, 256))


def test_files_unmodified():
    test_file = "/app/pr_workspace/test_wrapper.py"
    assert os.path.exists(test_file), f"{test_file} is missing"
    with open(test_file, "r") as f:
        content = f.read()
        assert "from hypothesis import given" in content, "test_wrapper.py appears to have been modified (missing hypothesis import)"
        assert "def test_mask_roundtrip(data, key):" in content, "test_wrapper.py appears to have been modified (missing test_mask_roundtrip)"

    expected = (
        "from hypothesis import given, strategies as st\n"
        "from wrapper import apply_mask\n"
        "\n"
        "@given(st.binary(), st.integers(min_value=0, max_value=255))\n"
        "def test_mask_roundtrip(data, key):\n"
        "    masked = apply_mask(data, key)\n"
        "    assert len(masked) == len(data)\n"
        "    unmasked = apply_mask(masked, key)\n"
        "    assert unmasked == data\n"
    )
    assert content == expected, "test_wrapper.py was modified"


def test_shared_library_is_original_elf():
    library = os.path.join(WORKSPACE, "libfastxor.so")
    assert os.path.isfile(library), "libfastxor.so is missing or is not a regular file"
    with open(library, "rb") as f:
        submitted = f.read()
    assert submitted.startswith(b"\x7fELF"), "libfastxor.so is not an ELF shared library"

    source = (
        "#include <stddef.h>\n"
        "\n"
        "int mask_payload(unsigned char* buffer, int length, unsigned char key) {\n"
        "    if (buffer == NULL) return -1;\n"
        "    for (int i = 0; i < length; i++) {\n"
        "        buffer[i] ^= key;\n"
        "    }\n"
        "    return 0;\n"
        "}\n"
    )
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "fastxor.c")
        reference = os.path.join(td, "libfastxor.so")
        with open(src, "w") as f:
            f.write(source)
        subprocess.run(
            ["gcc", "-fPIC", "-shared", "-O3", "fastxor.c", "-o", "libfastxor.so"],
            cwd=td,
            check=True,
        )
        subprocess.run(["strip", "--strip-all", reference], check=True)
        with open(reference, "rb") as f:
            expected = f.read()
    assert submitted == expected, "libfastxor.so was modified"

    symbols = subprocess.run(
        ["nm", "-D", library], capture_output=True, text=True, check=True
    ).stdout
    assert "mask_payload" in symbols, "libfastxor.so does not export mask_payload"


def test_required_property_suite_passes():
    result = subprocess.run(
        [sys.executable, "-m", "pytest", os.path.join(WORKSPACE, "test_wrapper.py"), "-q", "--tb=short"],
        cwd=WORKSPACE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert result.returncode == 0, "Required property tests failed:\n" + result.stdout


def test_wrapper_produces_xor_for_derived_inputs():
    script = r'''
import os
import random
import sys
sys.path.insert(0, "/app/pr_workspace")
from wrapper import apply_mask
rng = random.Random(918273)
for _ in range(40):
    data = bytes(rng.getrandbits(8) for _ in range(rng.randrange(0, 2049)))
    key = rng.randrange(256)
    got = apply_mask(data, key)
    expected = bytes(value ^ key for value in data)
    assert type(got) is bytes
    assert got == expected, (len(data), key)
'''
    result = subprocess.run(
        [sys.executable, "-c", script],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, "wrapper.apply_mask failed derived XOR checks:\n" + result.stdout


def test_wrapper_actually_invokes_mask_payload():
    library = os.path.join(WORKSPACE, "libfastxor.so")
    backup = library + ".verifier-backup"
    probe_source = r'''
#include <stddef.h>
int mask_payload(unsigned char* buffer, int length, unsigned char key) {
    if (buffer == NULL) return -1;
    for (int i = 0; i < length; i++) buffer[i] = (unsigned char)(buffer[i] + key + i);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "probe.c")
        probe = os.path.join(td, "libfastxor.so")
        with open(src, "w") as f:
            f.write(probe_source)
        subprocess.run(["gcc", "-fPIC", "-shared", "-O2", src, "-o", probe], check=True)

        assert not os.path.exists(backup), "Unexpected verifier backup file exists"
        os.replace(library, backup)
        try:
            with open(probe, "rb") as source, open(library, "wb") as target:
                target.write(source.read())
            script = r'''
import sys
sys.path.insert(0, "/app/pr_workspace")
from wrapper import apply_mask
data = b"\x00abc\xff\x10"
key = 37
expected = bytes((value + key + index) & 255 for index, value in enumerate(data))
got = apply_mask(data, key)
assert got == expected, (got, expected)
'''
            result = subprocess.run(
                [sys.executable, "-c", script],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=15,
            )
            assert result.returncode == 0, (
                "wrapper.py did not bind and invoke libfastxor.so's mask_payload with the correct ABI:\n"
                + result.stdout
            )
        finally:
            if os.path.exists(backup):
                os.replace(backup, library)


def test_server_endpoint_uses_wrapper_apply_mask():
    script = r'''
import base64
import sys
import types

calls = []
sentinel = b"\xde\xad\xbe\xef"
fake = types.ModuleType("wrapper")
def apply_mask(data, key):
    calls.append((data, key))
    return sentinel
fake.apply_mask = apply_mask
sys.modules["wrapper"] = fake
sys.path.insert(0, "/app/pr_workspace")

import server
from fastapi.testclient import TestClient

raw = b"wrapper-check"
with TestClient(server.app) as client:
    response = client.post("/mask", json={
        "payload": base64.b64encode(raw).decode("ascii"),
        "key": 173,
    })
assert response.status_code == 200, response.text
body = response.json()
assert base64.b64decode(body["masked_base64"]) == sentinel, body
assert calls == [(raw, 173)], calls
'''
    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=WORKSPACE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, "server.py bypasses wrapper.apply_mask:\n" + result.stdout


def test_server_log_exists():
    log_file = "/app/pr_workspace/server.log"
    assert os.path.exists(log_file), f"Log file {log_file} is missing. The server output should be redirected here."
    assert os.path.isfile(log_file), f"{log_file} is not a regular file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
