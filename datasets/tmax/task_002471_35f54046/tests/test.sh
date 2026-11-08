#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import socket
import stat
import time
import uuid

import grpc
import pytest

PROJECT_DIR = "/home/user/project"


def test_start_sh_exists_and_executable():
    script_path = os.path.join(PROJECT_DIR, "start.sh")
    assert os.path.isfile(script_path), f"Deployment script {script_path} does not exist."

    st = os.stat(script_path)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"Deployment script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()
    assert "make all" in content, f"{script_path} does not seem to run 'make all'."


def _server_pid():
    pid_file = os.path.join(PROJECT_DIR, "server.pid")
    assert os.path.isfile(pid_file), f"PID file {pid_file} was not created."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer PID. Found: '{pid_str}'"
    return int(pid_str)


def test_server_pid_exists_and_valid():
    pid_file = os.path.join(PROJECT_DIR, "server.pid")
    pid = _server_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} from {pid_file} is not running.")


def test_server_pid_owns_port_50051():
    pid = _server_pid()
    listener_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == 50051:
                        listener_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owned = set()
    fd_dir = f"/proc/{pid}/fd"
    for fd in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, fd))
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            owned.add(target[8:-1])
    assert listener_inodes & owned, f"PID {pid} does not own the listener on port 50051."


def test_build_artifacts_exist():
    so_path = os.path.join(PROJECT_DIR, "build/libprocessor.so")
    assert os.path.isfile(so_path), f"Shared library {so_path} was not built."

    pb2_path = os.path.join(PROJECT_DIR, "python/metadata_pb2.py")
    assert os.path.isfile(pb2_path), f"Protobuf python file {pb2_path} was not generated."

    grpc_path = os.path.join(PROJECT_DIR, "python/metadata_pb2_grpc.py")
    assert os.path.isfile(grpc_path), f"gRPC python file {grpc_path} was not generated."


def test_cpp_bug_fixed():
    cpp_path = os.path.join(PROJECT_DIR, "cpp/processor.cpp")
    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} is missing."

    with open(cpp_path, "r") as f:
        content = f.read()

    assert "char temp[50];" not in content, f"The 50-byte buffer overflow vulnerability is still present in {cpp_path}."
    assert "strcpy(" not in content, f"Unsafe 'strcpy' is still being used in {cpp_path}."


def test_makefile_completed():
    makefile_path = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile {makefile_path} is missing."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "Not implemented" not in content, f"Makefile at {makefile_path} still contains the 'Not implemented' stub."
    assert "libprocessor.so" in content, f"Makefile at {makefile_path} does not contain rules for building libprocessor.so."
    assert "protoc" in content or "python -m grpc_tools.protoc" in content, f"Makefile at {makefile_path} does not contain rules for compiling protobufs."


def test_python_server_implemented():
    server_path = os.path.join(PROJECT_DIR, "python/server.py")
    assert os.path.isfile(server_path), f"Python server file {server_path} is missing."

    with open(server_path, "r") as f:
        content = f.read()

    assert "RESOURCE_EXHAUSTED" in content, f"Python server {server_path} does not seem to handle the RESOURCE_EXHAUSTED gRPC status code for rate limiting."
    assert "Rate limit exceeded" in content, f"Python server {server_path} does not contain the exact required error message 'Rate limit exceeded'."
    assert "ctypes" in content, f"Python server {server_path} does not seem to use ctypes to load the shared library."


def test_server_port_open():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        result = s.connect_ex(("127.0.0.1", 50051))
        assert result == 0, "The gRPC server does not appear to be listening on port 50051."
    finally:
        s.close()


def test_shared_library_processes_large_inputs_safely():
    so_path = os.path.join(PROJECT_DIR, "build/libprocessor.so")
    library = ctypes.CDLL(so_path)
    process_data = library.process_data
    process_data.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
    process_data.restype = None

    for size in (0, 51, 500, 1000):
        data = ("x" * size).encode("ascii")
        output = ctypes.create_string_buffer(1024)
        process_data(data, output)
        assert output.value == b"Processed: " + data


