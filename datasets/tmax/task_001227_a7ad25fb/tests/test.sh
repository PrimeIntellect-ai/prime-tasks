#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib
import os
import secrets
import shutil
import string
import subprocess
import sys
import time

import grpc

WORKSPACE_DIR = "/home/user/workspace"
BUILD_SCRIPT = os.path.join(WORKSPACE_DIR, "build.sh")
SERVER_FILE = os.path.join(WORKSPACE_DIR, "server.py")
CLIENT_FILE = os.path.join(WORKSPACE_DIR, "test_client.py")
C_FILE = os.path.join(WORKSPACE_DIR, "artifact_utils.c")
SO_FILE = os.path.join(WORKSPACE_DIR, "libartifact.so")
LOG_FILE = os.path.join(WORKSPACE_DIR, "test_result.log")
PB2_FILE = os.path.join(WORKSPACE_DIR, "artifact_pb2.py")
PB2_GRPC_FILE = os.path.join(WORKSPACE_DIR, "artifact_pb2_grpc.py")
FIXED_FILENAME = "superlongversionstringthatwilloverflow_build123"


def random_letters(n):
    return "".join(secrets.choice(string.ascii_letters) for _ in range(n))


def stop_server(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def start_server():
    env = os.environ.copy()
    env["PYTHONPATH"] = WORKSPACE_DIR + os.pathsep + env.get("PYTHONPATH", "")
    proc = subprocess.Popen(
        ["python3", SERVER_FILE],
        cwd=WORKSPACE_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=8)
    except Exception as exc:
        stop_server(proc)
        stdout, stderr = proc.communicate()
        channel.close()
        raise AssertionError(
            f"gRPC server did not become ready: {exc}\nSTDOUT: {stdout}\nSTDERR: {stderr}"
        )
    return proc, channel


def call_extract(extract_version, value):
    # Eight-byte guards surround the exact 16-byte output region.
    storage = (ctypes.c_ubyte * 32)(*([0xA5] * 32))
    output = ctypes.cast(ctypes.byref(storage, 8), ctypes.c_char_p)
    extract_version(value, output)
    raw = bytes(storage)
    assert raw[:8] == bytes([0xA5] * 8), "C function wrote before version_out"
    assert raw[24:] == bytes([0xA5] * 8), "C function wrote past the 16-byte output buffer"
    region = raw[8:24]
    expected = value.split(b"_", 1)[0][:15]
    assert region[:len(expected)] == expected
    assert region[len(expected)] == 0, "Output was not null-terminated within 16 bytes"
    return region.split(b"\0", 1)[0]


def test_complete_implementation():
    # Preserve the original existence and executability assertions.
    assert os.path.isfile(BUILD_SCRIPT), f"Build script not found: {BUILD_SCRIPT}"
    assert os.access(BUILD_SCRIPT, os.X_OK), f"Build script is not executable: {BUILD_SCRIPT}"
    assert os.path.isfile(SERVER_FILE), f"Server file not found: {SERVER_FILE}"
    assert os.path.isfile(CLIENT_FILE), f"Client file not found: {CLIENT_FILE}"
    assert os.path.isfile(C_FILE), f"C source not found: {C_FILE}"

    # Generated and compiled artifacts must be produced by this invocation.
    for path in (SO_FILE, PB2_FILE, PB2_GRPC_FILE):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    result = subprocess.run(
        [BUILD_SCRIPT], cwd=WORKSPACE_DIR, capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, (
        f"Build script failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert os.path.isfile(SO_FILE), f"Shared library not found after build: {SO_FILE}"
    assert os.path.isfile(PB2_FILE), f"Generated protobuf module not found: {PB2_FILE}"
    assert os.path.isfile(PB2_GRPC_FILE), f"Generated gRPC module not found: {PB2_GRPC_FILE}"

    # Retain the original fixed C assertion, then exercise derived random cases and guards.
    lib = ctypes.CDLL(SO_FILE)
    extract_version = lib.extract_version
    extract_version.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    extract_version.restype = None

    buf = ctypes.create_string_buffer(b"A" * 20, 20)
    extract_version(FIXED_FILENAME.encode(), buf)
    assert buf.value == b"superlongversio", f"Expected 'superlongversio', got {buf.value}"
    assert buf[15] == b"\x00", "Buffer was not properly null-terminated at the 16th byte"
    assert buf[16] == b"A", "Buffer overflow detected! Wrote past the 16-byte limit."

    c_inputs = [
        b"",
        b"_suffix",
        b"abc_suffix",
        random_letters(7).encode() + b"_" + random_letters(11).encode(),
        random_letters(15).encode() + b"_tail",
        random_letters(16).encode() + b"_tail",
        random_letters(43).encode() + b"_tail",
        random_letters(37).encode(),
        random_letters(512).encode() + b"_tail",
    ]
    for value in c_inputs:
        assert call_extract(extract_version, value) == value.split(b"_", 1)[0][:15]

    # Verify that the generated modules describe the supplied proto service and messages.
    sys.path.insert(0, WORKSPACE_DIR)
    importlib.invalidate_caches()
    artifact_pb2 = importlib.import_module("artifact_pb2")
    artifact_pb2_grpc = importlib.import_module("artifact_pb2_grpc")
    service = artifact_pb2.DESCRIPTOR.services_by_name.get("ArtifactManager")
    assert service is not None, "ArtifactManager service missing from generated protobuf module"
    assert "GetVersion" in service.methods_by_name, "GetVersion RPC missing from generated stubs"
    assert artifact_pb2.ArtifactRequest.DESCRIPTOR.fields_by_name["filename"].number == 1
    assert artifact_pb2.ArtifactResponse.DESCRIPTOR.fields_by_name["version"].number == 1
    assert hasattr(artifact_pb2_grpc, "ArtifactManagerStub")
    assert hasattr(artifact_pb2_grpc, "ArtifactManagerServicer")

    # Replace the library temporarily with an unpredictable probe implementation. A valid
    # server must call the C function and forward the client's required filename to pass.
    backup_so = "/tmp/libartifact.original.so"
    probe_c = "/tmp/artifact_probe.c"
    probe_so = "/tmp/libartifact.probe.so"
    probe_token = "p" + random_letters(12)
    probe_other = "o" + random_letters(12)
    shutil.copy2(SO_FILE, backup_so)
    with open(probe_c, "w") as f:
        f.write(
            '#include <string.h>\n'
            'void extract_version(const char *filename, char *version_out) {\n'
            f'  const char *v = strcmp(filename, "{FIXED_FILENAME}") == 0 ? "{probe_token}" : "{probe_other}";\n'
            '  memcpy(version_out, v, strlen(v) + 1);\n'
            '}\n'
        )
    probe_build = subprocess.run(
        ["gcc", "-shared", "-fPIC", probe_c, "-o", probe_so],
        capture_output=True,
        text=True,
    )
    assert probe_build.returncode == 0, probe_build.stderr

    probe_proc = None
    probe_channel = None
    try:
        shutil.copy2(probe_so, SO_FILE)
        probe_proc, probe_channel = start_server()
        stub = artifact_pb2_grpc.ArtifactManagerStub(probe_channel)
        fixed_reply = stub.GetVersion(
            artifact_pb2.ArtifactRequest(filename=FIXED_FILENAME), timeout=5
        )
        assert fixed_reply.version == probe_token, "Server did not return the C function's result"

        random_filename = random_letters(19) + "_" + random_letters(8)
        other_reply = stub.GetVersion(
            artifact_pb2.ArtifactRequest(filename=random_filename), timeout=5
        )
        assert other_reply.version == probe_other, "Server did not forward the RPC filename to C"

        if os.path.exists(LOG_FILE):
            os.unlink(LOG_FILE)
        client_result = subprocess.run(
            ["python3", CLIENT_FILE],
            cwd=WORKSPACE_DIR,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert client_result.returncode == 0, (
            f"Client failed against probe server:\nSTDOUT: {client_result.stdout}\n"
            f"STDERR: {client_result.stderr}"
        )
        assert os.path.isfile(LOG_FILE), f"Log file not created: {LOG_FILE}"
        with open(LOG_FILE) as f:
            assert f.read().strip() == f"Extracted: {probe_token}", (
                "Client did not send the required filename and write the live RPC response"
            )
    finally:
        if probe_channel is not None:
            probe_channel.close()
        if probe_proc is not None:
            stop_server(probe_proc)
        shutil.copy2(backup_so, SO_FILE)

    # Exercise the real library through the real server on answers derived at runtime.
    server_proc = None
    channel = None
    try:
        server_proc, channel = start_server()
        stub = artifact_pb2_grpc.ArtifactManagerStub(channel)
        grpc_inputs = [
            "",
            "_suffix",
            random_letters(5) + "_" + random_letters(8),
            random_letters(15) + "_tail",
            random_letters(16) + "_tail",
            random_letters(41) + "_" + random_letters(9),
            random_letters(27),
        ]
        for filename in grpc_inputs:
            reply = stub.GetVersion(
                artifact_pb2.ArtifactRequest(filename=filename), timeout=5
            )
            expected = filename.split("_", 1)[0][:15]
            assert reply.version == expected, (
                f"GetVersion({filename!r}) returned {reply.version!r}, expected {expected!r}"
            )

        # Run the requested fixture rather than trusting a pre-existing log.
        if os.path.exists(LOG_FILE):
            os.unlink(LOG_FILE)
        client_result = subprocess.run(
            ["python3", CLIENT_FILE],
            cwd=WORKSPACE_DIR,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert client_result.returncode == 0, (
            f"Client failed:\nSTDOUT: {client_result.stdout}\nSTDERR: {client_result.stderr}"
        )
        assert os.path.isfile(LOG_FILE), f"Log file not created: {LOG_FILE}"
        with open(LOG_FILE) as f:
            content = f.read().strip()
        assert "Extracted: superlongversio" in content, f"Log file content incorrect. Got: {content}"
        assert content == "Extracted: superlongversio", f"Unexpected log format: {content!r}"
    finally:
        if channel is not None:
            channel.close()
        if server_proc is not None:
            stop_server(server_proc)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
