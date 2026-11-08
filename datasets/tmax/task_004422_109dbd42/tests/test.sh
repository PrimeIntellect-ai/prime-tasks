#!/bin/bash
mkdir -p /logs/verifier /tmp/grpc_generated

# Remove a server left running by the agent so verification exercises the submitted file.
pkill -f '^python(3)? .*/home/user/src/server.py' 2>/dev/null || true

# Generate the standard bindings needed by both the submitted server and provided client.
gen_ok=1
python3 -m grpc_tools.protoc \
  -I/home/user/src \
  --python_out=/home/user/src \
  --grpc_python_out=/home/user/src \
  /home/user/src/service.proto || gen_ok=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import ctypes
import os
import random
import re
import shutil
import string
import subprocess
import tempfile
import time

import grpc
import pytest

SRC = "/home/user/src"
SO_PATH = os.path.join(SRC, "libprocessor.so")
SERVER_PATH = os.path.join(SRC, "server.py")
CLIENT_PATH = os.path.join(SRC, "client.py")


def test_libprocessor_compiled():
    """Check if the shared library was compiled in the correct location."""
    so_path = "/home/user/src/libprocessor.so"
    assert os.path.isfile(so_path), f"The compiled shared library {so_path} is missing."
    ctypes.CDLL(so_path)


def test_server_py_updated():
    """Check if server.py was updated to load the correct library."""
    server_path = "/home/user/src/server.py"
    assert os.path.isfile(server_path), f"The file {server_path} is missing."
    with open(server_path, "r") as f:
        content = f.read()
    assert "/usr/lib/libprocessor.so" not in content, "server.py still contains the hardcoded broken library path."
    assert "libprocessor.so" in content, "server.py does not seem to load the new libprocessor.so."
    assert "extract_tokens" in content, "server.py does not call the C extract_tokens function."


