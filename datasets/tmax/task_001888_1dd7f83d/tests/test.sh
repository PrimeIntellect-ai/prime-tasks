#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest


def test_rate_limit_extracted():
    txt_path = "/app/rate_limit.txt"
    assert os.path.isfile(txt_path), f"Expected file not found: {txt_path}"
    with open(txt_path, "r") as f:
        content = f.read().strip()
    assert content == "5", f"Expected rate limit to be '5', but got '{content}'"


def test_server_compiled():
    server_binary = "/app/workspace/server"
    assert os.path.isfile(server_binary), "Server binary not found. The project did not compile successfully."
    assert os.access(server_binary, os.X_OK), "Server binary is not executable."


def test_server_listening():
    # Check if port 50051 is listening
    port_open = False
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1.0)
        result = s.connect_ex(('127.0.0.1', 50051))
        if result == 0:
            port_open = True
    assert port_open, "Expected server to be listening on port 50051, but it is not."


def test_extern_c_added():
    header_path = "/app/workspace/numalgo.h"
    assert os.path.isfile(header_path), f"Expected header file not found: {header_path}"
    with open(header_path, "r") as f:
        content = f.read()
    assert 'extern "C"' in content, "Expected 'extern \"C\"' block to be added to numalgo.h to fix the linking issue."


def _listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9:
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
                if local_port == port and fields[3] == "0A":
                    inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) in (1, os.getpid()):
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def _stop_existing_listener(port):
    pids = _listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(Path(f"/proc/{pid}").exists() for pid in pids):
        time.sleep(0.05)
    for pid in pids:
        if Path(f"/proc/{pid}").exists():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def _build_grpc_client():
    work = Path("/tmp/verifier_grpc_client")
    subprocess.run(["rm", "-rf", str(work)], check=True)
    work.mkdir()
    (work / "matrix.proto").write_text(r'''syntax = "proto3";
package matrix;
service MatrixService {
  rpc CalculateDeterminant (MatrixRequest) returns (MatrixResponse) {}
}
message MatrixRequest {
  repeated float data = 1;
  int32 size = 2;
}
message MatrixResponse { float determinant = 1; }
''')
    subprocess.run([
        "protoc", "-I", str(work), f"--cpp_out={work}",
        f"--grpc_out={work}",
        "--plugin=protoc-gen-grpc=/usr/bin/grpc_cpp_plugin",
        str(work / "matrix.proto")
    ], check=True)

    (work / "client.cc").write_text(r'''
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <random>
#include <vector>
#include <grpcpp/grpcpp.h>
#include "matrix.grpc.pb.h"

static double expected_det(const std::vector<float>& a, int n) {
    if (n == 1) return a[0];
    if (n == 2) return double(a[0]) * a[3] - double(a[1]) * a[2];
    return double(a[0]) * (double(a[4]) * a[8] - double(a[5]) * a[7])
         - double(a[1]) * (double(a[3]) * a[8] - double(a[5]) * a[6])
         + double(a[2]) * (double(a[3]) * a[7] - double(a[4]) * a[6]);
}

int main(int argc, char** argv) {
    if (argc != 2) return 20;
    std::mt19937 rng(static_cast<unsigned>(std::strtoul(argv[1], nullptr, 10)));
    std::uniform_int_distribution<int> values(-7, 7);
    auto channel = grpc::CreateChannel("127.0.0.1:50051", grpc::InsecureChannelCredentials());
    auto stub = matrix::MatrixService::NewStub(channel);
    const int sizes[5] = {1, 2, 3, 2, 3};

    for (int call = 0; call < 5; ++call) {
        int n = sizes[call];
        std::vector<float> data;
        matrix::MatrixRequest request;
        request.set_size(n);
        for (int i = 0; i < n * n; ++i) {
            float value = static_cast<float>(values(rng));
            data.push_back(value);
            request.add_data(value);
        }
        matrix::MatrixResponse response;
        grpc::ClientContext context;
        grpc::Status status = stub->CalculateDeterminant(&context, request, &response);
        if (!status.ok()) {
            std::cerr << "Request " << call + 1 << " unexpectedly failed with status "
                      << status.error_code() << ": " << status.error_message() << std::endl;
            return 30 + call;
        }
        double expected = expected_det(data, n);
        if (std::fabs(double(response.determinant()) - expected) > 0.01) {
            std::cerr << "Wrong determinant on request " << call + 1
                      << ": expected " << expected << ", got "
                      << response.determinant() << std::endl;
            return 40 + call;
        }
    }

    matrix::MatrixRequest request;
    request.set_size(1);
    request.add_data(11.0f);
    matrix::MatrixResponse response;
    grpc::ClientContext context;
    grpc::Status status = stub->CalculateDeterminant(&context, request, &response);
    if (status.ok() || status.error_code() != grpc::StatusCode::RESOURCE_EXHAUSTED) {
        std::cerr << "Sixth request was not rejected with RESOURCE_EXHAUSTED; status="
                  << status.error_code() << std::endl;
        return 60;
    }
    return 0;
}
''')

    flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "protobuf", "grpc++"], text=True
    ))
    command = [
        "g++", "-std=c++14", str(work / "client.cc"),
        str(work / "matrix.pb.cc"), str(work / "matrix.grpc.pb.cc"),
        "-o", str(work / "client"), "-pthread"
    ] + flags
    subprocess.run(command, check=True, cwd=work)
    return work / "client"


def test_actual_server_grpc_determinants_and_rate_limit():
    client = _build_grpc_client()
    _stop_existing_listener(50051)

    server = subprocess.Popen(
        ["/app/workspace/server"],
        cwd="/app/workspace",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 10
    listening = False
    while time.time() < deadline:
        assert server.poll() is None, "The submitted server executable exited during startup."
        try:
            with socket.create_connection(("127.0.0.1", 50051), timeout=0.2):
                listening = True
                break
        except OSError:
            time.sleep(0.1)
    assert listening, "Executing /app/workspace/server did not open port 50051."

    seed = secrets.randbits(32)
    result = subprocess.run(
        [str(client), str(seed)], text=True, capture_output=True, timeout=15
    )
    assert result.returncode == 0, (
        "The submitted server failed live gRPC determinant/rate-limit tests:\n"
        + result.stdout + result.stderr
    )
    assert server.poll() is None, "The submitted server stopped after handling gRPC requests."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
