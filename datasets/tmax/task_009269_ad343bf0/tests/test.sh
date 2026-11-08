#!/bin/bash
set +e
mkdir -p /logs/verifier

PROJECT=/home/user/project
SO="$PROJECT/rust_lib/target/release/libprocessor.so"
SERVER_PID=""
PROBE_PID=""
BACKUP_SO="/tmp/libprocessor.original.$$"
MARKER="/tmp/process_buffer_called.$$"

cleanup() {
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi
    if [ -n "$PROBE_PID" ]; then kill "$PROBE_PID" 2>/dev/null || true; fi
    pkill -f '[p]ython3.*server.py' 2>/dev/null || true
    if [ -f "$BACKUP_SO" ]; then cp -f "$BACKUP_SO" "$SO" 2>/dev/null || true; fi
    rm -f "$BACKUP_SO" "$MARKER" /tmp/libprocessor_probe.so /tmp/process_probe.c
}
trap cleanup EXIT

# Do not allow a server left running by the agent to satisfy the tests.
pkill -f '[p]ython3.*server.py' 2>/dev/null || true
rm -f "$PROJECT/output.log"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import random
import subprocess
import sys
import time

import grpc

PROJECT = "/home/user/project"
SO_PATH = PROJECT + "/rust_lib/target/release/libprocessor.so"
sys.path.insert(0, PROJECT)


def test_rust_library_compiled():
    assert os.path.isfile(SO_PATH), f"Compiled Rust library {SO_PATH} is missing."
    lib = ctypes.CDLL(SO_PATH)
    fn = lib.process_buffer
    fn.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
                   ctypes.POINTER(ctypes.c_uint8)]
    fn.restype = None

    rng = random.Random(937451)
    for length in [0, 1, 2, 17, 63, 257]:
        payload = bytes(rng.randrange(256) for _ in range(length))
        size = max(1, length)
        input_buf = (ctypes.c_uint8 * size)()
        output_buf = (ctypes.c_uint8 * size)()
        if payload:
            ctypes.memmove(input_buf, payload, length)
        fn(input_buf, length, output_buf)
        actual = bytes(output_buf[:length])
        expected = bytes((b + 5) & 0xff for b in payload)
        assert actual == expected


def test_grpc_bindings_generated():
    pb2_path = PROJECT + "/compute_pb2.py"
    pb2_grpc_path = PROJECT + "/compute_pb2_grpc.py"
    assert os.path.isfile(pb2_path), f"Generated protobuf file {pb2_path} is missing."
    assert os.path.isfile(pb2_grpc_path), f"Generated gRPC file {pb2_grpc_path} is missing."
    __import__("compute_pb2")
    __import__("compute_pb2_grpc")


def test_python_scripts_exist_and_configure_ctypes():
    server_path = PROJECT + "/server.py"
    client_path = PROJECT + "/client.py"
    assert os.path.isfile(server_path), f"Server script {server_path} is missing."
    assert os.path.isfile(client_path), f"Client script {client_path} is missing."

    with open(server_path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), server_path)
    assigned_attrs = {
        target.attr
        for node in ast.walk(tree)
        if isinstance(node, (ast.Assign, ast.AnnAssign))
        for target in ((node.targets if isinstance(node, ast.Assign) else [node.target]))
        if isinstance(target, ast.Attribute)
    }
    assert "argtypes" in assigned_attrs, "server.py does not set process_buffer.argtypes"
    assert "restype" in assigned_attrs, "server.py does not set process_buffer.restype"


def wait_for_server():
    channel = grpc.insecure_channel("localhost:50051")
    grpc.channel_ready_future(channel).result(timeout=12)
    return channel


