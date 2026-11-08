#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import ctypes
import os
import random
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import grpc
import pytest
from google.protobuf import descriptor_pb2
from grpc_tools import protoc

PROTO_PATH = "/home/user/proto/artifact.proto"
SO_PATH = "/home/user/rust_lib/target/release/librust_lib.so"
SERVER_PATH = "/home/user/server/server.py"
CLIENT_PATH = "/home/user/client.py"
SIG_PATH = "/home/user/final_signature.txt"


def compute_base(payload):
    sig = 0
    for byte in payload:
        sig = (sig * 31 + byte) % 1000000007
    return sig


def original_signature(payload):
    return (compute_base(payload) ^ 0xDEADBEEF) % 9999991


def stop_port_50051_processes():
    wanted = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    parts = line.split()
                    if len(parts) > 9 and parts[3] == "0A":
                        port = int(parts[1].rsplit(":", 1)[1], 16)
                        if port == 50051:
                            wanted.add(parts[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in wanted:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)


@contextlib.contextmanager
def running_server():
    stop_port_50051_processes()
    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH],
        cwd="/home/user/server",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=12)
        assert proc.poll() is None, "server.py exited before serving requests"
        yield channel
    except Exception:
        if proc.poll() is not None:
            pytest.fail(f"server.py exited with status {proc.returncode}")
        raise
    finally:
        channel.close()
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        stop_port_50051_processes()


@pytest.fixture(scope="session")
def generated_proto_modules():
    out_dir = tempfile.mkdtemp(prefix="artifact_proto_")
    result = protoc.main([
        "grpc_tools.protoc",
        "-I/home/user/proto",
        f"--python_out={out_dir}",
        f"--grpc_python_out={out_dir}",
        PROTO_PATH,
    ])
    assert result == 0, "artifact.proto could not be compiled"
    sys.path.insert(0, out_dir)
    try:
        import artifact_pb2
        import artifact_pb2_grpc
        yield artifact_pb2, artifact_pb2_grpc
    finally:
        if out_dir in sys.path:
            sys.path.remove(out_dir)
        shutil.rmtree(out_dir, ignore_errors=True)


def test_proto_file_exists_and_content():
    assert os.path.isfile(PROTO_PATH), f"Protobuf file {PROTO_PATH} is missing."
    with open(PROTO_PATH, "r") as f:
        content = f.read()

    assert "package artifact;" in content, "Proto file is missing 'package artifact;'"
    assert "service ArtifactSigner" in content, "Proto file is missing 'service ArtifactSigner'"
    assert "SignRequest" in content, "Proto file is missing 'SignRequest'"
    assert "SignResponse" in content, "Proto file is missing 'SignResponse'"

    with tempfile.NamedTemporaryFile(suffix=".desc") as desc:
        result = protoc.main([
            "grpc_tools.protoc",
            "-I/home/user/proto",
            f"--descriptor_set_out={desc.name}",
            PROTO_PATH,
        ])
        assert result == 0, "artifact.proto is not valid protobuf"
        descriptor_set = descriptor_pb2.FileDescriptorSet()
        descriptor_set.ParseFromString(Path(desc.name).read_bytes())

    assert len(descriptor_set.file) == 1
    file_desc = descriptor_set.file[0]
    assert file_desc.syntax == "proto3"
    assert file_desc.package == "artifact"

    messages = {message.name: message for message in file_desc.message_type}
    assert set(messages) == {"SignRequest", "SignResponse"}
    request_fields = list(messages["SignRequest"].field)
    response_fields = list(messages["SignResponse"].field)
    assert len(request_fields) == 1
    assert request_fields[0].name == "payload"
    assert request_fields[0].number == 1
    assert request_fields[0].type == request_fields[0].TYPE_BYTES
    assert len(response_fields) == 1
    assert response_fields[0].name == "signature"
    assert response_fields[0].number == 1
    assert response_fields[0].type == response_fields[0].TYPE_UINT64

    assert len(file_desc.service) == 1
    service = file_desc.service[0]
    assert service.name == "ArtifactSigner"
    assert len(service.method) == 1
    method = service.method[0]
    assert method.name == "Sign"
    assert method.input_type == ".artifact.SignRequest"
    assert method.output_type == ".artifact.SignResponse"


