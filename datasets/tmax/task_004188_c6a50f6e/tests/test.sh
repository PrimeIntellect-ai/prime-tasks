#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import os
import re
import socket
import subprocess
import sys
import tempfile

import pytest

PROJECT = "/home/user/broken_pr"
PROTO = os.path.join(PROJECT, "service.proto")
LEGACY = "/app/legacy_filter"


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def temporarily_hide_legacy():
    if not os.path.exists(LEGACY):
        return None
    hidden = f"{LEGACY}.hidden-by-verifier-{os.getpid()}"
    os.rename(LEGACY, hidden)
    return hidden


def restore_legacy(hidden):
    if hidden is not None:
        os.rename(hidden, LEGACY)


def test_grpc_server_listening():
    """Verify that the required server is listening on the specified address."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.settimeout(2)
        assert sock.connect_ex(("127.0.0.1", 50051)) == 0, (
            "gRPC server is not listening on 127.0.0.1:50051"
        )
    finally:
        sock.close()


def test_setup_builds_and_filter_is_native():
    setup_py = os.path.join(PROJECT, "setup.py")
    source_path = os.path.join(PROJECT, "filter_core.c")
    assert os.path.isfile(setup_py), "setup.py is missing"
    assert os.path.isfile(source_path), "filter_core.c is missing"

    source = open(source_path, "r", encoding="utf-8", errors="replace").read()
    forbidden_calls = re.compile(
        r"\b(?:popen|system|fork|vfork|execl|execle|execlp|execv|execve|execvp|"
        r"posix_spawn|dlopen|PyRun_[A-Za-z0-9_]*|PyImport_ImportModule)\s*\("
    )
    assert not forbidden_calls.search(source), (
        "filter_core.c appears to invoke an external process or dynamically execute "
        "another implementation instead of implementing the transformation natively"
    )

    install = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--no-deps", "--force-reinstall", "."],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert install.returncode == 0, (
        f"pip install . failed\nstdout:\n{install.stdout}\nstderr:\n{install.stderr}"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        build_lib = os.path.join(tmpdir, "lib")
        build_temp = os.path.join(tmpdir, "build")
        build = subprocess.run(
            [
                sys.executable,
                "setup.py",
                "build_ext",
                "--force",
                f"--build-lib={build_lib}",
                f"--build-temp={build_temp}",
            ],
            cwd=PROJECT,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert build.returncode == 0, (
            f"setup.py could not compile the extension\nstdout:\n{build.stdout}\n"
            f"stderr:\n{build.stderr}"
        )

        artifacts = []
        for suffix in importlib.machinery.EXTENSION_SUFFIXES:
            artifacts.extend(glob.glob(os.path.join(build_lib, "**", "filter_core" + suffix), recursive=True))
        assert artifacts, "The build did not produce a filter_core native extension"

        checker = os.path.join(tmpdir, "check_native.py")
        with open(checker, "w", encoding="utf-8") as handle:
            handle.write(r'''
import importlib.machinery
import inspect
import os

import filter_core

module_path = os.path.realpath(filter_core.__file__)
build_lib = os.path.realpath(os.environ["EXPECTED_BUILD_LIB"])
assert os.path.commonpath([module_path, build_lib]) == build_lib
assert any(module_path.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)
assert inspect.isbuiltin(filter_core.process), "filter_core.process is not a C-extension function"

vectors = [
    b"",
    bytes(range(256)),
    bytes(range(255, -1, -1)),
    b"\x00" * 1024,
    b"\xff" * 1024,
]
for length in (1, 2, 3, 7, 31, 127, 257, 1023, 4097, 8192):
    vectors.append(os.urandom(length))

for value in vectors:
    expected = bytes((~(byte ^ 0x5A)) & 0xFF for byte in value)
    actual = filter_core.process(value)
    assert type(actual) is bytes
    assert actual == expected, (value.hex(), expected.hex(), actual.hex())
''')

        env = os.environ.copy()
        env["PYTHONPATH"] = build_lib
        env["EXPECTED_BUILD_LIB"] = build_lib
        hidden = temporarily_hide_legacy()
        try:
            result = subprocess.run(
                [sys.executable, checker],
                cwd=tmpdir,
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
            )
        finally:
            restore_legacy(hidden)
        assert result.returncode == 0, (
            "The freshly built native extension failed behavioral checks while the "
            f"legacy executable was unavailable\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def test_grpc_process_data_from_declared_proto():
    """Compile the submitted proto and exercise unpredictable binary requests."""
    assert os.path.isfile(PROTO), f"Proto file not found at {PROTO}"

    inputs = [
        b"",
        bytes(range(256)),
        bytes(range(255, -1, -1)),
        b"\x00\xff\x5a\xa5\x0f\xf0",
    ]
    inputs.extend(os.urandom(length) for length in (1, 13, 97, 511, 2048, 8191))

    with tempfile.TemporaryDirectory() as tmpdir:
        compile_result = subprocess.run(
            [
                sys.executable,
                "-m",
                "grpc_tools.protoc",
                f"-I{os.path.dirname(PROTO)}",
                f"--python_out={tmpdir}",
                f"--grpc_python_out={tmpdir}",
                PROTO,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"Failed to compile service.proto\nstdout:\n{compile_result.stdout}\n"
            f"stderr:\n{compile_result.stderr}"
        )

        client = os.path.join(tmpdir, "test_client.py")
        with open(client, "w", encoding="utf-8") as handle:
            handle.write(r'''
import sys
import grpc
import service_pb2
import service_pb2_grpc

channel = grpc.insecure_channel("127.0.0.1:50051")
grpc.channel_ready_future(channel).result(timeout=3)
stub = service_pb2_grpc.FilterServiceStub(channel)
request = service_pb2.DataRequest(data=sys.stdin.buffer.read())
response = stub.ProcessData(request, timeout=3)
sys.stdout.buffer.write(response.data)
''')

        env = os.environ.copy()
        env["PYTHONPATH"] = tmpdir
        hidden = temporarily_hide_legacy()
        try:
            for input_data in inputs:
                expected = bytes((~(byte ^ 0x5A)) & 0xFF for byte in input_data)
                try:
                    result = subprocess.run(
                        [sys.executable, client],
                        input=input_data,
                        capture_output=True,
                        env=env,
                        timeout=8,
                    )
                except subprocess.TimeoutExpired:
                    pytest.fail("gRPC client request timed out")
                assert result.returncode == 0, (
                    "gRPC client request failed: "
                    + result.stderr.decode("utf-8", errors="replace")
                )
                assert result.stdout == expected, (
                    f"Expected {expected.hex()}, got {result.stdout.hex()} for "
                    f"input {input_data.hex()}"
                )
        finally:
            restore_legacy(hidden)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
