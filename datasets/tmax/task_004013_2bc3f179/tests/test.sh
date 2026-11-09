#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import math
import os
import re
import secrets
import socket
import subprocess
import sys
import time

import grpc
import pytest

ROOT = "/app/vendored/service-mesh"
SERVER_DIR = ROOT + "/server"
CLIENT_DIR = ROOT + "/client"
SERVER_PATH = SERVER_DIR + "/server"
THROUGHPUT_PATH = "/app/throughput.txt"


def wait_for_port(timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 50051), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail("The built Go server did not start listening on port 50051")


@pytest.fixture(scope="session", autouse=True)
def built_server():
    subprocess.run(["pkill", "-x", "server"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", SERVER_PATH], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)

    build = subprocess.run(
        ["go", "build", "-o", "server", "."], cwd=SERVER_DIR,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
    )
    assert build.returncode == 0, "go build -o server . failed:\n" + build.stdout

    proc = subprocess.Popen(
        [SERVER_PATH], cwd=SERVER_DIR,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    )
    try:
        wait_for_port()
        assert proc.poll() is None, "The Go server exited immediately"
        yield proc
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def encode_string(value):
    data = value.encode("utf-8")
    if not data:
        return b""
    n = len(data)
    length = bytearray()
    while True:
        byte = n & 0x7f
        n >>= 7
        length.append(byte | (0x80 if n else 0))
        if not n:
            break
    return b"\x0a" + bytes(length) + data


def process_ticks(proc):
    with open(f"/proc/{proc.pid}/stat", "r") as f:
        fields = f.read().split()
    return int(fields[13]) + int(fields[14])


def test_go_server_executable_exists():
    path = "/app/vendored/service-mesh/server/server"
    assert os.path.isfile(path), f"Go server executable not found at {path}. Did you build the Go code?"
    assert os.access(path, os.X_OK), f"Go server at {path} is not executable."


def test_protobuf_generated_files():
    pb2_path = "/app/vendored/service-mesh/client/service_pb2.py"
    pb2_grpc_path = "/app/vendored/service-mesh/client/service_pb2_grpc.py"
    assert os.path.isfile(pb2_path), f"Protobuf file {pb2_path} not found. Did you generate the protobufs?"
    assert os.path.isfile(pb2_grpc_path), f"Protobuf gRPC file {pb2_grpc_path} not found. Did you generate the protobufs?"


def test_property_based_test_exists():
    path = "/app/vendored/service-mesh/client/test_props.py"
    assert os.path.isfile(path), f"Property-based test file {path} not found."
    with open(path, "r") as f:
        content = f.read()
    assert "hypothesis" in content, "The property-based test does not appear to use the 'hypothesis' library."

    result = subprocess.run(
        [sys.executable, "-m", "pytest", path, "-q", "-rA"],
        cwd=CLIENT_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=180
    )
    assert result.returncode == 0, "The submitted property-based test failed:\n" + result.stdout
    assert re.search(r"\b[1-9][0-9]* passed\b", result.stdout), \
        "The property test did not execute any passing test (skipped tests are not sufficient):\n" + result.stdout


def test_server_echoes_verifier_generated_strings():
    values = [
        "",
        "plain ASCII",
        "nul\x00inside",
        "Unicode: λ雪🙂",
        "line one\nline two\tend",
        secrets.token_urlsafe(37),
        "秘密-" + secrets.token_hex(48),
    ]
    channel = grpc.insecure_channel("127.0.0.1:50051")
    grpc.channel_ready_future(channel).result(timeout=10)
    echo = channel.unary_unary(
        "/service.EchoService/Echo",
        request_serializer=lambda b: b,
        response_deserializer=lambda b: b,
    )
    try:
        for value in values:
            encoded = encode_string(value)
            response = echo(encoded, timeout=5)
            assert response == encoded, f"Echo changed verifier-generated payload {value!r}"
    finally:
        channel.close()


def test_benchmark_throughput_metric(built_server):
    benchmark_path = CLIENT_DIR + "/benchmark.py"
    assert os.path.isfile(benchmark_path), f"Benchmark file {benchmark_path} not found."
    source = open(benchmark_path, "r").read()
    try:
        tree = ast.parse(source, benchmark_path)
    except SyntaxError as exc:
        pytest.fail(f"benchmark.py is not valid Python: {exc}")

    has_asyncio = any(
        (isinstance(node, ast.Import) and any(alias.name == "asyncio" for alias in node.names)) or
        (isinstance(node, ast.ImportFrom) and node.module == "asyncio")
        for node in ast.walk(tree)
    )
    has_grpc_aio = "grpc.aio" in source or any(
        isinstance(node, ast.ImportFrom) and node.module == "grpc" and
        any(alias.name == "aio" for alias in node.names)
        for node in ast.walk(tree)
    )
    has_async_function = any(isinstance(node, ast.AsyncFunctionDef) for node in ast.walk(tree))
    concurrency_names = {"gather", "create_task", "as_completed", "wait", "TaskGroup"}
    has_concurrency = any(
        isinstance(node, ast.Call) and (
            (isinstance(node.func, ast.Name) and node.func.id in concurrency_names) or
            (isinstance(node.func, ast.Attribute) and node.func.attr in concurrency_names)
        ) for node in ast.walk(tree)
    )
    assert has_asyncio and has_grpc_aio and has_async_function and has_concurrency, \
        "benchmark.py must use asyncio, grpc.aio, and concurrent asynchronous requests"

    if os.path.exists(THROUGHPUT_PATH):
        os.remove(THROUGHPUT_PATH)
    before_ticks = process_ticks(built_server)
    result = subprocess.run(
        [sys.executable, benchmark_path], cwd=CLIENT_DIR,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240
    )
    after_ticks = process_ticks(built_server)
    assert result.returncode == 0, "benchmark.py failed:\n" + result.stdout
    assert after_ticks - before_ticks >= 5, \
        "benchmark.py did not generate meaningful RPC work on the running Go server"

    path = "/app/throughput.txt"
    assert os.path.isfile(path), f"Throughput output file {path} not found. Did you run the benchmark and save the output?"
    with open(path, "r") as f:
        content = f.read().strip()

    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", content), \
        f"{path} must contain a single ordinary float. Content was: {content}"
    try:
        rps = float(content)
    except ValueError:
        pytest.fail(f"Could not parse a float from {path}. Content was: {content}")
    assert math.isfinite(rps), f"RPS must be finite, but was {rps}"
    assert rps >= 2000.0, f"RPS {rps} is less than the required threshold of 2000.0. Keep optimizing!"


def test_independently_measured_server_throughput():
    async def measure():
        channels = [grpc.aio.insecure_channel("127.0.0.1:50051") for _ in range(8)]
        try:
            await asyncio.wait_for(asyncio.gather(*(c.channel_ready() for c in channels)), timeout=15)
            calls = [c.unary_unary(
                "/service.EchoService/Echo",
                request_serializer=lambda b: b,
                response_deserializer=lambda b: b,
            ) for c in channels]
            request = encode_string("verifier-benchmark-" + secrets.token_hex(8))
            count = 10000
            start = time.perf_counter()
            for base in range(0, count, 1000):
                responses = await asyncio.gather(*(
                    calls[i % len(calls)](request, timeout=15)
                    for i in range(base, min(base + 1000, count))
                ))
                assert all(response == request for response in responses)
            elapsed = time.perf_counter() - start
            return count / elapsed
        finally:
            await asyncio.gather(*(c.close() for c in channels))

    measured_rps = asyncio.run(measure())
    assert measured_rps > 2000.0, \
        f"Verifier independently measured only {measured_rps:.2f} RPS, below the required 2000 RPS"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
