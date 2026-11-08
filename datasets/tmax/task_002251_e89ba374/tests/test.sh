#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import subprocess
import uuid

WAF_DIR = "/home/user/waf"
VENV_PYTHON = "/home/user/waf/venv/bin/python"


def run_venv(args, **kwargs):
    return subprocess.run(
        [VENV_PYTHON] + args,
        cwd=WAF_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        **kwargs,
    )


def test_venv_exists():
    venv_python = "/home/user/waf/venv/bin/python"
    assert os.path.isfile(venv_python), f"Virtual environment Python executable not found at {venv_python}. Did you create the venv?"


def test_required_packages_installed_in_venv():
    proc = run_venv([
        "-c",
        "import grpc, grpc_tools; "
        "from importlib.metadata import version; "
        "assert version('grpcio'); assert version('grpcio-tools')",
    ])
    assert proc.returncode == 0, f"Required gRPC packages are not usable in the virtual environment:\n{proc.stderr}"


def test_protobuf_generated():
    pb2_file = "/home/user/waf/waf_pb2.py"
    pb2_grpc_file = "/home/user/waf/waf_pb2_grpc.py"

    assert os.path.isfile(pb2_file), f"Protobuf generated file {pb2_file} not found."
    assert os.path.isfile(pb2_grpc_file), f"gRPC generated file {pb2_grpc_file} not found."

    proc = run_venv([
        "-c",
        "import waf_pb2, waf_pb2_grpc; "
        "assert waf_pb2.DESCRIPTOR.services_by_name['WafService'].methods_by_name['Inspect']; "
        "assert waf_pb2.InspectRequest(payload='x').payload == 'x'; "
        "assert hasattr(waf_pb2_grpc, 'WafServiceStub'); "
        "assert hasattr(waf_pb2_grpc, 'WafServiceServicer'); "
        "assert callable(waf_pb2_grpc.add_WafServiceServicer_to_server)",
    ])
    assert proc.returncode == 0, f"Generated protobuf/gRPC bindings cannot be imported or do not describe waf.proto:\n{proc.stderr}"


def test_server_py_fixed():
    server_file = "/home/user/waf/server.py"
    assert os.path.isfile(server_file), f"File {server_file} is missing."

    with open(server_file, "r") as f:
        content = f.read()

    # Check that Python 2 print is removed or replaced with Python 3 print
    assert 'print "Server started"' not in content, "The Python 2 print statement is still in server.py."
    assert re.search(r'print\s*\(\s*(["\'])Server started\1\s*\)', content), "Could not find a valid Python 3 print('Server started') in server.py."

    # Check that the string is encoded before passing to C library
    assert ".encode(" in content or "bytes(" in content, "Did not find string encoding (.encode or bytes()) before passing to the C library in server.py."
    assert "lib.check_payload(request.payload)" not in content, "The buggy lib.check_payload(request.payload) is still in server.py. It must be encoded to bytes."

    proc = run_venv(["-m", "py_compile", server_file])
    assert proc.returncode == 0, f"server.py is not valid Python 3:\n{proc.stderr}"


def test_migration_result():
    result_file = "/home/user/waf/migration_result.txt"
    assert os.path.isfile(result_file), f"The output file {result_file} was not created."

    with open(result_file, "r") as f:
        content = f.read().strip()

    expected = "Clean: False, Malicious: True"
    assert expected in content, f"Expected '{expected}' in {result_file}, but got:\n{content}"


def test_server_is_running_and_behaves_like_matcher():
    # Confirm that the requested server.py artifact is represented by a live process.
    server_processes = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if any(arg == "server.py" or os.path.abspath(arg) == "/home/user/waf/server.py" for arg in argv):
            server_processes.append((name, argv))
    assert server_processes, "No running /home/user/waf/server.py process was found."

    # Derive expected answers directly from the supplied C library for fresh inputs.
    matcher = ctypes.CDLL("/home/user/waf/libmatcher.so")
    matcher.check_payload.argtypes = [ctypes.c_char_p]
    matcher.check_payload.restype = ctypes.c_int
    token = uuid.uuid4().hex
    payloads = [
        f"clean-雪-{token}",
        f"prefix-{token}-<script>-suffix",
        f"prefix-UNION SELECT-{token}",
        f"lower-union select-{token}",
    ]
    expected = [bool(matcher.check_payload(value.encode("utf-8"))) for value in payloads]

    helper = r'''
import json
import sys
import grpc
import waf_pb2
import waf_pb2_grpc

data = json.load(sys.stdin)
channel = grpc.insecure_channel("localhost:50051")
grpc.channel_ready_future(channel).result(timeout=8)
stub = waf_pb2_grpc.WafServiceStub(channel)
actual = []
for payload in data["payloads"]:
    response = stub.Inspect(waf_pb2.InspectRequest(payload=payload), timeout=5)
    actual.append(response.is_malicious)
print(json.dumps(actual))
channel.close()
'''
    proc = run_venv(["-c", helper], input=json.dumps({"payloads": payloads}))
    assert proc.returncode == 0, f"Could not call the running gRPC WAF service with generated bindings:\n{proc.stderr}"
    try:
        actual = json.loads(proc.stdout.strip().splitlines()[-1])
    except Exception as exc:
        raise AssertionError(f"Invalid output from live gRPC check: {proc.stdout!r}") from exc
    assert actual == expected, f"Live gRPC results {actual!r} did not match libmatcher.so results {expected!r}."

    # Execute the provided client with the virtual environment as required.
    client = run_venv(["/home/user/waf/test_client.py"])
    assert client.returncode == 0, f"test_client.py failed against the running server:\n{client.stderr}"
    assert "Clean: False, Malicious: True" in client.stdout, f"Unexpected test_client.py output:\n{client.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
