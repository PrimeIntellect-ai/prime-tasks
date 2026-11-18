#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import sys
import tempfile
import time

import grpc
import pytest
from grpc_tools import protoc

PROTO_PATH = "/home/user/emulator.proto"
SERVER_PATH = "/home/user/server.py"
CLIENT_PATH = "/home/user/client.py"
PAYLOAD_PATH = "/home/user/test_payload.bin"
RESULTS_PATH = "/home/user/test_results.json"


def test_emulator_proto_exists_and_valid():
    proto_path = PROTO_PATH
    assert os.path.exists(proto_path), f"File {proto_path} does not exist."

    with open(proto_path, "r") as f:
        content = f.read()

    assert 'syntax = "proto3";' in content or "syntax='proto3';" in content.replace(" ", ""), "Missing proto3 syntax declaration."
    assert "package iot_test;" in content, "Missing package iot_test declaration."
    assert "service Emulator" in content, "Missing Emulator service."
    assert "rpc ExecuteFirmware" in content, "Missing ExecuteFirmware RPC."
    assert "message FirmwareRequest" in content, "Missing FirmwareRequest message."
    assert "message FirmwareResponse" in content, "Missing FirmwareResponse message."
    assert "bytes bytecode = 1;" in content, "FirmwareRequest missing bytes bytecode field."
    assert "repeated int32 readings = 1;" in content, "FirmwareResponse missing repeated int32 readings field."

    out_dir = tempfile.mkdtemp(prefix="verifier_proto_")
    result = protoc.main([
        "grpc_tools.protoc",
        "-I/home/user",
        f"--python_out={out_dir}",
        f"--grpc_python_out={out_dir}",
        PROTO_PATH,
    ])
    assert result == 0, "emulator.proto could not be compiled."


def test_scripts_exist():
    server_path = SERVER_PATH
    client_path = CLIENT_PATH
    assert os.path.exists(server_path), f"File {server_path} does not exist."
    assert os.path.exists(client_path), f"File {client_path} does not exist."
    assert os.path.isfile(server_path), f"File {server_path} is not a regular file."
    assert os.path.isfile(client_path), f"File {client_path} is not a regular file."


def _stop_existing_servers():
    me = os.getpid()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == me:
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\x00", b" ")
            if b"server.py" in cmdline and (b"/home/user/server.py" in cmdline or b"python" in cmdline):
                os.kill(int(name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.4)


@pytest.fixture(scope="session")
def running_emulator():
    # The submitted server must be able to establish its own generated protobuf
    # modules rather than relying on artifacts left by an earlier manual run.
    _stop_existing_servers()
    for path in ("/home/user/emulator_pb2.py", "/home/user/emulator_pb2_grpc.py"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    generated = tempfile.mkdtemp(prefix="verifier_stubs_")
    rc = protoc.main([
        "grpc_tools.protoc",
        "-I/home/user",
        f"--python_out={generated}",
        f"--grpc_python_out={generated}",
        PROTO_PATH,
    ])
    assert rc == 0, "Failed to compile submitted protobuf for verifier stubs."
    sys.path.insert(0, generated)
    import emulator_pb2
    import emulator_pb2_grpc

    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=12)
        time.sleep(0.25)
        assert proc.poll() is None, "server.py exited instead of serving on port 50051."
        stub = emulator_pb2_grpc.EmulatorStub(channel)
        yield proc, channel, stub, emulator_pb2
    finally:
        channel.close()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)


