#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib
import math
import os
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import grpc
import pytest

PROJECT = "/home/user/project"
LIB = PROJECT + "/lib/libcalc.so"
GEN = PROJECT + "/grpc_gen"
SRC = PROJECT + "/src"


def test_project_structure():
    dirs = [
        "/home/user/project",
        "/home/user/project/lib",
        "/home/user/project/grpc_gen",
        "/home/user/project/src",
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} does not exist."


def test_shared_library_exists():
    so_path = "/home/user/project/lib/libcalc.so"
    assert os.path.isfile(so_path), f"Shared library {so_path} does not exist."


def test_grpc_generated_files():
    pb2_path = "/home/user/project/grpc_gen/service_pb2.py"
    pb2_grpc_path = "/home/user/project/grpc_gen/service_pb2_grpc.py"
    assert os.path.isfile(pb2_path), f"Generated file {pb2_path} does not exist."
    assert os.path.isfile(pb2_grpc_path), f"Generated file {pb2_grpc_path} does not exist."


def test_source_files_exist():
    server_path = "/home/user/project/src/server.py"
    client_path = "/home/user/project/src/client.py"
    run_path = "/home/user/project/run.sh"
    assert os.path.isfile(server_path), f"Source file {server_path} does not exist."
    assert os.path.isfile(client_path), f"Source file {client_path} does not exist."
    assert os.path.isfile(run_path), f"Script {run_path} does not exist."


def test_output_file_content():
    output_path = "/home/user/project/output.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."
    with open(output_path, "r") as f:
        content = f.read().strip()
    assert content == "46.5", f"Expected output.txt to contain '46.5', but got '{content}'."


def expression_cases():
    cases = []
    for op in "+-*/":
        a = secrets.randbelow(8000) / 4.0 + 1.25
        b = secrets.randbelow(5000) / 4.0 + 1.25
        text = f"{a}{op}{b}"
        if op == "+":
            expected = a + b
        elif op == "-":
            expected = a - b
        elif op == "*":
            expected = a * b
        else:
            expected = a / b
        cases.append((text.encode().hex(), expected))
    return cases


def load_generated_modules():
    if GEN not in sys.path:
        sys.path.insert(0, GEN)
    importlib.invalidate_caches()
    pb2 = importlib.import_module("service_pb2")
    pb2_grpc = importlib.import_module("service_pb2_grpc")
    return pb2, pb2_grpc


def wait_for_channel(proc, timeout=8):
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=timeout)
    except Exception:
        stderr = ""
        if proc.poll() is not None and proc.stderr is not None:
            stderr = proc.stderr.read()
        channel.close()
        raise AssertionError(f"Submitted server did not become ready: {stderr}")
    assert proc.poll() is None, "Submitted server exited before it could be exercised"
    return channel


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
    if proc.stdout:
        proc.stdout.close()
    if proc.stderr:
        proc.stderr.close()


