#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import subprocess
import time

import grpc

# Use the generated Python bindings already produced by the C++ project, if any;
# otherwise generate independent test bindings from the public protocol.
PROTO = "/home/user/encoder_service/encoder.proto"
GEN = "/tmp/encoder_py"
os.makedirs(GEN, exist_ok=True)
subprocess.run([
    "python3", "-m", "grpc_tools.protoc", "-I/home/user/encoder_service",
    f"--python_out={GEN}", f"--grpc_python_out={GEN}", PROTO
], check=True)
import sys
sys.path.insert(0, GEN)
import encoder_pb2
import encoder_pb2_grpc


def expected(text):
    if not text:
        rle = ""
    else:
        parts = []
        current = text[0]
        count = 1
        for ch in text[1:]:
            if ch == current:
                count += 1
            else:
                parts.append(current + str(count))
                current, count = ch, 1
        parts.append(current + str(count))
        rle = "".join(parts)
    return base64.b64encode(rle.encode("utf-8")).decode("ascii")


def test_build_artifact():
    project = "/home/user/encoder_service"
    proc = subprocess.run(["make", "-B"], cwd=project, capture_output=True, text=True, timeout=120)
    assert proc.returncode == 0, f"make failed:\n{proc.stdout}\n{proc.stderr}"
    binary = os.path.join(project, "encoder_server")
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "encoder_server was not built as an executable"


def test_benchmark_results_log():
    log_path = "/home/user/benchmark_results.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing. Did you save the benchmark output?"
    with open(log_path, "r") as f:
        content = f.read()
    match = re.search(r'Result:\s+(\d+)\s+RPS', content)
    assert match is not None, "Could not parse RPS from benchmark_results.log."
    assert int(match.group(1)) >= 10000, "Logged RPS is below 10000 RPS."


def test_server_correctness_on_varied_inputs():
    channel = grpc.insecure_channel("localhost:50051")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = encoder_pb2_grpc.EncoderServiceStub(channel)
    # Includes empty input, singletons, multi-digit runs, case changes,
    # punctuation, whitespace, digits, and non-ASCII UTF-8 text.
    cases = [
        "", "A", "AB", "aaaaaaaaaaaa", "AaAaAA", "111122233",
        "hello world!!!", "ZZZZZZZZZZZZZZZZZZZZxy", "a  b\\nccc",
        "éééßß", "AAAABBBCCDAA"
    ]
    for text in cases:
        response = stub.Encode(encoder_pb2.EncodeRequest(text=text), timeout=5)
        assert response.encoded_text == expected(text), (
            f"Incorrect encoding for {text!r}: expected {expected(text)!r}, "
            f"got {response.encoded_text!r}"
        )
    channel.close()


def test_server_running_and_performant():
    client_path = "/app/benchmark_client"
    assert os.path.isfile(client_path), f"Benchmark client {client_path} is missing."
    assert os.access(client_path, os.X_OK), f"Benchmark client {client_path} is not executable."
    proc = subprocess.run([client_path], capture_output=True, text=True, timeout=120)
    assert proc.returncode == 0, f"Benchmark client failed. Output: {proc.stdout}\nStderr: {proc.stderr}"
    match = re.search(r'Result:\s+(\d+)\s+RPS', proc.stdout)
    assert match is not None, "Could not parse RPS from live benchmark client output."
    assert int(match.group(1)) >= 10000, "Live RPS is below 10000 RPS."
TEST_EOF

# grpc_tools may not be installed, so generate bindings with system protoc and
# its Python gRPC plugin when available; install only the small Python runtime/tooling if needed.
if ! python3 -c 'import grpc, grpc_tools.protoc' >/dev/null 2>&1; then
    pip3 install -q grpcio grpcio-tools
fi

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