def test_processor_c_fixed():
    """Check if processor.c was modified to include bounds checking."""
    c_path = "/home/user/src/processor.c"
    assert os.path.isfile(c_path), f"The file {c_path} is missing."
    with open(c_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    assert "MAX_TOKENS" in content or "5" in content, "processor.c does not seem to enforce MAX_TOKENS."


def test_c_library_safely_truncates_and_returns_tokens():
    """Load and execute the submitted library in a child process so a crash is a test failure."""
    helper = r'''
import ctypes, json
path = "/home/user/src/libprocessor.so"
lib = ctypes.CDLL(path)
lib.extract_tokens.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p)]
lib.extract_tokens.restype = ctypes.c_int
lib.free_tokens.argtypes = [ctypes.POINTER(ctypes.c_char_p), ctypes.c_int]
lib.free_tokens.restype = None

def extract(value):
    output = (ctypes.c_char_p * 5)()
    count = lib.extract_tokens(value.encode("ascii"), output)
    assert 0 <= count <= 5, count
    values = [ctypes.string_at(output[i]).decode("ascii") for i in range(count)]
    lib.free_tokens(output, count)
    return values

assert extract("one two three four five six seven eight nine") == ["one", "two", "three", "four", "five"]
assert extract("A1,,b2;C3---d4/e5+f6") == ["A1", "b2", "C3", "d4", "e5"]
print(json.dumps("ok"))
'''
    completed = subprocess.run(
        ["python3", "-c", helper], text=True, capture_output=True, timeout=10
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert '"ok"' in completed.stdout


@contextlib.contextmanager
def running_server():
    env = os.environ.copy()
    env["PYTHONPATH"] = SRC + os.pathsep + env.get("PYTHONPATH", "")
    proc = subprocess.Popen(
        ["python3", SERVER_PATH],
        cwd=SRC,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        try:
            grpc.channel_ready_future(channel).result(timeout=8)
        except Exception:
            output = ""
            if proc.poll() is not None and proc.stdout is not None:
                output = proc.stdout.read()
            raise AssertionError("Submitted gRPC server did not become ready.\n" + output)
        assert proc.poll() is None, "Submitted server exited before it could be tested."
        yield channel
    finally:
        channel.close()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        time.sleep(0.3)


def expected_tokens(value):
    return re.findall(r"[A-Za-z0-9]+", value)[:5]


def expected_diff(a, b):
    return sorted(set(expected_tokens(a)).symmetric_difference(expected_tokens(b)))


def test_live_grpc_endpoint_and_provided_client():
    """Start the submitted server and derive expected answers for fresh RPC inputs."""
    import sys
    sys.path.insert(0, SRC)
    import service_pb2
    import service_pb2_grpc

    nonce = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(12))
    cases = [
        (
            f"common{nonce} alpha{nonce}, beta{nonce}; left{nonce} tailA{nonce} ignoredA{nonce}",
            f"common{nonce} alpha{nonce}, beta{nonce}; right{nonce} tailB{nonce} ignoredB{nonce}",
        ),
        (f"x1{nonce}!!x2{nonce} / x3{nonce}", f"x2{nonce}--y1{nonce}"),
        ("", f"solo{nonce}"),
    ]

    with running_server() as channel:
        stub = service_pb2_grpc.DataProcessorStub(channel)
        for input_a, input_b in cases:
            response = stub.GetTokenDiff(
                service_pb2.DiffRequest(input_a=input_a, input_b=input_b), timeout=5
            )
            actual = list(response.tokens)
            expected = expected_diff(input_a, input_b)
            assert actual == expected, f"For {input_a!r} and {input_b!r}, expected {expected}, got {actual}"

        env = os.environ.copy()
        env["PYTHONPATH"] = SRC + os.pathsep + env.get("PYTHONPATH", "")
        completed = subprocess.run(
            ["python3", CLIENT_PATH], cwd=SRC, env=env,
            text=True, capture_output=True, timeout=10
        )
        assert completed.returncode == 0, completed.stdout + completed.stderr

    # Preserve the original decisive assertion, but only after actually running the client.
    result_path = "/home/user/diff_result.txt"
    assert os.path.isfile(result_path), f"The output file {result_path} is missing. Did the client run successfully?"
    with open(result_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected = ["delta", "omega"]
    assert lines == expected, f"Expected symmetric difference {expected}, but got {lines}."


def test_endpoint_really_uses_the_c_extractor():
    """Temporarily substitute an ABI-compatible probe to prove RPC parsing goes through ctypes."""
    import sys
    sys.path.insert(0, SRC)
    import service_pb2
    import service_pb2_grpc

    probe_source = r'''
#include <stdlib.h>
#include <string.h>
int extract_tokens(const char *input, char **out_tokens) {
    if (strstr(input, "LEFT_SENTINEL") != NULL)
        out_tokens[0] = strdup("library_left");
    else
        out_tokens[0] = strdup("library_right");
    return 1;
}
void free_tokens(char **tokens, int count) {
    for (int i = 0; i < count; ++i) free(tokens[i]);
}
'''
    with tempfile.TemporaryDirectory() as td:
        c_path = os.path.join(td, "probe.c")
        probe_path = os.path.join(td, "probe.so")
        backup_path = os.path.join(td, "submitted.so")
        with open(c_path, "w") as f:
            f.write(probe_source)
        built = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", probe_path, c_path],
            text=True, capture_output=True, timeout=10
        )
        assert built.returncode == 0, built.stdout + built.stderr

        shutil.copy2(SO_PATH, backup_path)
        try:
            shutil.copy2(probe_path, SO_PATH)
            with running_server() as channel:
                stub = service_pb2_grpc.DataProcessorStub(channel)
                response = stub.GetTokenDiff(
                    service_pb2.DiffRequest(
                        input_a="LEFT_SENTINEL", input_b="RIGHT_SENTINEL"
                    ), timeout=5
                )
                assert list(response.tokens) == ["library_left", "library_right"]
        finally:
            shutil.copy2(backup_path, SO_PATH)
TEST_EOF

if [ "$gen_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
