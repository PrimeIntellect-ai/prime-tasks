#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import threading
import time
from concurrent import futures

import grpc
import pytest
import websockets

PROJECT = "/home/user/project"
DIST = "/home/user/dist"
EXE = os.path.join(DIST, "bin", "telemetry_bridge")


@pytest.fixture(scope="session", autouse=True)
def build_and_package():
    script = os.path.join(PROJECT, "build_and_package.sh")
    assert os.path.isfile(script), f"Missing script: {script}"
    assert os.stat(script).st_mode & stat.S_IXUSR, f"Script is not executable: {script}"

    shutil.rmtree(os.path.join(PROJECT, "build"), ignore_errors=True)
    shutil.rmtree(DIST, ignore_errors=True)
    result = subprocess.run(
        [script], cwd=PROJECT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=240
    )
    assert result.returncode == 0, "Packaging script failed:\n" + result.stdout


def test_proto_file_exists_and_content():
    """Verify that telemetry.proto exists and contains the required definitions."""
    proto_path = "/home/user/project/telemetry.proto"
    assert os.path.isfile(proto_path), f"Missing protobuf file: {proto_path}"

    with open(proto_path, "r") as f:
        content = f.read()

    assert "package telemetry;" in content or "package telemetry" in content, "Missing 'telemetry' package in proto file"
    assert "service TelemetryService" in content, "Missing 'TelemetryService' in proto file"
    assert "rpc StreamMetrics" in content, "Missing 'StreamMetrics' RPC in proto file"
    assert "message Metric" in content, "Missing 'Metric' message in proto file"