def start_server():
    proc = subprocess.Popen(
        [sys.executable, os.path.join(SRC, "server.py")],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return proc, wait_for_channel(proc)


def assert_server_gone():
    deadline = time.time() + 4
    while time.time() < deadline:
        channel = grpc.insecure_channel("localhost:50051")
        try:
            grpc.channel_ready_future(channel).result(timeout=0.25)
        except Exception:
            channel.close()
            return
        channel.close()
        time.sleep(0.15)
    raise AssertionError("run.sh did not kill the background server")


def run_shell_script():
    proc = subprocess.Popen(
        ["/bin/bash", os.path.join(PROJECT, "run.sh")],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        raise AssertionError(f"run.sh timed out; stdout={stdout!r}, stderr={stderr!r}")
    assert proc.returncode == 0, f"run.sh failed; stdout={stdout!r}, stderr={stderr!r}"
    assert_server_gone()


def sentinel_value(hex_payload):
    h = 17
    for byte in hex_payload.encode("ascii"):
        h = (h * 131 + byte) % 100000
    return 1000.0 + h / 10.0


def build_sentinel_library(destination):
    source = r'''#include <stddef.h>
int evaluate_hex_expression(const char *s, double *result) {
    unsigned long h = 17;
    const unsigned char *p = (const unsigned char *)s;
    if (!s || !result) return -1;
    while (*p) { h = (h * 131 + *p) % 100000; ++p; }
    *result = 1000.0 + ((double)h) / 10.0;
    return 0;
}
'''
    c_path = destination + ".c"
    with open(c_path, "w") as f:
        f.write(source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", c_path, "-o", destination],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_real_artifacts_and_execution():
    # Load and exercise the submitted ELF shared library directly on runtime-derived cases.
    try:
        calc = ctypes.CDLL(LIB)
        evaluate = calc.evaluate_hex_expression
    except Exception as exc:
        pytest.fail(f"libcalc.so is not a loadable library with the required symbol: {exc}")
    evaluate.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_double)]
    evaluate.restype = ctypes.c_int
    cases = expression_cases()
    for payload, expected in cases:
        result = ctypes.c_double()
        rc = evaluate(payload.encode("ascii"), ctypes.byref(result))
        assert rc == 0
        assert math.isclose(result.value, expected, rel_tol=1e-10, abs_tol=1e-10)

    # Import the generated protobuf code and verify the required schema and service exist.
    pb2, pb2_grpc = load_generated_modules()
    request_field = pb2.ComputeRequest.DESCRIPTOR.fields_by_name["hex_payload"]
    response_field = pb2.ComputeResponse.DESCRIPTOR.fields_by_name["result"]
    assert request_field.number == 1
    assert response_field.number == 1
    assert hasattr(pb2_grpc, "MathServiceStub")
    assert hasattr(pb2_grpc, "add_MathServiceServicer_to_server")

    # The implementation must explicitly configure the ctypes ABI as instructed.
    with open(os.path.join(SRC, "server.py"), "r") as f:
        server_source = f.read()
    tree = ast.parse(server_source)
    assigned_attrs = set()
    has_cdll_call = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            name = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", None)
            if name in ("CDLL", "PyDLL"):
                has_cdll_call = True
        targets = []
        if isinstance(node, ast.Assign):
            targets = node.targets
        elif isinstance(node, ast.AnnAssign):
            targets = [node.target]
        for target in targets:
            if isinstance(target, ast.Attribute):
                assigned_attrs.add(target.attr)
    assert has_cdll_call, "server.py does not load the C shared library with ctypes"
    assert "argtypes" in assigned_attrs, "server.py does not set evaluate_hex_expression.argtypes"
    assert "restype" in assigned_attrs, "server.py does not set evaluate_hex_expression.restype"

    # Exercise the submitted server with several non-fixed requests.
    proc, channel = start_server()
    try:
        stub = pb2_grpc.MathServiceStub(channel)
        for payload, expected in cases:
            response = stub.Compute(pb2.ComputeRequest(hex_payload=payload), timeout=4)
            assert math.isclose(response.result, expected, rel_tol=1e-10, abs_tol=1e-10)

        client = subprocess.run(
            [sys.executable, os.path.join(SRC, "client.py")],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=8,
        )
        assert client.returncode == 0, client.stderr
        assert client.stdout == "46.5\n", f"Client must print only '46.5', got {client.stdout!r}"
    finally:
        channel.close()
        stop_process(proc)
    assert_server_gone()

    # Execute run.sh itself rather than trusting the pre-existing output file.
    output = os.path.join(PROJECT, "output.txt")
    if os.path.exists(output):
        os.unlink(output)
    run_shell_script()
    with open(output, "r") as f:
        assert f.read().strip() == "46.5"

    # Replace the library temporarily with a runtime-built implementation having
    # deliberately different behavior. This proves server.py, client.py, and run.sh
    # really travel through the submitted shared library and gRPC service.
    backup = tempfile.mktemp(prefix="original_libcalc_", suffix=".so")
    sentinel = tempfile.mktemp(prefix="sentinel_libcalc_", suffix=".so")
    shutil.copy2(LIB, backup)
    build_sentinel_library(sentinel)
    try:
        os.replace(sentinel, LIB)
        proc, channel = start_server()
        try:
            stub = pb2_grpc.MathServiceStub(channel)
            dynamic_payload = secrets.token_bytes(18).hex()
            response = stub.Compute(pb2.ComputeRequest(hex_payload=dynamic_payload), timeout=4)
            assert math.isclose(response.result, sentinel_value(dynamic_payload), abs_tol=1e-9)

            client = subprocess.run(
                [sys.executable, os.path.join(SRC, "client.py")],
                cwd=PROJECT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=8,
            )
            expected_client = f"{sentinel_value('31352e352a332e30'):.1f}\n"
            assert client.returncode == 0, client.stderr
            assert client.stdout == expected_client
        finally:
            channel.close()
            stop_process(proc)
        assert_server_gone()

        if os.path.exists(output):
            os.unlink(output)
        run_shell_script()
        with open(output, "r") as f:
            assert f.read().strip() == f"{sentinel_value('31352e352a332e30'):.1f}"
    finally:
        if os.path.exists(backup):
            os.replace(backup, LIB)
        if os.path.exists(sentinel):
            os.unlink(sentinel)
        if os.path.exists(sentinel + ".c"):
            os.unlink(sentinel + ".c")

    # Restore the required final output using the restored submitted library.
    if os.path.exists(output):
        os.unlink(output)
    run_shell_script()
    with open(output, "r") as f:
        assert f.read().strip() == "46.5"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
