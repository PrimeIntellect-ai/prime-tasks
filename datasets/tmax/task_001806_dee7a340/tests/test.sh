#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from concurrent import futures

import grpc
import pytest

BACKEND = "/home/user/backend"
BINARY = "/home/user/backend/build/server"
CLIENT = "/home/user/client/client_v3.py"
LOG = "/home/user/benchmark.log"


def load_submitted_proto():
    out_dir = tempfile.mkdtemp(prefix="verifier_stubs_")
    proto = os.path.join(BACKEND, "data_service.proto")
    result = subprocess.run(
        [sys.executable, "-m", "grpc_tools.protoc", "-I" + BACKEND,
         "--python_out=" + out_dir, "--grpc_python_out=" + out_dir, proto],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, "Updated protobuf schema could not be compiled: " + result.stderr
    sys.path.insert(0, out_dir)
    import data_service_pb2 as pb2
    import data_service_pb2_grpc as pb2_grpc

    field = pb2.DataPoint.DESCRIPTOR.fields_by_name.get("weight")
    assert field is not None, "DataPoint must contain a weight field"
    assert field.number == 3, "DataPoint.weight must use field number 3"
    assert field.type == field.TYPE_DOUBLE, "DataPoint.weight must be a double"
    return pb2, pb2_grpc


PB2, PB2_GRPC = load_submitted_proto()


def run_client(timeout=60):
    env = os.environ.copy()
    env["PYTHONPATH"] = "/home/user/client:" + env.get("PYTHONPATH", "")
    return subprocess.run(
        ["python3", CLIENT], cwd="/home/user/client", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )


def test_server_binary_exists():
    assert os.path.exists(BINARY), f"Compiled server binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Server binary at {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled server must be an ELF executable"


def test_server_logic_and_memory_leak():
    assert os.path.exists(CLIENT), f"Client script not found at {CLIENT}"

    server_proc = subprocess.Popen(
        ["valgrind", "--leak-check=full", "--show-leak-kinds=all",
         "--error-exitcode=1", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    server_stdout = ""
    server_stderr = ""
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=12)
        stub = PB2_GRPC.DataServiceStub(channel)

        # Independently exercise multiplication with values other than the
        # benchmark's fixed 10.0 * 2.5 case.
        cases = [
            (101, 3.0, 4.0, 12.0),
            (202, -7.0, 2.5, -17.5),
            (303, 1.25, -8.0, -10.0),
            (404, 0.0, 123.5, 0.0),
        ]
        for request_id, value, weight, expected in cases:
            response = stub.ProcessData(
                PB2.DataPoint(id=request_id, value=value, weight=weight), timeout=5
            )
            assert response.id == request_id, "Server did not preserve the request id"
            assert response.processed_value == expected, (
                f"Incorrect multiplication for value={value}, weight={weight}"
            )

        # Preserve the original requirement that the submitted client run
        # successfully against the submitted server.
        client_proc = run_client()
        assert client_proc.returncode == 0, (
            "Client script failed to run. Stderr: "
            + client_proc.stderr.decode("utf-8", errors="replace")
        )
    finally:
        channel.close()
        if server_proc.poll() is None:
            server_proc.send_signal(signal.SIGINT)
        try:
            server_stdout, server_stderr = server_proc.communicate(timeout=8)
        except subprocess.TimeoutExpired:
            server_proc.kill()
            server_stdout, server_stderr = server_proc.communicate()

    assert "definitely lost: 0 bytes in 0 blocks" in server_stderr, (
        "Memory leak detected in the C++ server or valgrind did not run properly"
    )


class TrackingService(PB2_GRPC.DataServiceServicer):
    def __init__(self, bad_id=None):
        self.bad_id = bad_id
        self.calls = []
        self.active = 0
        self.max_active = 0
        self.lock = threading.Lock()

    def ProcessData(self, request, context):
        with self.lock:
            self.active += 1
            self.max_active = max(self.max_active, self.active)
            self.calls.append((request.id, request.value, request.weight))
        # Make overlapping asynchronous requests observable.
        time.sleep(0.001)
        result = 24.0 if request.id == self.bad_id else 25.0
        with self.lock:
            self.active -= 1
        return PB2.DataResult(id=request.id, processed_value=result)


def exercise_client_against_controlled_server(bad_id=None):
    service = TrackingService(bad_id=bad_id)
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=16))
    PB2_GRPC.add_DataServiceServicer_to_server(service, server)
    bound_port = server.add_insecure_port("localhost:50051")
    assert bound_port == 50051, "Could not bind verifier-controlled gRPC server to localhost:50051"
    server.start()
    if os.path.exists(LOG):
        os.unlink(LOG)
    started = time.monotonic()
    try:
        proc = run_client()
    finally:
        server.stop(0).wait()
    elapsed = time.monotonic() - started

    assert len(service.calls) == 1000, "Client must send exactly 1000 ProcessData requests"
    assert service.calls == [(i, 10.0, 2.5) for i in range(1, 1001)], (
        "Client requests must use ids 1..1000, value 10.0, and weight 2.5 in order"
    )
    assert service.max_active == 1, "The 1000 client requests must be sent sequentially"
    return proc, elapsed


def test_client_requests_and_response_validation():
    # A deliberately incorrect response proves the client actually checks all
    # response values rather than always reporting success.
    bad_proc, _ = exercise_client_against_controlled_server(bad_id=417)
    assert os.path.exists(LOG), "Client did not write benchmark.log"
    with open(LOG, "r") as f:
        bad_lines = f.read().strip().split("\n")
    assert bad_lines and bad_lines[0] == "All values correct: False", (
        "Client did not detect an incorrect processed_value"
    )

    # Finish with a fully correct run so the required final benchmark reports True.
    good_proc, elapsed = exercise_client_against_controlled_server()
    assert good_proc.returncode == 0, (
        "Client failed against a valid gRPC service. Stderr: "
        + good_proc.stderr.decode("utf-8", errors="replace")
    )

    with open(LOG, "r") as f:
        lines = f.read().strip().split("\n")
    assert len(lines) == 2, "benchmark.log must contain exactly two lines"
    assert lines[0] == "All values correct: True"
    match = re.fullmatch(r"Average latency: (\d+\.\d{2}) ms", lines[1])
    assert match is not None, "Average latency must be written with exactly two decimal places"
    latency = float(match.group(1))
    assert latency > 0.0, "Measured average latency must be positive"
    assert latency <= (elapsed * 1000.0 / 1000.0) + 5.0, "Reported latency is not plausible"


def test_benchmark_log_exists_and_format():
    log_path = "/home/user/benchmark.log"
    assert os.path.exists(log_path), f"Benchmark log not found at {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip().split('\n')

    assert len(content) >= 2, "Benchmark log should contain at least two lines"
    assert "All values correct: True" in content[0], "First line of benchmark.log must be 'All values correct: True'"
    latency_match = re.search(r"Average latency:\s+\d+\.\d+\s+ms", content[1])
    assert latency_match is not None, "Second line of benchmark.log must match 'Average latency: X.XX ms'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