def _run_client():
    completed = subprocess.run(
        [sys.executable, CLIENT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, f"client.py failed: {completed.stderr}"


def test_results_json_correct(running_emulator):
    # Recreate the supplied payload, execute the submitted client, and retain the
    # original expected-results assertion.
    payload = b"\x01\x14\x03\x02\x05\x03\x02\xfb\x03\x04"
    with open(PAYLOAD_PATH, "wb") as f:
        f.write(payload)
    try:
        os.remove(RESULTS_PATH)
    except FileNotFoundError:
        pass
    _run_client()

    results_path = RESULTS_PATH
    assert os.path.exists(results_path), f"File {results_path} does not exist. Did the client script run successfully?"
    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} does not contain valid JSON.")

    expected_results = [20, 25, 20]
    assert results == expected_results, f"Expected {expected_results} in {results_path}, but got {results}."


def test_vm_on_derived_random_programs(running_emulator):
    _, _, stub, pb2 = running_emulator
    rng = secrets.SystemRandom()

    # A new request must begin with temp initialized to zero.
    response = stub.ExecuteFirmware(pb2.FirmwareRequest(bytecode=b"\x03\x04"), timeout=4)
    assert list(response.readings) == [0]

    for _ in range(12):
        temp = 0
        expected = []
        code = bytearray()
        initial = rng.randint(-128, 127)
        code.extend((0x01, initial & 0xff))
        temp = initial
        code.append(0x03)
        expected.append(temp)

        for _ in range(rng.randint(8, 25)):
            choice = rng.choice((1, 2, 2, 3))
            if choice == 1:
                value = rng.randint(-128, 127)
                code.extend((0x01, value & 0xff))
                temp = value
            elif choice == 2:
                value = rng.randint(-128, 127)
                code.extend((0x02, value & 0xff))
                temp += value
            else:
                code.append(0x03)
                expected.append(temp)
        code.extend((0x03, 0x04))
        expected.append(temp)

        response = stub.ExecuteFirmware(pb2.FirmwareRequest(bytecode=bytes(code)), timeout=4)
        assert list(response.readings) == expected


def test_end_ignores_all_trailing_bytes(running_emulator):
    _, _, stub, pb2 = running_emulator
    trailing = secrets.token_bytes(30)
    code = bytes((0x01, 0xF9, 0x03, 0x04)) + trailing
    response = stub.ExecuteFirmware(pb2.FirmwareRequest(bytecode=code), timeout=4)
    assert list(response.readings) == [-7]


def test_payload_size_rejection(running_emulator):
    _, _, stub, pb2 = running_emulator
    oversized = secrets.token_bytes(129)
    with pytest.raises(grpc.RpcError) as caught:
        stub.ExecuteFirmware(pb2.FirmwareRequest(bytecode=oversized), timeout=4)
    assert caught.value.code() == grpc.StatusCode.INVALID_ARGUMENT
    assert caught.value.details() == "Payload too large"


def test_invalid_opcode_rejection(running_emulator):
    _, _, stub, pb2 = running_emulator
    invalid = secrets.choice(tuple(range(0x05, 0x100)))
    with pytest.raises(grpc.RpcError) as caught:
        stub.ExecuteFirmware(pb2.FirmwareRequest(bytecode=bytes((invalid,))), timeout=4)
    assert caught.value.code() == grpc.StatusCode.INVALID_ARGUMENT
    assert caught.value.details() == "Invalid opcode"


def test_client_reads_payload_and_serializes_dynamic_response(running_emulator):
    rng = secrets.SystemRandom()
    start = rng.randint(-128, 127)
    delta1 = rng.randint(-128, 127)
    delta2 = rng.randint(-128, 127)
    expected = [start, start + delta1, start + delta1 + delta2]
    payload = bytes((
        0x01, start & 0xff, 0x03,
        0x02, delta1 & 0xff, 0x03,
        0x02, delta2 & 0xff, 0x03,
        0x04,
    ))
    with open(PAYLOAD_PATH, "wb") as f:
        f.write(payload)
    try:
        os.remove(RESULTS_PATH)
    except FileNotFoundError:
        pass

    _run_client()
    assert os.path.exists(RESULTS_PATH), "client.py did not create test_results.json."
    with open(RESULTS_PATH, "r") as f:
        actual = json.load(f)
    assert actual == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
