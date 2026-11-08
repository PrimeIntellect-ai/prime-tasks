#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import random
import re
import signal
import subprocess
import tempfile
import time
import urllib.request

HOME = "/home/user"
PAYLOAD = f"{HOME}/extracted_payload.bin"
CLI = f"{HOME}/decoder_cli"


def expected_capture_payload():
    data = bytearray()
    for chunk_id in range(128):
        data.extend(chunk_id.to_bytes(2, "big"))
        data.extend((32).to_bytes(2, "big"))
        data.extend(b"ABCD")
    return bytes(data)


def normalize_hex_list(values):
    assert isinstance(values, list), "Result must be a list"
    normalized = []
    for value in values:
        assert isinstance(value, str), "Every assembled request must be a string"
        assert value, "Assembled request must not be empty"
        assert re.fullmatch(r"[0-9a-fA-F]+", value), f"Invalid hexadecimal output: {value!r}"
        assert len(value) % 2 == 0, "Hexadecimal output must contain complete bytes"
        normalized.append(value.lower())
    return normalized


def run_decoder(data):
    with tempfile.NamedTemporaryFile() as f:
        f.write(data)
        f.flush()
        proc = subprocess.run([CLI, f.name], capture_output=True, text=True, timeout=10)
    assert proc.returncode == 0, f"decoder_cli failed: {proc.stderr}"
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    return normalize_hex_list(lines)


def make_stream(groups, seed, trailing=b""):
    records = []
    expected = []
    for base_id, payloads in groups:
        expected.append(b"".join(payloads).hex())
        total = len(payloads)
        for offset, payload in enumerate(payloads):
            assert len(payload) == 4
            records.append(
                (base_id + offset).to_bytes(2, "big")
                + total.to_bytes(2, "big")
                + payload
            )
    random.Random(seed).shuffle(records)
    return b"".join(records) + trailing, expected


def test_extracted_payload_contents():
    assert os.path.isfile(PAYLOAD), f"Missing {PAYLOAD}"
    with open(PAYLOAD, "rb") as f:
        actual = f.read()
    expected = expected_capture_payload()
    assert len(actual) == 1024, "Extracted payload should be exactly 1024 bytes"
    assert actual == expected, "Extracted bytes do not match the pixels encoded in the video"


def test_makefile_and_artifacts():
    assert os.path.isfile(f"{HOME}/Makefile"), "Makefile is missing"
    subprocess.run(["make", "-B"], cwd=HOME, check=True, timeout=60)
    assert os.path.isfile(CLI), "decoder_cli is missing"
    assert os.access(CLI, os.X_OK), "decoder_cli is not executable"
    assert os.path.isfile(f"{HOME}/libdecoder.so"), "libdecoder.so is missing"
    assert os.path.isfile(f"{HOME}/api.py"), "api.py is missing"
    ctypes.CDLL(f"{HOME}/libdecoder.so")


def test_decoder_behavior():
    capture_expected = [(b"ABCD" * 32).hex()] * 4
    assert run_decoder(expected_capture_payload()) == capture_expected

    rng = random.Random(93481)
    for case in range(30):
        count = rng.randint(1, 40)
        base = rng.randint(0, 65000 - count)
        payloads = [rng.randbytes(4) for _ in range(count)]
        stream, expected = make_stream([(base, payloads)], case)
        assert run_decoder(stream) == expected

    groups = [
        (10, [b"zero", b"one!", b"two!"]),
        (100, [b"ABCD", b"EFGH"]),
        (1000, [b"ijkl", b"mnop", b"qrst", b"uvwx"]),
    ]
    stream, expected = make_stream(groups, 771)
    assert run_decoder(stream) == expected

    # An incomplete final record cannot form a chunk and must not alter completed requests.
    stream, expected = make_stream([(400, [b"DATA", b"MORE", b"DONE"])], 19, b"\xaa\xbb\xcc")
    assert run_decoder(stream) == expected


def test_api_uses_ffi_and_decodes_payload_on_each_request():
    api_path = f"{HOME}/api.py"
    with open(api_path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source)
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    calls_cdll = any(
        isinstance(node, ast.Call)
        and ((isinstance(node.func, ast.Name) and node.func.id == "CDLL")
             or (isinstance(node.func, ast.Attribute) and node.func.attr == "CDLL"))
        for node in ast.walk(tree)
    )
    assert imports_ctypes and calls_cdll, "api.py must load the C shared library through ctypes"
    assert "/home/user/libdecoder.so" in source, "api.py must load /home/user/libdecoder.so"

    first_stream, first_expected = make_stream(
        [(25, [b"GET ", b"/one", b" HTT", b"P/1.", b"1\r\n\r"])], 3
    )
    second_stream, second_expected = make_stream(
        [(600, [b"POST", b" /x ", b"BODY"])], 4
    )

    with open(PAYLOAD, "rb") as f:
        original = f.read()

    proc = None
    try:
        with open(PAYLOAD, "wb") as f:
            f.write(first_stream)

        proc = subprocess.Popen(
            ["make", "start-api"], cwd=HOME,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        first_result = None
        for _ in range(30):
            try:
                with urllib.request.urlopen("http://localhost:8080/requests", timeout=1) as response:
                    assert response.status == 200
                    first_result = json.loads(response.read().decode())
                    break
            except Exception:
                time.sleep(0.5)
        assert first_result is not None, "API did not start or return 200 at /requests"
        assert normalize_hex_list(first_result) == first_expected

        with open(PAYLOAD, "wb") as f:
            f.write(second_stream)
        with urllib.request.urlopen("http://localhost:8080/requests", timeout=3) as response:
            assert response.status == 200
            second_result = json.loads(response.read().decode())
        assert normalize_hex_list(second_result) == second_expected, \
            "The endpoint must decode the current extracted_payload.bin on each request"
    finally:
        with open(PAYLOAD, "wb") as f:
            f.write(original)
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
