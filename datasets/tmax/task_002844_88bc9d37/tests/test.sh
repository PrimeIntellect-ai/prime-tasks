#!/bin/bash
set -e
mkdir -p /logs/verifier
trap 'echo "0" > /logs/verifier/reward.txt' EXIT

PROJECT_DIR=/home/user/project
VENV=/tmp/verifier-venv
WHEELS=/tmp/verifier-wheels
GENERATED=/tmp/verifier-generated
rm -rf "$VENV" "$WHEELS" "$GENERATED"
mkdir -p "$WHEELS" "$GENERATED"

# Compile the submitted Rust source from a clean target and install that exact
# build into an isolated verifier environment.
cargo clean --manifest-path "$PROJECT_DIR/rust_ext/Cargo.toml"
timeout 300s maturin build --release \
    --manifest-path "$PROJECT_DIR/rust_ext/Cargo.toml" \
    --out "$WHEELS"
python3 -m venv --system-site-packages "$VENV"
WHEEL=$(find "$WHEELS" -maxdepth 1 -type f -name '*.whl' | head -n 1)
test -n "$WHEEL"
"$VENV/bin/python" -m pip install --no-deps --force-reinstall "$WHEEL"
SITE=$($VENV/bin/python -c 'import site; print(site.getsitepackages()[0])')

# Independently compile the submitted schema so malformed proto source cannot
# be hidden behind fabricated generated files.
"$VENV/bin/python" -m grpc_tools.protoc \
    -I"$PROJECT_DIR/proto" \
    --python_out="$GENERATED" \
    --grpc_python_out="$GENERATED" \
    "$PROJECT_DIR/proto/service.proto"

cat << 'RUNTIME_EOF' > /tmp/test_runtime.py
import importlib.machinery
import random
from concurrent import futures

import grpc
from google.protobuf.message import Message
import service_pb2
import service_pb2_grpc
import server as submitted_server
import string_processor

# The imported implementation must be the freshly built native extension, not
# a Python stand-in placed in the project.
module_path = getattr(string_processor, "__file__", "")
assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), module_path

for text, multiplier in [
    ("", 1),
    ("abc", 3),
    ("hé🙂", 2),
    ("a\x00b", 4),
]:
    assert string_processor.process_string(text, multiplier) == text * multiplier

# Execute the checked-in generated protobuf and gRPC modules and validate their
# descriptor rather than trusting their filenames.
assert issubclass(service_pb2.ProcessRequest, Message)
assert issubclass(service_pb2.ProcessResponse, Message)
field = service_pb2.ProcessRequest.DESCRIPTOR.fields_by_name.get("multiplier")
assert field is not None
assert field.number == 2
assert field.type == field.TYPE_INT32
assert service_pb2.ProcessRequest.DESCRIPTOR.fields_by_name["input_text"].number == 1

# Start a real local gRPC server using the submitted servicer and exercise it
# through the submitted generated client code.
grpc_server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
service_pb2_grpc.add_ProcessorServiceServicer_to_server(
    submitted_server.ProcessorServicer(), grpc_server
)
port = grpc_server.add_insecure_port("127.0.0.1:0")
assert port > 0
grpc_server.start()
try:
    with grpc.insecure_channel(f"127.0.0.1:{port}") as channel:
        grpc.channel_ready_future(channel).result(timeout=10)
        stub = service_pb2_grpc.ProcessorServiceStub(channel)
        cases = [("", 1), ("hello", 1), ("xy", 7), ("é🙂", 3), ("zero", 0)]
        rng = random.Random(817263)
        alphabet = "ab Zé🙂"
        for _ in range(20):
            text = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 20)))
            cases.append((text, rng.randrange(1, 11)))
        for text, multiplier in cases:
            response = stub.Process(
                service_pb2.ProcessRequest(input_text=text, multiplier=multiplier),
                timeout=10,
            )
            effective = multiplier if multiplier != 0 else 1
            expected = text * effective
            assert response.output_text == expected
            assert len(response.output_text) == len(text) * effective
finally:
    grpc_server.stop(0).wait()
RUNTIME_EOF

env PYTHONPATH="$SITE:$PROJECT_DIR" timeout 120s "$VENV/bin/python" /tmp/test_runtime.py

# Run the submitted property-based test itself from a neutral directory and
# regenerate the required results log from this real execution.
test -f "$PROJECT_DIR/test_server.py"
cp "$PROJECT_DIR/test_server.py" /tmp/submitted_test_server.py
env PYTHONPATH="$SITE:$PROJECT_DIR" timeout 180s "$VENV/bin/python" -m pytest \
    /tmp/submitted_test_server.py -v > /home/user/test_results.log 2>&1
grep -Eq '[1-9][0-9]* passed' /home/user/test_results.log

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

PROJECT_DIR = "/home/user/project"

def test_rust_extension_fixed():
    lib_rs_path = os.path.join(PROJECT_DIR, "rust_ext", "src", "lib.rs")
    assert os.path.isfile(lib_rs_path), f"File {lib_rs_path} is missing."

    with open(lib_rs_path, "r") as f:
        content = f.read()

    assert "-> String" in content, "The Rust extension was not fixed to return `String` instead of `&str`."
    assert "-> &str" not in content, "The Rust extension still returns `&str`, which causes a lifetime error."

def test_protobuf_schema_updated():
    proto_path = os.path.join(PROJECT_DIR, "proto", "service.proto")
    assert os.path.isfile(proto_path), f"File {proto_path} is missing."

    with open(proto_path, "r") as f:
        content = f.read()

    # Look for the multiplier field in ProcessRequest
    assert re.search(r"int32\s+multiplier\s*=\s*2\s*;", content), "The `multiplier` field was not added correctly to `service.proto`."

def test_grpc_files_generated():
    pb2_path = os.path.join(PROJECT_DIR, "service_pb2.py")
    pb2_grpc_path = os.path.join(PROJECT_DIR, "service_pb2_grpc.py")

    assert os.path.isfile(pb2_path), f"Generated gRPC file {pb2_path} is missing."
    assert os.path.isfile(pb2_grpc_path), f"Generated gRPC file {pb2_grpc_path} is missing."

def test_server_updated():
    server_path = os.path.join(PROJECT_DIR, "server.py")
    assert os.path.isfile(server_path), f"File {server_path} is missing."

    with open(server_path, "r") as f:
        content = f.read()

    assert "request.multiplier" in content, "The server does not appear to read `multiplier` from the request."
    # The multiplier should default to 1 if 0
    assert "1" in content and ("if" in content or "or" in content or "max" in content), "The server logic does not seem to handle the default multiplier correctly."

def test_test_server_created_and_valid():
    test_server_path = os.path.join(PROJECT_DIR, "test_server.py")
    assert os.path.isfile(test_server_path), f"Test file {test_server_path} is missing."

    with open(test_server_path, "r") as f:
        content = f.read()

    assert "@given" in content, "The property-based test does not use the `@given` decorator."
    assert "st.text" in content, "The property-based test does not generate random strings using `st.text`."
    assert "st.integers" in content, "The property-based test does not generate random integers using `st.integers`."
    assert "len(" in content, "The property-based test does not assert the length of the returned string."

def test_test_results_log():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"Test results log {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().lower()

    assert "passed" in content, "The test results log does not indicate that tests passed."
    assert "failed" not in content or "0 failed" in content, "The test results log indicates that some tests failed."
TEST_EOF

env PYTHONPATH="$SITE:$PROJECT_DIR" "$VENV/bin/python" -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

echo "1" > /logs/verifier/reward.txt
trap - EXIT