def test_grpc_server_on_derived_inputs():
    import compute_pb2
    import compute_pb2_grpc

    channel = wait_for_server()
    try:
        stub = compute_pb2_grpc.ComputeServiceStub(channel)
        rng = random.Random(182736)
        payloads = [b"", b"\x00\xfb\xfc\xfd\xfe\xff"]
        payloads += [bytes(rng.randrange(256) for _ in range(n)) for n in (1, 7, 31, 128)]
        for payload in payloads:
            response = stub.ProcessData(
                compute_pb2.ProcessRequest(payload=payload), timeout=5
            )
            expected = bytes((b + 5) & 0xff for b in payload)
            assert response.result == expected
    finally:
        channel.close()


def test_client_is_executed():
    log_path = PROJECT + "/output.log"
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass
    completed = subprocess.run(
        [sys.executable, PROJECT + "/client.py"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, completed.stderr
    assert os.path.isfile(log_path), "client.py did not create output.log"


def test_output_log_content():
    log_path = PROJECT + "/output.log"
    assert os.path.isfile(log_path), f"Output log file {log_path} is missing."

    input_bytes = b"SYSTEMS_PROGRAMMING"
    expected_bytes = bytes((b + 5) & 0xFF for b in input_bytes)
    expected_hex = expected_bytes.hex()

    with open(log_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content.lower() == expected_hex.lower(), (
        f"Content of {log_path} is incorrect. "
        f"Expected '{expected_hex}', but got '{actual_content}'."
    )
TEST_EOF

cd "$PROJECT" || STATUS=1
python3 "$PROJECT/server.py" >/tmp/submitted_server.log 2>&1 &
SERVER_PID=$!
python3 -m pytest /tmp/test_final_state.py -x --tb=short
STATUS=$?
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""
pkill -f '[p]ython3.*server.py' 2>/dev/null || true

# Replace the expected library temporarily with an ABI-compatible probe. The
# probe preserves the required behavior but leaves evidence that the submitted
# server actually invoked process_buffer through the shared library.
if [ "$STATUS" -eq 0 ]; then
    cp "$SO" "$BACKUP_SO" || STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
    cat > /tmp/process_probe.c <<PROBE_EOF
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

void process_buffer(const uint8_t *input, size_t len, uint8_t *output) {
    FILE *f = fopen("$MARKER", "ab");
    if (f) { fputc('1', f); fclose(f); }
    if (!input || !output) return;
    for (size_t i = 0; i < len; ++i) output[i] = (uint8_t)(input[i] + 5u);
}
PROBE_EOF
    cc -shared -fPIC -O2 /tmp/process_probe.c -o /tmp/libprocessor_probe.so || STATUS=1
    cp /tmp/libprocessor_probe.so "$SO" || STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
    rm -f "$MARKER"
    cd "$PROJECT"
    python3 "$PROJECT/server.py" >/tmp/probe_server.log 2>&1 &
    PROBE_PID=$!

    MARKER_PATH="$MARKER" python3 - <<'PY_EOF'
import os
import random
import sys
import time

import grpc

sys.path.insert(0, "/home/user/project")
import compute_pb2
import compute_pb2_grpc

channel = grpc.insecure_channel("localhost:50051")
grpc.channel_ready_future(channel).result(timeout=12)
rng = random.Random(774411)
payload = bytes(rng.randrange(256) for _ in range(79))
response = compute_pb2_grpc.ComputeServiceStub(channel).ProcessData(
    compute_pb2.ProcessRequest(payload=payload), timeout=5
)
assert response.result == bytes((b + 5) & 0xff for b in payload)
channel.close()
assert os.path.isfile(os.environ["MARKER_PATH"]), (
    "server returned an answer without invoking process_buffer from libprocessor.so"
)
PY_EOF
    [ $? -eq 0 ] || STATUS=1
fi

if [ -n "$PROBE_PID" ]; then
    kill "$PROBE_PID" 2>/dev/null || true
    wait "$PROBE_PID" 2>/dev/null || true
    PROBE_PID=""
fi
if [ -f "$BACKUP_SO" ]; then
    cp -f "$BACKUP_SO" "$SO" || STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
