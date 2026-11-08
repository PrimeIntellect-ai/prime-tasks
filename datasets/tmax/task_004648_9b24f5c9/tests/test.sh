#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib
import os
import random
import socket
import string
import subprocess
import sys
import tempfile
import uuid

import grpc
import pytest
import requests
from grpc_tools import protoc


def _random_key():
    alphabet = string.ascii_uppercase + string.digits
    return "AKIA" + "".join(random.SystemRandom().choice(alphabet) for _ in range(16))


def _post(filepath, raw_payload):
    payload = {
        "filepath": filepath,
        "encoded_payload": base64.b64encode(raw_payload.encode("utf-8")).decode("ascii"),
    }
    try:
        return requests.post("http://127.0.0.1:8080/scan", json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"HTTP request to /scan failed: {exc}")


def _grpc_modules():
    out_dir = tempfile.mkdtemp(prefix="scanner_proto_")
    result = protoc.main([
        "grpc_tools.protoc",
        "-I/home/user",
        f"--python_out={out_dir}",
        f"--grpc_python_out={out_dir}",
        "/home/user/scanner.proto",
    ])
    assert result == 0, "Failed to compile /home/user/scanner.proto"
    sys.path.insert(0, out_dir)
    sys.modules.pop("scanner_pb2", None)
    sys.modules.pop("scanner_pb2_grpc", None)
    return importlib.import_module("scanner_pb2"), importlib.import_module("scanner_pb2_grpc")


def test_secscanner_setup_fixed():
    setup_path = "/app/secscanner-1.0.4/setup.py"
    assert os.path.isfile(setup_path), f"File {setup_path} does not exist."
    with open(setup_path, "r") as f:
        content = f.read()
    assert "baddep==9.9.9" not in content, "The invalid dependency 'baddep==9.9.9' was not removed from setup.py."


def test_secscanner_redactor_fixed():
    redactor_path = "/app/secscanner-1.0.4/secscanner/redactor.py"
    assert os.path.isfile(redactor_path), f"File {redactor_path} does not exist."
    with open(redactor_path, "r") as f:
        content = f.read()
    assert "b32decode" not in content, "The base64 decoding still uses 'b32decode'."
    assert "b64decode" in content, "The base64 decoding was not changed to 'b64decode'."


def test_secscanner_installs_and_executes():
    install = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--force-reinstall", "/app/secscanner-1.0.4"],
        cwd="/tmp",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert install.returncode == 0, f"secscanner did not install successfully:\n{install.stdout}"

    key1, key2 = _random_key(), _random_key()
    raw = f"prefix-{uuid.uuid4().hex} {key1} middle {key2} suffix-{uuid.uuid4().hex}"
    encoded = base64.b64encode(raw.encode()).decode()
    code = (
        "from secscanner import redact_payload\n"
        f"result = redact_payload({encoded!r})\n"
        f"assert result == {raw.replace(key1, '[REDACTED]').replace(key2, '[REDACTED]')!r}, result\n"
    )
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    execution = subprocess.run(
        [sys.executable, "-c", code], cwd="/tmp", env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
    )
    assert execution.returncode == 0, f"Installed secscanner failed behavioral execution:\n{execution.stdout}"


