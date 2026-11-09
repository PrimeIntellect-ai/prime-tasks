#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/project"
BUILD_SCRIPT = os.path.join(PROJECT, "build.sh")
TEST_SCRIPT = os.path.join(PROJECT, "test_sensor.py")
PROTO = os.path.join(PROJECT, "schema", "sensor.proto")


def run_checked(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, timeout=120, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {args}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_build_script_exists_and_executable():
    assert os.path.isfile(BUILD_SCRIPT), f"Build script missing at {BUILD_SCRIPT}"
    st = os.stat(BUILD_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Build script at {BUILD_SCRIPT} is not executable"


def test_test_script_exists():
    assert os.path.isfile(TEST_SCRIPT), f"Test script missing at {TEST_SCRIPT}"


def test_build_and_test_execution():
    # Ensure every artifact and success marker examined below was produced by this run.
    shutil.rmtree(os.path.join(PROJECT, "gen"), ignore_errors=True)
    log_file = os.path.join(PROJECT, "build.log")
    if os.path.exists(log_file):
        os.remove(log_file)

    result_build = subprocess.run(
        [BUILD_SCRIPT], cwd=PROJECT, capture_output=True, text=True, timeout=120
    )
    assert result_build.returncode == 0, (
        f"build.sh failed with output:\n{result_build.stderr}\n{result_build.stdout}"
    )

    go_gen_file = os.path.join(PROJECT, "gen", "go", "sensor.pb.go")
    py_gen_file = os.path.join(PROJECT, "gen", "python", "sensor_pb2.py")
    go_grpc_file = os.path.join(PROJECT, "gen", "go", "sensor_grpc.pb.go")
    py_grpc_file = os.path.join(PROJECT, "gen", "python", "sensor_pb2_grpc.py")

    assert os.path.isfile(go_gen_file), f"Go generated protobuf missing at {go_gen_file}"
    assert os.path.isfile(py_gen_file), f"Python generated protobuf missing at {py_gen_file}"
    assert os.path.isfile(go_grpc_file), f"Go generated gRPC file missing at {go_grpc_file}"
    assert os.path.isfile(py_grpc_file), f"Python generated gRPC file missing at {py_grpc_file}"

    # Independently invoke the required compilers and require the freshly built
    # artifacts to be their genuine deterministic output, rather than placeholders.
    with tempfile.TemporaryDirectory() as expected:
        expected_go = os.path.join(expected, "go")
        expected_python = os.path.join(expected, "python")
        os.makedirs(expected_go)
        os.makedirs(expected_python)

        run_checked([
            "protoc", f"-I{os.path.dirname(PROTO)}",
            f"--go_out=paths=source_relative:{expected_go}",
            f"--go-grpc_out=paths=source_relative:{expected_go}", PROTO,
        ], cwd=PROJECT)
        run_checked([
            "python3", "-m", "grpc_tools.protoc", f"-I{os.path.dirname(PROTO)}",
            f"--python_out={expected_python}",
            f"--grpc_python_out={expected_python}", PROTO,
        ], cwd=PROJECT)

        for actual, reference in [
            (go_gen_file, os.path.join(expected_go, "sensor.pb.go")),
            (go_grpc_file, os.path.join(expected_go, "sensor_grpc.pb.go")),
            (py_gen_file, os.path.join(expected_python, "sensor_pb2.py")),
            (py_grpc_file, os.path.join(expected_python, "sensor_pb2_grpc.py")),
        ]:
            with open(actual, "rb") as af, open(reference, "rb") as rf:
                assert af.read() == rf.read(), f"{actual} is not genuine compiler output"

    # Compile the generated Go package in an isolated temporary module.
    with tempfile.TemporaryDirectory() as go_check:
        shutil.copy(go_gen_file, go_check)
        shutil.copy(go_grpc_file, go_check)
        run_checked(["go", "mod", "init", "verifier.local/sensor"], cwd=go_check)
        run_checked(["go", "mod", "tidy"], cwd=go_check)
        run_checked(["go", "test", "./..."], cwd=go_check)

    result_test = subprocess.run(
        ["python3", TEST_SCRIPT], cwd=PROJECT, capture_output=True, text=True, timeout=120
    )
    assert result_test.returncode == 0, (
        f"test_sensor.py failed with output:\n{result_test.stderr}\n{result_test.stdout}"
    )

    assert os.path.isfile(log_file), f"Log file missing at {log_file}"
    with open(log_file, "r") as f:
        log_content = f.read()
    assert "BUILD_AND_TEST_SUCCESS" in log_content, "Log file does not contain the expected success string."
    assert "BUILD_AND_TEST_SUCCESS" in log_content.splitlines(), (
        "Log file does not contain the exact success marker as a line"
    )

    # Independently import the submitted fixture and exercise the required mock.
    probe = r'''
import sys
sys.path.insert(0, "/home/user/project/gen/python")
sys.path.insert(0, "/home/user/project")
import sensor_pb2
import sensor_pb2_grpc
import test_sensor

assert hasattr(test_sensor, "MockSensorService")
Mock = test_sensor.MockSensorService
assert issubclass(Mock, sensor_pb2_grpc.SensorStreamerServicer)
request = sensor_pb2.SensorRequest(client_id="verifier-independent-client")
responses = list(Mock().FetchData(request, None))
assert len(responses) == 3
assert all(isinstance(item, sensor_pb2.SensorResponse) for item in responses)
expected = [1.1, 2.2, 3.3]
assert all(abs(item.value - value) < 1e-6 for item, value in zip(responses, expected))
assert request.client_id == "verifier-independent-client"
'''
    probe_result = subprocess.run(
        ["python3", "-I", "-c", probe],
        cwd="/tmp", capture_output=True, text=True, timeout=120
    )
    assert probe_result.returncode == 0, (
        "MockSensorService failed independent behavioral validation:\n"
        f"{probe_result.stderr}\n{probe_result.stdout}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
