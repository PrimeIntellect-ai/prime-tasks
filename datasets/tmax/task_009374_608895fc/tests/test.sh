#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

import pytest

APP_DIR = "/home/user/app"


def wait_for_port(port, proc=None, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            pytest.fail(f"Process exited before port {port} became available")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Timed out waiting for port {port}")


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def pid_is_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def read_pids(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [int(line.strip()) for line in f if line.strip()]


def test_stubs_generated():
    """Verify that the protocol buffer stubs have been compiled."""
    pb2_path = os.path.join(APP_DIR, "processor_pb2.py")
    pb2_grpc_path = os.path.join(APP_DIR, "processor_pb2_grpc.py")

    assert os.path.isfile(pb2_path), f"Stub file {pb2_path} is missing. Did you compile the proto file?"
    assert os.path.isfile(pb2_grpc_path), f"Stub file {pb2_grpc_path} is missing. Did you compile the proto file?"

    check = subprocess.run(
        [sys.executable, "-c", "import processor_pb2, processor_pb2_grpc; assert hasattr(processor_pb2, 'ProcessRequest'); assert hasattr(processor_pb2_grpc, 'TextProcessorStub')"],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
    )
    assert check.returncode == 0, f"Generated stubs are not importable or do not describe the required service: {check.stderr}"


def test_e2e_script():
    """Run the submitted orchestration and prove its requests traverse proxy and gRPC."""
    script_path = os.path.join(APP_DIR, "run_e2e.sh")
    log_path = os.path.join(APP_DIR, "test_results.log")
    backend_path = os.path.join(APP_DIR, "backend.py")
    proxy_path = os.path.join(APP_DIR, "proxy.py")
    saved_proxy_path = os.path.join(APP_DIR, ".proxy_verifier_original.py")
    rpc_log = "/tmp/e2e_rpc_calls.jsonl"
    backend_pid_log = "/tmp/e2e_backend_pid"
    proxy_pid_log = "/tmp/e2e_proxy_pid"

    assert os.path.isfile(script_path), f"E2E script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"E2E script {script_path} is not executable."
    assert os.path.isfile(proxy_path), f"Proxy script {proxy_path} is missing."

    with open(backend_path, "rb") as f:
        original_backend = f.read()
    backend_mode = os.stat(backend_path).st_mode
    with open(proxy_path, "rb") as f:
        original_proxy = f.read()
    proxy_mode = os.stat(proxy_path).st_mode

    for path in (log_path, rpc_log, backend_pid_log, proxy_pid_log, saved_proxy_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    instrumented_backend = r'''import json
import os
import time
from concurrent import futures
import grpc
import processor_pb2
import processor_pb2_grpc

with open("/tmp/e2e_backend_pid", "a") as f:
    f.write(str(os.getpid()) + "\\n")

class Servicer(processor_pb2_grpc.TextProcessorServicer):
    def ProcessText(self, request, context):
        with open("/tmp/e2e_rpc_calls.jsonl", "a") as f:
            f.write(json.dumps({"text": request.text, "action": int(request.action)}) + "\\n")
            f.flush()
        if request.action == processor_pb2.UPPER:
            result = request.text.upper()
        elif request.action == processor_pb2.REVERSE:
            result = request.text[::-1]
        else:
            result = request.text
        return processor_pb2.ProcessResponse(result=result)

server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
processor_pb2_grpc.add_TextProcessorServicer_to_server(Servicer(), server)
server.add_insecure_port("[::]:50051")
server.start()
try:
    while True:
        time.sleep(3600)
except KeyboardInterrupt:
    server.stop(0)
'''
    proxy_wrapper = f'''import os, sys
with open({proxy_pid_log!r}, "a") as f:
    f.write(str(os.getpid()) + "\\n")
os.execv(sys.executable, [sys.executable, {saved_proxy_path!r}])
'''

    result = None
    observed_pids = []
    try:
        with open(saved_proxy_path, "wb") as f:
            f.write(original_proxy)
        os.chmod(saved_proxy_path, proxy_mode)
        with open(backend_path, "w") as f:
            f.write(instrumented_backend)
        os.chmod(backend_path, backend_mode)
        with open(proxy_path, "w") as f:
            f.write(proxy_wrapper)
        os.chmod(proxy_path, proxy_mode)

        result = subprocess.run(
            [script_path], cwd=APP_DIR, capture_output=True, text=True, timeout=40
        )

        assert os.path.isfile(log_path), f"Log file {log_path} was not created by run_e2e.sh."
        with open(log_path) as f:
            content = f.read().strip()
        assert content == "E2E_ALL_PASS", f"Expected 'E2E_ALL_PASS' in {log_path}, but got: '{content}'"
        assert result.returncode == 0, f"run_e2e.sh exited with {result.returncode}: {result.stderr}"

        backend_pids = read_pids(backend_pid_log)
        proxy_pids = read_pids(proxy_pid_log)
        observed_pids = backend_pids + proxy_pids
        assert backend_pids, "run_e2e.sh did not start backend.py"
        assert proxy_pids, "run_e2e.sh did not start proxy.py"

        assert os.path.isfile(rpc_log), "The E2E requests never reached the gRPC backend"
        with open(rpc_log) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert {"text": "hello e2e", "action": 0} in calls, "E2E upper request did not traverse the proxy to gRPC"
        assert {"text": "protobuf", "action": 1} in calls, "E2E reverse request did not traverse the proxy to gRPC"

        time.sleep(0.5)
        still_alive = [pid for pid in observed_pids if pid_is_alive(pid)]
        assert not still_alive, f"run_e2e.sh did not clean up background services: {still_alive}"
    finally:
        for pid in set(observed_pids + read_pids(backend_pid_log) + read_pids(proxy_pid_log)):
            if pid_is_alive(pid):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        with open(backend_path, "wb") as f:
            f.write(original_backend)
        os.chmod(backend_path, backend_mode)
        with open(proxy_path, "wb") as f:
            f.write(original_proxy)
        os.chmod(proxy_path, proxy_mode)
        try:
            os.remove(saved_proxy_path)
        except FileNotFoundError:
            pass


def test_proxy_endpoints():
    """Verify normal and randomized requests against the real backend."""
    proxy_path = os.path.join(APP_DIR, "proxy.py")
    backend_path = os.path.join(APP_DIR, "backend.py")
    assert os.path.isfile(proxy_path), f"Proxy script {proxy_path} is missing."

    backend_proc = subprocess.Popen([sys.executable, backend_path], cwd=APP_DIR)
    proxy_proc = subprocess.Popen([sys.executable, proxy_path], cwd=APP_DIR)
    try:
        wait_for_port(50051, backend_proc)
        wait_for_port(8080, proxy_proc)

        url_upper = "http://localhost:8080/api/v1/process/upper?text=verification"
        with urllib.request.urlopen(url_upper, timeout=5) as response:
            data = json.loads(response.read().decode())
            assert data.get("result") == "VERIFICATION", f"Expected 'VERIFICATION' for upper action, got {data.get('result')}"
        assert backend_proc.poll() is None, "Backend stopped while serving proxy requests"

        url_reverse = "http://localhost:8080/api/v1/process/reverse?text=verification"
        with urllib.request.urlopen(url_reverse, timeout=5) as response:
            data = json.loads(response.read().decode())
            assert data.get("result") == "noitacifirev", f"Expected 'noitacifirev' for reverse action, got {data.get('result')}"
        assert backend_proc.poll() is None, "Backend stopped while serving proxy requests"

        for action in ("upper", "reverse"):
            text = "Dynamic " + uuid.uuid4().hex + " zZ9"
            expected = text.upper() if action == "upper" else text[::-1]
            query = urllib.parse.urlencode({"text": text})
            url = f"http://localhost:8080/api/v1/process/{action}?{query}"
            with urllib.request.urlopen(url, timeout=5) as response:
                assert response.status == 200
                data = json.loads(response.read().decode())
                assert data.get("result") == expected
            assert backend_proc.poll() is None, "Backend did not remain running"

        url_invalid = "http://localhost:8080/api/v1/process/invalid?text=verification"
        try:
            with urllib.request.urlopen(url_invalid, timeout=5) as response:
                pytest.fail(f"Expected HTTP 400 for invalid action, but got HTTP {response.status}")
        except urllib.error.HTTPError as e:
            assert e.code == 400, f"Expected HTTP 400 for invalid action, got HTTP {e.code}"
    finally:
        stop_process(proxy_proc)
        stop_process(backend_proc)


def test_proxy_actually_calls_grpc():
    """Use an unpredictable gRPC backend response to reject hard-coded HTTP servers."""
    proxy_path = os.path.join(APP_DIR, "proxy.py")
    fake_backend_path = "/tmp/verifier_fake_backend.py"
    record_path = "/tmp/verifier_grpc_records.jsonl"
    try:
        os.remove(record_path)
    except FileNotFoundError:
        pass

    fake_backend = r'''import json
import time
from concurrent import futures
import grpc
import processor_pb2
import processor_pb2_grpc

class Servicer(processor_pb2_grpc.TextProcessorServicer):
    def ProcessText(self, request, context):
        with open("/tmp/verifier_grpc_records.jsonl", "a") as f:
            f.write(json.dumps({"text": request.text, "action": int(request.action)}) + "\\n")
            f.flush()
        return processor_pb2.ProcessResponse(result="grpc-proof:" + str(int(request.action)) + ":" + request.text)

server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
processor_pb2_grpc.add_TextProcessorServicer_to_server(Servicer(), server)
server.add_insecure_port("[::]:50051")
server.start()
try:
    while True:
        time.sleep(3600)
except KeyboardInterrupt:
    server.stop(0)
'''
    with open(fake_backend_path, "w") as f:
        f.write(fake_backend)

    backend_proc = subprocess.Popen([sys.executable, fake_backend_path], cwd=APP_DIR)
    proxy_proc = subprocess.Popen([sys.executable, proxy_path], cwd=APP_DIR)
    expected_calls = []
    try:
        wait_for_port(50051, backend_proc)
        wait_for_port(8080, proxy_proc)
        for action, enum_value in (("upper", 0), ("reverse", 1)):
            text = uuid.uuid4().hex + " Mixed text " + uuid.uuid4().hex
            expected_calls.append({"text": text, "action": enum_value})
            url = "http://localhost:8080/api/v1/process/{}?{}".format(
                action, urllib.parse.urlencode({"text": text})
            )
            with urllib.request.urlopen(url, timeout=5) as response:
                data = json.loads(response.read().decode())
                assert data == {"result": f"grpc-proof:{enum_value}:{text}"}
            assert backend_proc.poll() is None, "gRPC backend stopped during proxy operation"

        with open(record_path) as f:
            records = [json.loads(line) for line in f if line.strip()]
        for expected in expected_calls:
            assert expected in records, f"Proxy did not send the expected gRPC request: {expected}"
    finally:
        stop_process(proxy_proc)
        stop_process(backend_proc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