def test_http_endpoint_world_readable_file():
    test_file = "/tmp/test_config_644.json"
    with open(test_file, "w") as f:
        f.write("dummy")
    os.chmod(test_file, 0o644)

    payload = {
        "filepath": test_file,
        "encoded_payload": base64.b64encode(b"secret AKIAABCDEFGHIJKLMNOP").decode("utf-8")
    }

    try:
        response = requests.post("http://127.0.0.1:8080/scan", json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP request to /scan failed: {e}")

    assert response.status_code == 403, f"Expected HTTP 403 for world-readable file, got {response.status_code}. Response: {response.text}"


def test_http_endpoint_strict_file():
    test_file = "/tmp/test_config_600.json"
    with open(test_file, "w") as f:
        f.write("dummy")
    os.chmod(test_file, 0o600)

    raw_payload = b"user_data: AKIA0123456789ABCDEF, other_data: test"
    payload = {
        "filepath": test_file,
        "encoded_payload": base64.b64encode(raw_payload).decode("utf-8")
    }

    try:
        response = requests.post("http://127.0.0.1:8080/scan", json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP request to /scan failed: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 for strict file, got {response.status_code}. Response: {response.text}"

    with open(test_file, "r") as f:
        written_content = f.read()

    assert "AKIA0123456789ABCDEF" not in written_content, "The sensitive API key was not redacted."
    assert "[REDACTED]" in written_content, "The redacted placeholder '[REDACTED]' was not found in the output."
    assert written_content == "user_data: [REDACTED], other_data: test", f"Unexpected file content: {written_content}"


def test_http_randomized_behavior():
    for _ in range(3):
        marker1, marker2 = uuid.uuid4().hex, uuid.uuid4().hex
        key1, key2 = _random_key(), _random_key()
        raw = f"{marker1}: {key1}; preserve=AKIAshort; second={key2}; {marker2}"
        expected = f"{marker1}: [REDACTED]; preserve=AKIAshort; second=[REDACTED]; {marker2}"
        path = f"/tmp/http_strict_{uuid.uuid4().hex}.txt"
        with open(path, "w") as f:
            f.write("original")
        os.chmod(path, 0o600)
        response = _post(path, raw)
        assert response.status_code == 200, response.text
        assert "Redaction complete" in response.text
        with open(path) as f:
            assert f.read() == expected

    for mode in (0o604, 0o644, 0o777):
        path = f"/tmp/http_public_{uuid.uuid4().hex}.txt"
        original = "unchanged-" + uuid.uuid4().hex
        with open(path, "w") as f:
            f.write(original)
        os.chmod(path, mode)
        response = _post(path, f"secret {_random_key()} {uuid.uuid4().hex}")
        assert response.status_code == 403, f"Mode {oct(mode)} returned {response.status_code}: {response.text}"
        with open(path) as f:
            assert f.read() == original, "World-readable file was modified"


def test_grpc_port_open():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect(("127.0.0.1", 50051))
        s.close()
    except Exception as e:
        pytest.fail(f"gRPC port 50051 is not open or reachable: {e}")


def test_grpc_scanner_behavior():
    scanner_pb2, scanner_pb2_grpc = _grpc_modules()
    channel = grpc.insecure_channel("127.0.0.1:50051")
    grpc.channel_ready_future(channel).result(timeout=5)
    stub = scanner_pb2_grpc.ScannerStub(channel)

    for _ in range(2):
        key = _random_key()
        marker = uuid.uuid4().hex
        raw = f"grpc-{marker} key={key} tail={uuid.uuid4().hex}"
        expected = raw.replace(key, "[REDACTED]")
        path = f"/tmp/grpc_strict_{uuid.uuid4().hex}.txt"
        with open(path, "w") as f:
            f.write("before")
        os.chmod(path, 0o600)
        request = scanner_pb2.ScanRequest(
            filepath=path,
            encoded_payload=base64.b64encode(raw.encode()).decode(),
        )
        response = stub.ScanPayload(request, timeout=5)
        assert response.message == "Redaction complete"
        with open(path) as f:
            assert f.read() == expected

    path = f"/tmp/grpc_public_{uuid.uuid4().hex}.txt"
    original = "do-not-change-" + uuid.uuid4().hex
    with open(path, "w") as f:
        f.write(original)
    os.chmod(path, 0o644)
    request = scanner_pb2.ScanRequest(
        filepath=path,
        encoded_payload=base64.b64encode(f"secret {_random_key()}".encode()).decode(),
    )
    with pytest.raises(grpc.RpcError) as caught:
        stub.ScanPayload(request, timeout=5)
    assert caught.value.code() == grpc.StatusCode.PERMISSION_DENIED
    with open(path) as f:
        assert f.read() == original, "gRPC modified a world-readable file"
    channel.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
