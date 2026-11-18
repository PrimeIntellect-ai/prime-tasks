#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import socket
import stat
import subprocess
import sys
from concurrent import futures

import pytest

APP_DIR = "/app/tiny_vm_grpc"
SRC_DIR = os.path.join(APP_DIR, "src")
BENCHMARK_RESULT_PATH = os.path.join(APP_DIR, "benchmark_result.txt")
TEST_FILE_PATH = os.path.join(APP_DIR, "tests", "test_vm.py")
BENCHMARK_PATH = os.path.join(APP_DIR, "benchmark.py")
PROTO_PATH = os.path.join(APP_DIR, "proto", "vm_service.proto")

EXPECTED_TEST = '''import sys
sys.path.append('./src')
from vm import TinyVM
from utils import compare_versions

def test_compare_versions():
    assert compare_versions("1.0", "1.1") < 0
    assert compare_versions("2.0", "2.0") == 0
    assert compare_versions("2.1", "2.0") > 0

def test_vm_execution():
    vm = TinyVM()
    res = vm.execute("SET R1 10\\nADD R1 5\\nHALT\\n")
    assert res == 15
'''

EXPECTED_BENCHMARK = '''import time
import grpc
import sys
import threading
sys.path.append('./src')
import vm_service_pb2
import vm_service_pb2_grpc
import server

def run_benchmark():
    code = "SET R1 0\\nSET R2 10000\\nADD R1 1\\nSUB R2 1\\nJNZ R2 2\\nHALT\\n"

    channel = grpc.insecure_channel('localhost:50051')
    stub = vm_service_pb2_grpc.VMServiceStub(channel)

    start = time.time()
    response = stub.Execute(vm_service_pb2.ProgramRequest(code=code))
    end = time.time()

    duration = end - start
    with open('benchmark_result.txt', 'w') as f:
        f.write(str(duration))
    print(f"Result: {response.result}, Time: {duration}")

if __name__ == '__main__':
    t = threading.Thread(target=server.serve, daemon=True)
    t.start()
    time.sleep(1) # wait for server
    run_benchmark()
'''

EXPECTED_PROTO = '''syntax = "proto3";
package vm;
service VMService {
  rpc Execute (ProgramRequest) returns (ProgramResponse) {}
}
message ProgramRequest {
  string code = 1;
}
message ProgramResponse {
  int32 result = 1;
}
'''


def assert_regular_file(path):
    assert os.path.exists(path), f"Required file not found: {path}"
    assert stat.S_ISREG(os.lstat(path).st_mode), f"Required path is not a regular file: {path}"


def test_protected_files_unmodified():
    expected = {
        TEST_FILE_PATH: EXPECTED_TEST,
        BENCHMARK_PATH: EXPECTED_BENCHMARK,
        PROTO_PATH: EXPECTED_PROTO,
    }
    for path, content in expected.items():
        assert_regular_file(path)
        with open(path, "r", encoding="utf-8") as f:
            assert f.read() == content, f"Protected file was modified: {path}"


def test_unit_tests_pass():
    assert os.path.exists(TEST_FILE_PATH), f"Test file not found at {TEST_FILE_PATH}"
    result = subprocess.run(
        ["pytest", TEST_FILE_PATH],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Unit tests failed. Pytest output:\n{result.stdout}\n{result.stderr}"


def test_generated_stubs_and_grpc_loop_semantics():
    for name in ("vm_service_pb2.py", "vm_service_pb2_grpc.py"):
        assert_regular_file(os.path.join(SRC_DIR, name))

    sys.path.insert(0, SRC_DIR)
    import grpc
    import vm_service_pb2
    import vm_service_pb2_grpc
    import server as server_module
    from utils import compare_versions

    assert vm_service_pb2.ProgramRequest.DESCRIPTOR.full_name == "vm.ProgramRequest"
    assert vm_service_pb2.ProgramResponse.DESCRIPTOR.full_name == "vm.ProgramResponse"
    service = vm_service_pb2.DESCRIPTOR.services_by_name.get("VMService")
    assert service is not None and "Execute" in service.methods_by_name

    assert compare_versions("1.2.9", "1.3.0") < 0
    assert compare_versions("10.0.1", "9.99.99") > 0
    assert compare_versions("3.4.5", "3.4.5") == 0

    grpc_server = grpc.server(futures.ThreadPoolExecutor(max_workers=2))
    vm_service_pb2_grpc.add_VMServiceServicer_to_server(
        server_module.VMServiceServicer(), grpc_server
    )
    port = grpc_server.add_insecure_port("127.0.0.1:0")
    assert port > 0, "Could not allocate a port for the submitted gRPC service"
    grpc_server.start()
    channel = grpc.insecure_channel(f"127.0.0.1:{port}")
    try:
        grpc.channel_ready_future(channel).result(timeout=5)
        stub = vm_service_pb2_grpc.VMServiceStub(channel)
        rng = random.SystemRandom()
        for _ in range(3):
            count = rng.randrange(2000, 9000)
            initial = rng.randrange(-1000, 1000)
            increment = rng.randrange(1, 8)
            code = (
                f"SET R1 {initial}\\n"
                f"SET R2 {count}\\n"
                f"ADD R1 {increment}\\n"
                "SUB R2 1\\n"
                "JNZ R2 2\\n"
                "HALT\\n"
            )
            response = stub.Execute(vm_service_pb2.ProgramRequest(code=code), timeout=5)
            assert response.result == initial + count * increment
    finally:
        channel.close()
        grpc_server.stop(0).wait()


def test_run_real_benchmark_and_result():
    # The immutable benchmark starts its own submitted gRPC server on this port.
    probe = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    try:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 0)
        probe.bind(("::", 50051))
    except OSError as exc:
        pytest.fail(f"Port 50051 was already occupied before the benchmark: {exc}")
    finally:
        probe.close()

    try:
        os.unlink(BENCHMARK_RESULT_PATH)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [sys.executable, BENCHMARK_PATH],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        timeout=20,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    assert result.returncode == 0, (
        f"Benchmark failed. Output:\n{result.stdout}\n{result.stderr}"
    )
    assert re.search(r"Result:\s*10000(?:,|\s)", result.stdout), (
        f"Benchmark did not return the expected VM result:\n{result.stdout}"
    )

    assert os.path.exists(BENCHMARK_RESULT_PATH), (
        f"Benchmark result file not found at {BENCHMARK_RESULT_PATH}"
    )
    with open(BENCHMARK_RESULT_PATH, "r") as f:
        content = f.read().strip()
    try:
        execution_time = float(content)
    except ValueError:
        pytest.fail(
            f"Benchmark result file does not contain a valid float. Content: {content}"
        )

    threshold = 0.5
    assert math.isfinite(execution_time) and execution_time >= 0, (
        f"Benchmark duration is not a valid elapsed time: {execution_time}"
    )
    assert execution_time < threshold, (
        f"Execution time {execution_time} is not < {threshold} seconds"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
