#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import random
import signal
import stat
import subprocess
import sys
import tempfile
import time

import pytest

try:
    import grpc
    from grpc_tools import protoc
except ImportError:
    pytest.fail("grpcio or grpcio-tools is not installed.")

try:
    import cv2
except ImportError:
    pytest.fail("opencv-python (cv2) is not installed.")

PIPELINE_DIR = "/home/user/video_pipeline"
BUILD_SH = os.path.join(PIPELINE_DIR, "build.sh")
CHECKSUM_C = os.path.join(PIPELINE_DIR, "checksum.c")
LIB_SO = os.path.join(PIPELINE_DIR, "libchecksum.so")
PROTO_FILE = os.path.join(PIPELINE_DIR, "service.proto")
SERVER_PY = os.path.join(PIPELINE_DIR, "server.py")
SERVER_PID = os.path.join(PIPELINE_DIR, "server.pid")
VIDEO_FILE = "/app/drone_flight.mp4"

EXPECTED_C = r'''#include <stdint.h>
#include <stddef.h>

// Computes a simple XOR-based checksum for error-checking
uint32_t compute_frame_checksum(const uint8_t* data, size_t length) {
    uint32_t checksum = 0x811c9dc5;
    for (size_t i = 0; i < length; i++) {
        checksum ^= data[i];
        checksum *= 0x01000193;
    }
    return checksum;
}'''

EXPECTED_PROTO = r'''syntax = "proto3";
package video;

service FrameAnalyzer {
    rpc GetFrameChecksum (FrameRequest) returns (FrameChecksumReply) {}
}

message FrameRequest {
    int32 frame_number = 1;
}

message FrameChecksumReply {
    uint32 checksum = 1;
}'''


def compute_expected_checksum(frame_number: int) -> int:
    cap = cv2.VideoCapture(VIDEO_FILE)
    if not cap.isOpened():
        pytest.fail(f"Could not open video file {VIDEO_FILE}")
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_number)
    ret, frame = cap.read()
    cap.release()
    if not ret:
        pytest.fail(f"Could not read frame {frame_number} from {VIDEO_FILE}")

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    checksum = 0x811C9DC5
    for byte in gray.flatten().tobytes():
        checksum ^= byte
        checksum = (checksum * 0x01000193) & 0xFFFFFFFF
    return checksum


