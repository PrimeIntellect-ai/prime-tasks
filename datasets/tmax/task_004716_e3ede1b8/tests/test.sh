#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib
import json
import math
import os
import runpy
import signal
import socket
import subprocess
import sys
import threading
import time
from concurrent import futures
from unittest import mock

import grpc
import pytest

PROJECT = "/home/user/math_service"


def expected_series(n, x):
    return math.fsum((x ** i) / i for i in range(1, n + 1))


def assert_port_free():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.2)
        assert sock.connect_ex(("127.0.0.1", 50051)) != 0, (
            "port 50051 is already occupied; the task required the benchmark server "
            "to be cleanly terminated"
        )


def stop_process(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)


def test_complete_implementation():
    setup_path = os.path.join(PROJECT, "setup.py")
    captured = {}

    def capture_setup(*args, **kwargs):
        captured.update(kwargs)

    with mock.patch("setuptools.setup", capture_setup):
        runpy.run_path(setup_path, run_name="__verifier_setup__")

    extensions = captured.get("ext_modules", [])
    algo_extensions = [ext for ext in extensions if getattr(ext, "name", None) == "algo_ext"]
    assert algo_extensions, "setup.py must define the algo_ext extension"
    assert "m" in (algo_extensions[0].libraries or []), (
        "algo_ext must explicitly link the standard math library ('m')"
    )

    # Rebuild from the submitted build configuration rather than trusting a file
    # that merely has the expected shared-object name.
    for path in glob.glob(os.path.join(PROJECT, "algo_ext*.so")):
        os.remove(path)
    build = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, "extension build failed:\n" + build.stdout

    # Original extension assertion.
    so_files = glob.glob("/home/user/math_service/algo_ext*.so")
    assert len(so_files) > 0, (
        "algo_ext shared object file (.so) is missing in /home/user/math_service/. "
        "Did you compile the extension?"
    )

    sys.path.insert(0, PROJECT)
    importlib.invalidate_caches()
    sys.modules.pop("algo_ext", None)
    algo_ext = importlib.import_module("algo_ext")
    assert callable(getattr(algo_ext, "compute", None)), "algo_ext.compute is missing"
    for n, x in [(1, 0.25), (7, -0.3), (100, 0.5)]:
        actual = algo_ext.compute(n, x)
        expected = expected_series(n, x)
        assert isinstance(actual, float)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12)

    # Original generated-file assertions.
    pb2_path = "/home/user/math_service/service_pb2.py"
    pb2_grpc_path = "/home/user/math_service/service_pb2_grpc.py"
    assert os.path.isfile(pb2_path), f"{pb2_path} is missing. Did you generate the gRPC python files?"
    assert os.path.isfile(pb2_grpc_path), f"{pb2_grpc_path} is missing. Did you generate the gRPC python files?"

    service_pb2 = importlib.import_module("service_pb2")
    service_pb2_grpc = importlib.import_module("service_pb2_grpc")

    descriptor = service_pb2.DESCRIPTOR
    assert descriptor.package == "mathapp"
    assert "SeriesRequest" in descriptor.message_types_by_name
    assert "SeriesResponse" in descriptor.message_types_by_name
    request_desc = descriptor.message_types_by_name["SeriesRequest"]
    response_desc = descriptor.message_types_by_name["SeriesResponse"]
    assert [(f.name, f.number, f.type) for f in request_desc.fields] == [
        ("n", 1, request_desc.fields_by_name["n"].TYPE_INT32),
        ("x", 2, request_desc.fields_by_name["x"].TYPE_DOUBLE),
    ]
    assert [(f.name, f.number, f.type) for f in response_desc.fields] == [
        ("result", 1, response_desc.fields_by_name["result"].TYPE_DOUBLE),
    ]
    assert "MathService" in descriptor.services_by_name
    service_desc = descriptor.services_by_name["MathService"]
    assert len(service_desc.methods) == 1
    method = service_desc.methods[0]
    assert method.name == "ComputeSeries"
    assert method.input_type.full_name == "mathapp.SeriesRequest"
    assert method.output_type.full_name == "mathapp.SeriesResponse"
    assert not method.client_streaming and not method.server_streaming

    assert os.path.isfile(os.path.join(PROJECT, "server.py")), "server.py is missing"
    assert os.path.isfile(os.path.join(PROJECT, "benchmark.py")), "benchmark.py is missing"
    assert_port_free()

    # Run the submitted server with a verifier-provided algo_ext module. Correct
    # RPC results then demonstrate that server.py imports and calls algo_ext.compute.
    wrapper = r'''
import runpy, sys, types
m = types.ModuleType("algo_ext")
def compute(n, x):
    return 12345.0 + n * 0.25 + x * 2.0
m.compute = compute
sys.modules["algo_ext"] = m
runpy.run_path("/home/user/math_service/server.py", run_name="__main__")
'''
    server_proc = subprocess.Popen(
        [sys.executable, "-c", wrapper],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        try:
            grpc.channel_ready_future(channel).result(timeout=10)
        except grpc.FutureTimeoutError:
            output = ""
            if server_proc.poll() is not None:
                output = server_proc.stdout.read()
            pytest.fail("submitted server did not listen on port 50051:\n" + output)

        stub = service_pb2_grpc.MathServiceStub(channel)
        for n, x in [(4, 0.75), (19, -0.2), (100, 0.5)]:
            response = stub.ComputeSeries(
                service_pb2.SeriesRequest(n=n, x=x), timeout=5
            )
            expected = 12345.0 + n * 0.25 + x * 2.0
            assert math.isclose(response.result, expected, rel_tol=0, abs_tol=1e-12), (
                "server.py did not return the value produced by algo_ext.compute"
            )
    finally:
        channel.close()
        stop_process(server_proc)

    time.sleep(0.2)
    assert_port_free()

    # Exercise benchmark.py against a controlled server so request count and
    # request parameters are observed rather than taken from its JSON report.
    state = {"count": 0, "active": 0, "max_active": 0, "bad_request": False}
    lock = threading.Lock()
    expected_final = expected_series(100, 0.5)

    class CountingServicer(service_pb2_grpc.MathServiceServicer):
        def ComputeSeries(self, request, context):
            with lock:
                state["count"] += 1
                state["active"] += 1
                state["max_active"] = max(state["max_active"], state["active"])
                if request.n != 100 or request.x != 0.5:
                    state["bad_request"] = True
            try:
                time.sleep(0.0005)
                return service_pb2.SeriesResponse(result=expected_final)
            finally:
                with lock:
                    state["active"] -= 1

    grpc_server = grpc.server(futures.ThreadPoolExecutor(max_workers=16))
    service_pb2_grpc.add_MathServiceServicer_to_server(CountingServicer(), grpc_server)
    bound_port = grpc_server.add_insecure_port("localhost:50051")
    assert bound_port == 50051, "could not bind benchmark verifier server to port 50051"
    grpc_server.start()

    json_path = "/home/user/math_service/benchmark_results.json"
    if os.path.exists(json_path):
        os.remove(json_path)
    try:
        benchmark = subprocess.run(
            [sys.executable, os.path.join(PROJECT, "benchmark.py")],
            cwd=PROJECT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
    finally:
        grpc_server.stop(0).wait(timeout=5)

    assert benchmark.returncode == 0, "benchmark.py failed:\n" + benchmark.stdout
    assert state["count"] == 1000, f"benchmark made {state['count']} requests instead of 1000"
    assert not state["bad_request"], "benchmark requests must use n=100 and x=0.5"
    assert state["max_active"] == 1, "benchmark requests were not sequential"

    # Original benchmark-result assertions, now applied to a freshly generated file.
    assert os.path.isfile(json_path), f"{json_path} is missing. Did you run the benchmark client?"
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} contains invalid JSON.")

    assert "final_result" in data, "'final_result' key missing in benchmark_results.json"
    assert "total_time_seconds" in data, "'total_time_seconds' key missing in benchmark_results.json"
    assert set(data) == {"final_result", "total_time_seconds"}, (
        "benchmark_results.json must contain exactly the required keys"
    )

    final_result = data["final_result"]
    total_time = data["total_time_seconds"]
    assert isinstance(final_result, (int, float)), f"final_result must be a number, got {type(final_result).__name__}"
    assert isinstance(total_time, (int, float)), f"total_time_seconds must be a number, got {type(total_time).__name__}"
    assert 0.693 <= final_result <= 0.694, (
        f"final_result {final_result} is out of expected range (0.693 to 0.694). "
        "Check your RPC call parameters."
    )
    assert math.isclose(final_result, expected_final, rel_tol=1e-12, abs_tol=1e-12)
    assert total_time > 0, f"total_time_seconds {total_time} must be greater than 0."
    assert math.isfinite(total_time)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