def test_proto_compiles_and_has_exact_api(tmp_path):
    proto = os.path.join(PROJECT, "telemetry.proto")
    result = subprocess.run([
        sys.executable, "-m", "grpc_tools.protoc", f"-I{PROJECT}",
        f"--python_out={tmp_path}", f"--grpc_python_out={tmp_path}", proto
    ], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert result.returncode == 0, "telemetry.proto does not compile:\n" + result.stdout

    sys.path.insert(0, str(tmp_path))
    try:
        import telemetry_pb2
        desc = telemetry_pb2.DESCRIPTOR
        assert desc.package == "telemetry"
        metric = desc.message_types_by_name["Metric"]
        assert [(f.name, f.number, f.type) for f in metric.fields] == [
            ("name", 1, f.TYPE_STRING), ("value", 2, f.TYPE_DOUBLE)
        ]
        empty = desc.message_types_by_name["EmptyRequest"]
        assert len(empty.fields) == 0
        method = desc.services_by_name["TelemetryService"].methods_by_name["StreamMetrics"]
        assert method.input_type.full_name == "telemetry.EmptyRequest"
        assert method.output_type.full_name == "telemetry.Metric"
        assert method.server_streaming and not method.client_streaming
    finally:
        sys.path.pop(0)


def test_cpp_bridge_file_exists():
    """Verify that bridge.cpp exists."""
    cpp_path = "/home/user/project/bridge.cpp"
    assert os.path.isfile(cpp_path), f"Missing C++ source file: {cpp_path}"


def test_cmake_lists_exists():
    """Verify that CMakeLists.txt exists."""
    cmake_path = "/home/user/project/CMakeLists.txt"
    assert os.path.isfile(cmake_path), f"Missing CMakeLists.txt: {cmake_path}"


def test_build_and_package_script_exists_and_executable():
    """Verify that build_and_package.sh exists and is executable."""
    script_path = "/home/user/project/build_and_package.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script is not executable: {script_path}"


def test_dist_bin_contains_executable():
    """Verify that the packaging script created the dist bin directory and the executable."""
    bin_dir = "/home/user/dist/bin"
    assert os.path.isdir(bin_dir), f"Missing dist bin directory: {bin_dir}"

    exe_path = os.path.join(bin_dir, "telemetry_bridge")
    assert os.path.isfile(exe_path), f"Missing executable in dist: {exe_path}"

    st = os.stat(exe_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Packaged binary is not executable: {exe_path}"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Packaged telemetry_bridge is not an ELF executable"


def test_dist_lib_contains_libraries():
    """Verify that the packaging script copied dynamic libraries into dist lib."""
    lib_dir = "/home/user/dist/lib"
    assert os.path.isdir(lib_dir), f"Missing dist lib directory: {lib_dir}"

    libs = [f for f in os.listdir(lib_dir) if os.path.isfile(os.path.join(lib_dir, f))]
    assert len(libs) >= 3, f"Expected multiple shared libraries packaged in {lib_dir}, found {len(libs)}"

    ldd = subprocess.run(["ldd", EXE], text=True, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, check=True).stdout
    required = []
    for line in ldd.splitlines():
        match = re.search(r"=>\s+(/\S+)", line)
        if match:
            required.append(os.path.basename(match.group(1)))
    assert required, "The packaged executable has no resolved dynamic dependencies"
    missing = [name for name in required if not os.path.isfile(os.path.join(lib_dir, name))]
    assert not missing, "Dynamic dependencies missing from dist/lib: " + ", ".join(missing)


def test_end_to_end_grpc_to_websocket(tmp_path):
    generated = tmp_path / "generated"
    generated.mkdir()
    result = subprocess.run([
        sys.executable, "-m", "grpc_tools.protoc", f"-I{PROJECT}",
        f"--python_out={generated}", f"--grpc_python_out={generated}",
        os.path.join(PROJECT, "telemetry.proto")
    ], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert result.returncode == 0, result.stdout

    sys.path.insert(0, str(generated))
    try:
        import telemetry_pb2
        import telemetry_pb2_grpc

        token = secrets.token_hex(12)
        expected = [
            (f"cpu-{token}", float(secrets.randbelow(900000) + 1000) + 0.125),
            (f"memory-{token}", float(secrets.randbelow(900000) + 1000) + 0.375),
            (f"requests-{token}", float(secrets.randbelow(900000) + 1000) + 0.625),
        ]
        rpc_called = threading.Event()

        class Servicer(telemetry_pb2_grpc.TelemetryServiceServicer):
            def StreamMetrics(self, request, context):
                rpc_called.set()
                index = 0
                while context.is_active():
                    name, value = expected[index % len(expected)]
                    yield telemetry_pb2.Metric(name=name, value=value)
                    index += 1
                    time.sleep(0.12)

        server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
        telemetry_pb2_grpc.add_TelemetryServiceServicer_to_server(Servicer(), server)
        assert server.add_insecure_port("[::]:50051") != 0
        server.start()

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = os.path.join(DIST, "lib")
        process = subprocess.Popen(
            [EXE], cwd=os.path.join(DIST, "bin"), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

        async def exercise_clients():
            uri = "ws://127.0.0.1:8080"
            last_error = None
            for _ in range(80):
                if process.poll() is not None:
                    out, err = process.communicate(timeout=2)
                    raise AssertionError(
                        f"telemetry_bridge exited early with {process.returncode}\nstdout:\n{out}\nstderr:\n{err}"
                    )
                try:
                    async with websockets.connect(uri, open_timeout=0.5) as probe:
                        pass
                    break
                except Exception as exc:
                    last_error = exc
                    await asyncio.sleep(0.1)
            else:
                raise AssertionError(f"Could not connect to WebSocket server on port 8080: {last_error}")

            async with websockets.connect(uri, open_timeout=2) as ws1, \
                       websockets.connect(uri, open_timeout=2) as ws2:
                async def receive(ws):
                    messages = []
                    for _ in range(8):
                        raw = await asyncio.wait_for(ws.recv(), timeout=3)
                        assert isinstance(raw, str), "WebSocket telemetry must be text JSON"
                        obj = json.loads(raw)
                        assert set(obj.keys()) == {"name", "value"}
                        assert isinstance(obj["name"], str)
                        assert isinstance(obj["value"], (int, float)) and not isinstance(obj["value"], bool)
                        matches = [
                            (name, value) for name, value in expected
                            if obj["name"] == name and abs(float(obj["value"]) - value) < 1e-9
                        ]
                        assert matches, f"WebSocket emitted data not supplied by mock gRPC server: {obj!r}"
                        messages.append(matches[0])
                    return messages

                first, second = await asyncio.gather(receive(ws1), receive(ws2))
                assert set(first).intersection(second), "Telemetry was not broadcast to both connected clients"

        try:
            asyncio.run(exercise_clients())
            assert rpc_called.wait(2), "Bridge never called the StreamMetrics RPC"
            assert process.poll() is None, "Bridge stopped while serving telemetry"
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            server.stop(0).wait()
    finally:
        sys.path.pop(0)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