def _varint(value):
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7f) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def _request(client_id, data):
    client = client_id.encode("utf-8")
    payload = data.encode("utf-8")
    return b"\x0a" + _varint(len(client)) + client + b"\x12" + _varint(len(payload)) + payload


def _read_varint(buf, pos):
    value = 0
    shift = 0
    while True:
        assert pos < len(buf), "Truncated protobuf response"
        byte = buf[pos]
        pos += 1
        value |= (byte & 0x7f) << shift
        if not byte & 0x80:
            return value, pos
        shift += 7
        assert shift < 70, "Invalid protobuf varint"


def _response_result(buf):
    pos = 0
    result = None
    while pos < len(buf):
        tag, pos = _read_varint(buf, pos)
        wire = tag & 7
        field = tag >> 3
        if wire == 2:
            length, pos = _read_varint(buf, pos)
            value = buf[pos:pos + length]
            assert len(value) == length, "Truncated protobuf field"
            pos += length
            if field == 1:
                result = value.decode("utf-8")
        elif wire == 0:
            _, pos = _read_varint(buf, pos)
        elif wire == 1:
            pos += 8
        elif wire == 5:
            pos += 4
        else:
            pytest.fail(f"Unsupported protobuf wire type {wire}")
    assert result is not None, "ProcessResponse did not contain its result field"
    return result


def _rpc():
    channel = grpc.insecure_channel("127.0.0.1:50051")
    grpc.channel_ready_future(channel).result(timeout=5)
    call = channel.unary_unary(
        "/metadata.MetadataService/Process",
        request_serializer=lambda value: value,
        response_deserializer=lambda value: value,
    )
    return channel, call


def test_grpc_process_rpc_handles_large_input():
    channel, call = _rpc()
    try:
        client = "large-" + uuid.uuid4().hex
        data = "L" * 1000
        response = call(_request(client, data), timeout=5)
        assert _response_result(response) == "Processed: " + data
    finally:
        channel.close()


def test_grpc_rate_limit_is_three_requests_per_second_per_client():
    channel, call = _rpc()
    try:
        client = "limited-" + uuid.uuid4().hex
        for index in range(3):
            data = f"request-{index}"
            response = call(_request(client, data), timeout=5)
            assert _response_result(response) == "Processed: " + data

        with pytest.raises(grpc.RpcError) as exc_info:
            call(_request(client, "request-4"), timeout=5)
        assert exc_info.value.code() == grpc.StatusCode.RESOURCE_EXHAUSTED
        assert exc_info.value.details() == "Rate limit exceeded"

        other_client = "other-" + uuid.uuid4().hex
        response = call(_request(other_client, "independent"), timeout=5)
        assert _response_result(response) == "Processed: independent"

        time.sleep(1.15)
        response = call(_request(client, "after-window"), timeout=5)
        assert _response_result(response) == "Processed: after-window"
    finally:
        channel.close()
TEST_EOF

prep_ok=1

# Remove any listener left by the agent so the tested service must be launched by start.sh.
python3 <<'PY' || prep_ok=0
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == 50051:
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

for entry in os.listdir("/proc"):
    if not entry.isdigit():
        continue
    fd_dir = f"/proc/{entry}/fd"
    try:
        fds = os.listdir(fd_dir)
    except OSError:
        continue
    for fd in fds:
        try:
            target = os.readlink(os.path.join(fd_dir, fd))
        except OSError:
            continue
        if target.startswith("socket:[") and target[8:-1] in inodes:
            try:
                os.kill(int(entry), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
            break
time.sleep(0.5)
PY

rm -f /home/user/project/server.pid \
      /home/user/project/build/libprocessor.so \
      /home/user/project/python/metadata_pb2.py \
      /home/user/project/python/metadata_pb2_grpc.py

(cd /home/user/project && timeout 45s make all) >/tmp/verifier_make.log 2>&1 || prep_ok=0
(cd /home/user/project && timeout 45s ./start.sh) >/tmp/verifier_start.log 2>&1 || prep_ok=0
sleep 2

if [ "$prep_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
