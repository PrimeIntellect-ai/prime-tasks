#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import os
import signal
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import uuid

import pytest

PORTS = (8080, 50051)


def listening_inodes():
    found = {port: set() for port in PORTS}
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            try:
                port = int(fields[1].rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if port in found:
                found[port].add(fields[9])
    return found


def socket_owners(inodes):
    wanted = {inode for values in inodes.values() for inode in values}
    owners = set()
    if not wanted:
        return owners
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = os.path.join("/proc", name, "fd")
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in wanted:
                owners.add(int(name))
                break
    return owners


def process_is_running(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (OSError, IndexError):
        return False


def exercise_live_service(payload):
    url = "http://127.0.0.1:8080/process?" + urllib.parse.urlencode({"payload": payload})
    with urllib.request.urlopen(url, timeout=2) as response:
        assert response.status == 200
        body = response.read().decode("utf-8")
    expected = "Processed: " + payload
    assert body == expected, f"HTTP returned {body!r}, expected {expected!r}"

    modern = "/home/user/modern_app"
    if modern not in sys.path:
        sys.path.insert(0, modern)
    importlib.invalidate_caches()
    for module in ("schema_pb2_grpc", "schema_pb2"):
        sys.modules.pop(module, None)

    import grpc
    import schema_pb2
    import schema_pb2_grpc

    channel = grpc.insecure_channel("127.0.0.1:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=2)
        stub = schema_pb2_grpc.DataProcessorStub(channel)
        result = stub.ProcessData(schema_pb2.DataRequest(payload=payload), timeout=2)
        assert result.result == expected, (
            f"gRPC returned {result.result!r}, expected {expected!r}"
        )
    finally:
        channel.close()


@pytest.fixture(scope="session", autouse=True)
def run_upgrade_pipeline():
    script_path = "/home/user/upgrade_pipeline.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable. Did you run chmod +x?"

    before = listening_inodes()
    assert not before[8080] and not before[50051], (
        "Ports 8080 or 50051 were already listening before the pipeline ran."
    )

    payload = "verifier_" + uuid.uuid4().hex
    observed_pids = set()
    behavior_ok = False
    last_behavior_error = None

    with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
        proc = subprocess.Popen(
            ["bash", script_path],
            stdout=stdout_file,
            stderr=stderr_file,
            start_new_session=True,
        )
        deadline = time.time() + 300
        try:
            while time.time() < deadline:
                listeners = listening_inodes()
                if listeners[8080] and listeners[50051]:
                    observed_pids.update(socket_owners(listeners))
                    try:
                        exercise_live_service(payload)
                        behavior_ok = True
                        break
                    except Exception as exc:
                        last_behavior_error = exc
                if proc.poll() is not None:
                    break
                time.sleep(0.01)

            remaining = max(1, deadline - time.time())
            try:
                returncode = proc.wait(timeout=remaining)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
                pytest.fail("The upgrade pipeline did not exit within 300 seconds.")
        finally:
            if proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()

        stdout_file.seek(0)
        stderr_file.seek(0)
        stdout = stdout_file.read().decode("utf-8", errors="replace")
        stderr = stderr_file.read().decode("utf-8", errors="replace")

    assert returncode == 0, (
        f"The script {script_path} failed with return code {returncode}.\n"
        f"Stdout:\n{stdout}\nStderr:\n{stderr}"
    )
    assert behavior_ok, (
        "The pipeline never exposed working HTTP and gRPC services on ports 8080 and 50051. "
        f"Last error: {last_behavior_error!r}"
    )
    assert observed_pids, "Could not identify the process owning the service sockets."

    stop_deadline = time.time() + 5
    while time.time() < stop_deadline:
        listeners = listening_inodes()
        if (not listeners[8080] and not listeners[50051]
                and all(not process_is_running(pid) for pid in observed_pids)):
            break
        time.sleep(0.05)

    listeners = listening_inodes()
    assert not listeners[8080] and not listeners[50051], (
        "The pipeline exited without shutting down both service listeners."
    )
    assert all(not process_is_running(pid) for pid in observed_pids), (
        "The background service process was not killed before the pipeline exited."
    )


def test_modern_app_directory_created():
    assert os.path.isdir("/home/user/modern_app"), "The /home/user/modern_app directory was not created."


def test_schema_proto_upgraded_to_proto3():
    proto_path = "/home/user/modern_app/schema.proto"
    assert os.path.isfile(proto_path), f"The file {proto_path} is missing."

    with open(proto_path, "r") as f:
        content = f.read()

    assert 'syntax = "proto3";' in content, "schema.proto syntax declaration was not updated to 'proto3'."
    assert 'required ' not in content, "schema.proto still contains the 'required' field label, which is invalid in proto3."


def test_grpc_bindings_compiled():
    pb2_path = "/home/user/modern_app/schema_pb2.py"
    pb2_grpc_path = "/home/user/modern_app/schema_pb2_grpc.py"

    assert os.path.isfile(pb2_path), f"gRPC binding {pb2_path} was not generated."
    assert os.path.isfile(pb2_grpc_path), f"gRPC binding {pb2_grpc_path} was not generated."


def test_service_py_upgraded_to_python3():
    service_path = "/home/user/modern_app/service.py"
    assert os.path.isfile(service_path), f"The file {service_path} is missing."

    with open(service_path, "r") as f:
        content = f.read()

    assert 'import http.server as BaseHTTPServer' in content, "service.py did not update the BaseHTTPServer import."
    assert 'import urllib.parse as urlparse' in content, "service.py did not update the urlparse import."
    assert 'print(' in content, "service.py did not update print statements to Python 3 function calls."
    assert 'print "' not in content, "service.py still contains Python 2 print statements."


def test_migration_result_log_correct():
    log_path = "/home/user/migration_result.log"
    assert os.path.isfile(log_path), f"The file {log_path} was not created."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected = "Processed: migrate_me"
    assert content == expected, f"Expected {log_path} to contain '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