def test_rust_library_compiled_and_works():
    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd="/home/user/rust_lib",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, f"Rust release build failed:\n{build.stdout}"
    assert os.path.isfile(SO_PATH), f"Compiled Rust library {SO_PATH} is missing. Did you fix the bug and build in release mode?"

    library = ctypes.CDLL(SO_PATH)
    function = library.process_signature
    function.argtypes = [ctypes.c_uint64]
    function.restype = ctypes.c_uint64
    bases = [0, 1, 305886295, 2**64 - 1]
    bases.extend(random.SystemRandom().randrange(0, 2**64) for _ in range(4))
    for base in bases:
        expected = (base ^ 0xDEADBEEF) % 9999991
        assert function(base) == expected


def test_server_script_exists():
    assert os.path.isfile(SERVER_PATH), f"Server script {SERVER_PATH} is missing."
    content = Path(SERVER_PATH).read_text()
    assert "ctypes" in content, "server.py must use ctypes"
    assert SO_PATH in content, "server.py must load the requested Rust shared object"
    assert "process_signature" in content
    assert "[::]:50051" in content


def test_client_script_exists():
    assert os.path.isfile(CLIENT_PATH), f"Client script {CLIENT_PATH} is missing."


def test_grpc_server_uses_payload_logic_and_loaded_library(generated_proto_modules):
    artifact_pb2, artifact_pb2_grpc = generated_proto_modules
    rng = random.SystemRandom()
    multiplier = rng.randrange(3, 2**32) | 1
    increment = rng.randrange(1, 2**32)
    xor_value = rng.randrange(1, 2**32)

    with tempfile.TemporaryDirectory(prefix="test_library_") as temp_dir:
        source = Path(temp_dir) / "override.c"
        replacement = Path(temp_dir) / "librust_lib.so"
        backup = Path(temp_dir) / "original.so"
        source.write_text(
            "#include <stdint.h>\n"
            "uint64_t process_signature(uint64_t base) {\n"
            f"  return (base * {multiplier}ULL + {increment}ULL) ^ {xor_value}ULL;\n"
            "}\n"
        )
        compile_result = subprocess.run(
            ["gcc", "-shared", "-fPIC", str(source), "-o", str(replacement)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert compile_result.returncode == 0, compile_result.stdout
        shutil.copy2(SO_PATH, backup)
        shutil.copy2(replacement, SO_PATH)
        try:
            with running_server() as channel:
                stub = artifact_pb2_grpc.ArtifactSignerStub(channel)
                payloads = [b"", os.urandom(7), os.urandom(31), b"artifact_v1_release-extra"]
                for payload in payloads:
                    base = compute_base(payload)
                    expected = (((base * multiplier + increment) & ((1 << 64) - 1)) ^ xor_value)
                    response = stub.Sign(artifact_pb2.SignRequest(payload=payload), timeout=5)
                    assert response.signature == expected
        finally:
            shutil.copy2(backup, SO_PATH)


def test_client_executes_against_real_server():
    try:
        os.remove(SIG_PATH)
    except FileNotFoundError:
        pass

    with running_server():
        result = subprocess.run(
            [sys.executable, CLIENT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=20,
        )
        assert result.returncode == 0, f"client.py failed:\n{result.stdout}"

    assert os.path.isfile(SIG_PATH), f"Final signature file {SIG_PATH} is missing. Did you run the client?"


def test_final_signature():
    assert os.path.isfile(SIG_PATH), f"Final signature file {SIG_PATH} is missing. Did you run the client?"
    with open(SIG_PATH, "r") as f:
        content = f.read().strip()

    expected_sig = "6430342"
    assert content == expected_sig, f"Final signature in {SIG_PATH} is incorrect. Expected {expected_sig}, got {content}."
    assert int(content) == original_signature(b"artifact_v1_release")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
