#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop services left by the agent so the verifier can provide controlled endpoints.
pkill -u user 2>/dev/null || true
pkill -f 'python3 .*grpc_server.py' 2>/dev/null || true
pkill -f 'python3 .*ws_server.py' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import json
import os
import socket
import subprocess
import sys
import time
import uuid
from concurrent import futures

import grpc

HOME = "/home/user"
sys.path.insert(0, HOME)


def test_libextractor_compiled():
    path = "/home/user/libextractor.so"
    assert os.path.isfile(path), f"Shared library {path} does not exist. Did you compile extractor.c?"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF shared library"


def test_pipeline_test_script_exists():
    path = "/home/user/pipeline_test.py"
    assert os.path.isfile(path), f"Python script {path} does not exist."


def test_pipeline_result_log():
    path = "/home/user/pipeline_result.log"
    assert os.path.isfile(path), f"Result log {path} does not exist. Did the pipeline script run successfully?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "SUCCESS_201_METADATA_OK"
    assert content == expected, f"Expected '{expected}' in {path}, but found '{content}'."


def _exercise_library(path):
    code = r'''
import ctypes
import sys
lib = ctypes.CDLL(sys.argv[1])
lib.extract_metadata.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
lib.extract_metadata.restype = None
out = ctypes.create_string_buffer(64)
lib.extract_metadata(b"A" * 10000, out)
assert out.value == b"A" * 15, repr(out.value)
'''
    result = subprocess.run(
        [sys.executable, "-c", code, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Unsafe or incorrect extract_metadata implementation in {path}; "
        f"return code {result.returncode}, stderr: {result.stderr}"
    )


def test_extractor_source_and_shared_library_are_safe():
    _exercise_library(os.path.join(HOME, "libextractor.so"))

    rebuilt = "/tmp/libextractor_rebuilt.so"
    compile_result = subprocess.run(
        ["gcc", "-shared", "-o", rebuilt, "-fPIC", os.path.join(HOME, "extractor.c")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, compile_result.stderr
    _exercise_library(rebuilt)


def _start_ws_server(candidates):
    payload = base64.b64encode(
        json.dumps({"candidates": candidates}).encode("utf-8")
    ).decode("ascii")
    code = r'''
import asyncio
import base64
import os
import websockets

payload = base64.b64decode(os.environ["TEST_WS_PAYLOAD"]).decode("utf-8")

async def handler(websocket, *args):
    await websocket.send(payload)
    await asyncio.sleep(2)

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8080):
        await asyncio.Future()

asyncio.run(main())
'''
    env = os.environ.copy()
    env["TEST_WS_PAYLOAD"] = payload
    proc = subprocess.Popen(
        [sys.executable, "-c", code],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )

    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Controlled WebSocket server failed: {proc.stderr.read()}")
        sock = socket.socket()
        try:
            if sock.connect_ex(("127.0.0.1", 8080)) == 0:
                return proc
        finally:
            sock.close()
        time.sleep(0.05)
    proc.terminate()
    raise AssertionError("Controlled WebSocket server did not start")


def _remove_generated_bindings():
    for path in (
        os.path.join(HOME, "build_service_pb2.py"),
        os.path.join(HOME, "build_service_pb2_grpc.py"),
    ):
        if os.path.exists(path):
            os.remove(path)
    for path in glob.glob(os.path.join(HOME, "__pycache__", "build_service_pb2*.pyc")):
        os.remove(path)


def test_pipeline_script_uses_websocket_semver_and_grpc():
    import build_service_pb2
    import build_service_pb2_grpc

    state = {"expected": None, "token": None, "requests": []}

    class ControlledServicer(build_service_pb2_grpc.PipelineTesterServicer):
        def ValidateRelease(self, request, context):
            state["requests"].append(request.version_payload)
            if request.version_payload != state["expected"]:
                return build_service_pb2.ReleaseReply(
                    validation_code="WRONG_VERSION_" + uuid.uuid4().hex
                )
            return build_service_pb2.ReleaseReply(validation_code=state["token"])

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
    build_service_pb2_grpc.add_PipelineTesterServicer_to_server(ControlledServicer(), server)
    assert server.add_insecure_port("[::]:50051") == 50051
    server.start()

    cases = [
        (["3.9.99", "3.10.0", "99.0.0-alpha", "2.100.0", "3.10.0-rc.1"], "3.10.0"),
        (["9.99.99", "10.0.0", "10.0.1-beta.2", "8.0.0+build.7", "0.0.1"], "10.0.0"),
    ]

    try:
        for candidates, expected_version in cases:
            state["expected"] = expected_version
            state["token"] = "VALIDATION_" + uuid.uuid4().hex
            before = len(state["requests"])
            ws_proc = _start_ws_server(candidates)
            try:
                result_path = os.path.join(HOME, "pipeline_result.log")
                if os.path.exists(result_path):
                    os.remove(result_path)

                # The task requires the script to generate these bindings itself.
                _remove_generated_bindings()
                run = subprocess.run(
                    [sys.executable, os.path.join(HOME, "pipeline_test.py")],
                    cwd=HOME,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                assert run.returncode == 0, (
                    f"pipeline_test.py failed with code {run.returncode}\n"
                    f"stdout: {run.stdout}\nstderr: {run.stderr}"
                )
                assert os.path.isfile(result_path), "pipeline_test.py did not create pipeline_result.log"
                with open(result_path, "r") as f:
                    actual = f.read()
                assert actual == state["token"], (
                    "pipeline_result.log was not exactly the validation code returned by the RPC"
                )
                assert state["requests"][before:] == [expected_version], (
                    f"Expected one ValidateRelease call with {expected_version}, "
                    f"got {state['requests'][before:]}"
                )
                assert os.path.isfile(os.path.join(HOME, "build_service_pb2.py"))
                assert os.path.isfile(os.path.join(HOME, "build_service_pb2_grpc.py"))
            finally:
                ws_proc.terminate()
                try:
                    ws_proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    ws_proc.kill()
    finally:
        server.stop(0).wait()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
