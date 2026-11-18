#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import subprocess

import pytest

SO_PATH = "/home/user/rust_lib/target/debug/libproxy_abi.so"
EXPECTED = b"http://backend_service:9090"


def test_rust_project_files_exist():
    """Verify that the Rust project files and Cargo.toml exist."""
    cargo_toml_path = "/home/user/rust_lib/Cargo.toml"
    assert os.path.exists(cargo_toml_path), f"{cargo_toml_path} does not exist"

    with open(cargo_toml_path, "r") as f:
        content = f.read()

    assert re.search(r'crate-type\s*=\s*\[\s*["\']cdylib["\']\s*\]', content), "Cargo.toml must specify crate-type = ['cdylib']"
    assert re.search(r'name\s*=\s*["\']proxy_abi["\']', content), "Cargo.toml must specify name = 'proxy_abi'"


def test_shared_library_exists():
    """Verify that the compiled shared library exists."""
    assert os.path.exists(SO_PATH), f"Compiled library {SO_PATH} does not exist. Did you run `cargo build`?"


def test_python_script_exists():
    """Verify that the Python test script exists."""
    py_path = "/home/user/test_proxy.py"
    assert os.path.exists(py_path), f"Python script {py_path} does not exist."


def test_result_log_content_and_script_execution():
    """Keep the original result assertion, then ensure the script recreates it."""
    log_path = "/home/user/result.log"
    assert os.path.exists(log_path), f"Result log {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "http://backend_service:9090", f"Expected 'http://backend_service:9090', got '{content}'"

    os.unlink(log_path)
    completed = subprocess.run(
        ["python3", "/home/user/test_proxy.py"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr.decode("utf-8", "replace")
    assert os.path.isfile(log_path), "test_proxy.py did not recreate result.log"
    with open(log_path, "rb") as f:
        assert f.read() == EXPECTED, "result.log must contain exactly the extracted target with no newline"


def load_library():
    lib = ctypes.CDLL(SO_PATH)
    assert hasattr(lib, "extract_target"), "extract_target function is not exported by the library."
    lib.extract_target.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_char),
        ctypes.c_size_t,
    ]
    lib.extract_target.restype = ctypes.c_int32
    return lib


def payload(path, target, route_type=1):
    return (
        bytes([route_type])
        + len(path).to_bytes(2, "big")
        + path
        + len(target).to_bytes(2, "big")
        + target
    )


def invoke(lib, data, out_len=1024):
    # Allocate substantial guarded storage even for tiny advertised buffers so a
    # bad implementation is detected by canaries rather than corrupting Python.
    input_storage = (ctypes.c_uint8 * max(1, len(data)))()
    if data:
        ctypes.memmove(input_storage, data, len(data))

    capacity = max(1024, out_len + 64)
    output_storage = (ctypes.c_ubyte * capacity)(*([0xA5] * capacity))
    output_ptr = ctypes.cast(output_storage, ctypes.POINTER(ctypes.c_char))
    result = lib.extract_target(input_storage, len(data), output_ptr, out_len)
    return result, bytes(output_storage)


def assert_valid(lib, target):
    data = payload(b"/api/v3", target)
    result, output = invoke(lib, data, len(target) + 1)
    assert result == len(target)
    assert output[:len(target)] == target
    assert output[len(target)] == 0, "target must be null-terminated"
    assert output[len(target) + 1:] == bytes([0xA5]) * (len(output) - len(target) - 1), "wrote past out_len"


def assert_invalid(lib, data):
    result, _ = invoke(lib, data)
    assert result == -1


def test_rust_library_functionality():
    """Retain the original fixed cases and exercise actual format parsing."""
    lib = load_library()

    valid_payload = b'\x01\x00\x07/api/v3\x00\x1bhttp://backend_service:9090'
    out_buf = ctypes.create_string_buffer(100)
    original_input = ctypes.cast(ctypes.c_char_p(valid_payload), ctypes.POINTER(ctypes.c_uint8))
    res = lib.extract_target(original_input, len(valid_payload), out_buf, 100)
    assert res == 27, f"Expected return value 27, got {res}"
    assert out_buf.value == EXPECTED, f"Expected output buffer to contain target, got {out_buf.value}"

    invalid_route = b'\x02\x00\x07/api/v3\x00\x1bhttp://backend_service:9090'
    out_buf2 = ctypes.create_string_buffer(100)
    res2 = lib.extract_target(ctypes.cast(ctypes.c_char_p(invalid_route), ctypes.POINTER(ctypes.c_uint8)), len(invalid_route), out_buf2, 100)
    assert res2 == -1, f"Expected -1 for invalid route type, got {res2}"

    invalid_path = b'\x01\x00\x07/api/v4\x00\x1bhttp://backend_service:9090'
    out_buf3 = ctypes.create_string_buffer(100)
    res3 = lib.extract_target(ctypes.cast(ctypes.c_char_p(invalid_path), ctypes.POINTER(ctypes.c_uint8)), len(invalid_path), out_buf3, 100)
    assert res3 == -1, f"Expected -1 for invalid path, got {res3}"

    # Dynamically generated and varied targets prevent fixed-target solutions.
    nonce = secrets.token_hex(16).encode("ascii")
    targets = [
        b"http://service-" + nonce + b":8081/random/path",
        b"https://example.invalid/" + secrets.token_bytes(24).hex().encode("ascii"),
        ("http://backend.invalid/" + "x" * 280).encode("utf-8"),
        "https://example.invalid/naive-\u2603".encode("utf-8"),
    ]
    for target in targets:
        assert_valid(lib, target)

    # Every proper prefix of a dynamically generated message is truncated and invalid.
    complete = payload(b"/api/v3", targets[0])
    for cut in range(len(complete)):
        assert_invalid(lib, complete[:cut])

    # Length fields must be parsed as big-endian and must fit within the input.
    assert_invalid(lib, b"\x01\x00\x08/api/v3" + len(targets[0]).to_bytes(2, "big") + targets[0])
    assert_invalid(lib, b"\x01\x00\x07/api/v3\x01\x00short")
    assert_invalid(lib, b"\x01\xff\xff/api/v3")
    assert_invalid(lib, payload(b"/api/v30", targets[0]))
    assert_invalid(lib, payload(b"/API/v3", targets[0]))
    assert_invalid(lib, payload(b"/api/v3", targets[0], route_type=0))
    assert_invalid(lib, payload(b"/api/v3", targets[0], route_type=255))

    # Target bytes are required to be valid UTF-8.
    assert_invalid(lib, payload(b"/api/v3", b"http://bad/\xff\xfe"))

    # A buffer must hold all target bytes plus the terminating NUL. No byte at
    # or beyond the advertised out_len may be modified on undersized calls.
    overflow_target = b"http://" + secrets.token_hex(20).encode("ascii")
    overflow_payload = payload(b"/api/v3", overflow_target)
    for small_len in (0, 1, len(overflow_target)):
        result, storage = invoke(lib, overflow_payload, small_len)
        assert result == -1, "undersized output buffer must be rejected"
        assert storage[small_len:] == bytes([0xA5]) * (len(storage) - small_len), "write exceeded out_len"

    # Zero-length input and null pointers are invalid and must not be dereferenced.
    assert_invalid(lib, b"")
    null_result = lib.extract_target(None, 1, None, 0)
    assert null_result == -1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