def probe_expected(frame_number: int) -> int:
    cap = cv2.VideoCapture(VIDEO_FILE)
    if not cap.isOpened():
        pytest.fail(f"Could not open video file {VIDEO_FILE}")
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_number)
    ret, frame = cap.read()
    cap.release()
    if not ret:
        pytest.fail(f"Could not read frame {frame_number} from {VIDEO_FILE}")
    data = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).flatten().tobytes()
    if not data:
        return 0x13572468
    return (0x13572468 ^ len(data) ^ (data[0] << 16) ^
            (data[len(data) // 2] << 8) ^ data[-1]) & 0xFFFFFFFF


def stop_pid(pid):
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def launch_server():
    log = open("/tmp/video_pipeline_server.log", "ab", buffering=0)
    proc = subprocess.Popen(
        [sys.executable, SERVER_PY], cwd=PIPELINE_DIR,
        stdout=log, stderr=subprocess.STDOUT
    )
    with open(SERVER_PID, "w") as f:
        f.write(str(proc.pid))
    try:
        grpc.channel_ready_future(
            grpc.insecure_channel("127.0.0.1:50051")
        ).result(timeout=10)
    except Exception:
        stop_pid(proc.pid)
        pytest.fail("server.py did not begin listening on port 50051")
    assert proc.poll() is None, "server.py exited unexpectedly"
    return proc


@pytest.fixture(scope="session", autouse=True)
def rebuilt_running_server():
    assert os.path.isfile(CHECKSUM_C), f"C source {CHECKSUM_C} does not exist."
    with open(CHECKSUM_C) as f:
        assert f.read().strip() == EXPECTED_C.strip(), "checksum.c does not contain the prescribed implementation"

    assert os.path.isfile(PROTO_FILE), f"Proto file {PROTO_FILE} does not exist."
    with open(PROTO_FILE) as f:
        assert f.read().strip() == EXPECTED_PROTO.strip(), "service.proto does not contain the prescribed schema"

    assert os.path.isfile(SERVER_PY), f"Server source {SERVER_PY} does not exist."
    with open(SERVER_PY) as f:
        server_source = f.read()
    ast.parse(server_source)
    assert "ctypes" in server_source, "server.py does not use ctypes"
    assert ("CDLL" in server_source or "LoadLibrary" in server_source), "server.py does not load a shared library with ctypes"
    assert "libchecksum.so" in server_source, "server.py does not load libchecksum.so"
    assert "compute_frame_checksum" in server_source, "server.py does not call compute_frame_checksum"

    assert os.path.isfile(SERVER_PID), f"PID file {SERVER_PID} does not exist."
    try:
        old_pid = int(open(SERVER_PID).read().strip())
        cmdline = open(f"/proc/{old_pid}/cmdline", "rb").read().replace(b"\0", b" ")
    except (ValueError, OSError):
        pytest.fail("server.pid does not identify a running process")
    assert b"server.py" in cmdline, "server.pid does not identify the running Python gRPC server"
    stop_pid(old_pid)

    for artifact in (LIB_SO,
                     os.path.join(PIPELINE_DIR, "service_pb2.py"),
                     os.path.join(PIPELINE_DIR, "service_pb2_grpc.py")):
        try:
            os.unlink(artifact)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [BUILD_SH], cwd=PIPELINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert result.returncode == 0, f"build.sh failed:\n{result.stdout}"
    assert os.path.isfile(LIB_SO), "build.sh did not create libchecksum.so"
    assert os.path.isfile(os.path.join(PIPELINE_DIR, "service_pb2.py")), "build.sh did not generate service_pb2.py"
    assert os.path.isfile(os.path.join(PIPELINE_DIR, "service_pb2_grpc.py")), "build.sh did not generate service_pb2_grpc.py"

    state = {"proc": launch_server()}
    yield state
    # Leave a valid server running as required by the task.


def test_build_script_exists_and_executable():
    assert os.path.exists(BUILD_SH), f"Build script {BUILD_SH} does not exist."
    st = os.stat(BUILD_SH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Build script {BUILD_SH} is not executable."


def test_libchecksum_exists():
    assert os.path.exists(LIB_SO), f"Shared library {LIB_SO} does not exist."
    lib = ctypes.CDLL(LIB_SO)
    fn = lib.compute_frame_checksum
    fn.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    fn.restype = ctypes.c_uint32
    sample = bytes([0, 1, 2, 127, 128, 255])
    array = (ctypes.c_uint8 * len(sample)).from_buffer_copy(sample)
    expected = 0x811C9DC5
    for byte in sample:
        expected ^= byte
        expected = (expected * 0x01000193) & 0xFFFFFFFF
    assert fn(array, len(sample)) == expected, "libchecksum.so does not implement the prescribed checksum"


def compile_proto(tmpdir):
    protoc_args = [
        "grpc_tools.protoc",
        f"--proto_path={PIPELINE_DIR}",
        f"--python_out={tmpdir}",
        f"--grpc_python_out={tmpdir}",
        PROTO_FILE,
    ]
    assert protoc.main(protoc_args) == 0, "Failed to compile service.proto"
    sys.path.insert(0, tmpdir)
    try:
        import service_pb2
        import service_pb2_grpc
        return service_pb2, service_pb2_grpc
    except ImportError as exc:
        pytest.fail(f"Failed to import generated proto modules: {exc}")


def test_grpc_service():
    with tempfile.TemporaryDirectory() as tmpdir:
        service_pb2, service_pb2_grpc = compile_proto(tmpdir)
        cap = cv2.VideoCapture(VIDEO_FILE)
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        cap.release()
        assert frame_count > 20, "Video does not contain enough test frames"

        rng = random.SystemRandom()
        candidates = [n for n in range(frame_count) if n != 15]
        frame_numbers = [0, frame_count - 1] + rng.sample(candidates, min(6, len(candidates)))
        channel = grpc.insecure_channel("0.0.0.0:50051")
        stub = service_pb2_grpc.FrameAnalyzerStub(channel)
        try:
            for frame_number in frame_numbers:
                expected = compute_expected_checksum(frame_number)
                response = stub.GetFrameChecksum(
                    service_pb2.FrameRequest(frame_number=frame_number), timeout=5
                )
                assert response.checksum == expected, (
                    f"Frame {frame_number}: expected checksum {expected}, got {response.checksum}"
                )
        except grpc.RpcError as exc:
            pytest.fail(f"gRPC call failed: {exc}")
        finally:
            channel.close()
            sys.path.pop(0)
            sys.modules.pop("service_pb2", None)
            sys.modules.pop("service_pb2_grpc", None)


def test_service_really_calls_c_library(rebuilt_running_server):
    state = rebuilt_running_server
    real_backup = LIB_SO + ".verifier-real"
    stop_pid(state["proc"].pid)
    state["proc"] = None
    os.replace(LIB_SO, real_backup)

    probe_source = r'''#include <stdint.h>
#include <stddef.h>
uint32_t compute_frame_checksum(const uint8_t* data, size_t length) {
    if (length == 0) return 0x13572468u;
    return 0x13572468u ^ (uint32_t)length ^
           ((uint32_t)data[0] << 16) ^
           ((uint32_t)data[length / 2] << 8) ^
           (uint32_t)data[length - 1];
}
'''
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".c", delete=False) as f:
            f.write(probe_source)
            probe_c = f.name
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", LIB_SO, probe_c],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )
        assert result.returncode == 0, f"Could not build verifier probe library:\n{result.stdout}"
        state["proc"] = launch_server()

        with tempfile.TemporaryDirectory() as tmpdir:
            service_pb2, service_pb2_grpc = compile_proto(tmpdir)
            frame_number = random.SystemRandom().randrange(0, 250)
            channel = grpc.insecure_channel("127.0.0.1:50051")
            try:
                response = service_pb2_grpc.FrameAnalyzerStub(channel).GetFrameChecksum(
                    service_pb2.FrameRequest(frame_number=frame_number), timeout=5
                )
                assert response.checksum == probe_expected(frame_number), (
                    "The service did not return the value produced by libchecksum.so "
                    "for the exact flattened grayscale frame bytes"
                )
            finally:
                channel.close()
                sys.path.pop(0)
                sys.modules.pop("service_pb2", None)
                sys.modules.pop("service_pb2_grpc", None)
    finally:
        if state.get("proc") is not None:
            stop_pid(state["proc"].pid)
        try:
            os.unlink(LIB_SO)
        except FileNotFoundError:
            pass
        if os.path.exists(real_backup):
            os.replace(real_backup, LIB_SO)
        state["proc"] = launch_server()
        try:
            os.unlink(probe_c)
        except (NameError, FileNotFoundError):
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
