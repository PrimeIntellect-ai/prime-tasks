#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

PROJECT_DIR = "/home/user/project"
SCRIPT_PATH = os.path.join(PROJECT_DIR, "build_and_test.sh")
LOG_PATH = os.path.join(PROJECT_DIR, "result.log")
SO_PATH = os.path.join(PROJECT_DIR, "libmathops.so")
SERVER_PATH = os.path.join(PROJECT_DIR, "server.py")
CLIENT_PATH = os.path.join(PROJECT_DIR, "client_test.py")

EXPECTED_SERVER = '''import time
import ctypes
import sys
from xmlrpc.server import SimpleXMLRPCServer

# Simulate a gRPC/RPC service wrapping a C lib
try:
    lib = ctypes.CDLL('./libmathops.so')
    lib.compute_transform.restype = ctypes.c_double
    lib.compute_transform.argtypes = [ctypes.c_double]
except OSError as e:
    print(f"Failed to load library: {e}", file=sys.stderr)
    sys.exit(1)

def compute(val):
    return lib.compute_transform(val)

server = SimpleXMLRPCServer(("localhost", 8080), allow_none=True)
server.register_function(compute, "compute")
server.serve_forever()
'''

EXPECTED_CLIENT = '''import xmlrpc.client
import sys
import math

try:
    proxy = xmlrpc.client.ServerProxy("http://localhost:8080/")
    val = proxy.compute(0.0)
    # cos(0) + sin(0) = 1.0
    if not math.isclose(val, 1.0, rel_tol=1e-5):
        print("Property test failed!")
        sys.exit(1)
    print("All property tests passed.")
    sys.exit(0)
except Exception as e:
    print(f"Connection/Test error: {e}")
    sys.exit(1)
'''


def server_processes():
    found = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            args = (entry / "cmdline").read_bytes().split(b"\0")
            decoded = [arg.decode(errors="replace") for arg in args if arg]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if any(os.path.basename(arg) == "server.py" for arg in decoded):
            found.append((int(entry.name), " ".join(decoded)))
    return found


def terminate_servers(processes):
    for pid, _ in processes:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline:
        remaining = server_processes()
        if not remaining:
            return
        time.sleep(0.05)
    for pid, _ in server_processes():
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


@pytest.fixture(scope="session", autouse=True)
def run_script():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    if os.path.exists(SO_PATH):
        os.remove(SO_PATH)

    original_server = Path(SERVER_PATH).read_text()
    original_client = Path(CLIENT_PATH).read_text()
    sources_unchanged = (
        original_server == EXPECTED_SERVER and original_client == EXPECTED_CLIENT
    )

    preexisting = server_processes()
    terminate_servers(preexisting)

    marker_dir = Path(tempfile.mkdtemp(prefix="pipeline-verifier-"))
    server_started = marker_dir / "server_started"
    server_request = marker_dir / "server_request"
    client_started = marker_dir / "client_started"
    client_success = marker_dir / "client_success"

    instrumented_server = f'''import time
import ctypes
import sys
from xmlrpc.server import SimpleXMLRPCServer

try:
    lib = ctypes.CDLL('./libmathops.so')
    lib.compute_transform.restype = ctypes.c_double
    lib.compute_transform.argtypes = [ctypes.c_double]
except OSError as e:
    print(f"Failed to load library: {{e}}", file=sys.stderr)
    sys.exit(1)

def compute(val):
    with open({str(server_request)!r}, "a") as marker:
        marker.write(str(time.time()) + "\\n")
    return lib.compute_transform(val)

server = SimpleXMLRPCServer(("localhost", 8080), allow_none=True)
server.register_function(compute, "compute")
with open({str(server_started)!r}, "w") as marker:
    marker.write(str(time.time()))
server.serve_forever()
'''

    instrumented_client = f'''import xmlrpc.client
import sys
import math
import time

with open({str(client_started)!r}, "w") as marker:
    marker.write(str(time.time()))
try:
    proxy = xmlrpc.client.ServerProxy("http://localhost:8080/")
    val = proxy.compute(0.0)
    if not math.isclose(val, 1.0, rel_tol=1e-5):
        print("Property test failed!")
        sys.exit(1)
    with open({str(client_success)!r}, "w") as marker:
        marker.write(str(time.time()))
    print("All property tests passed.")
    sys.exit(0)
except Exception as e:
    print(f"Connection/Test error: {{e}}")
    sys.exit(1)
'''

    Path(SERVER_PATH).write_text(instrumented_server)
    Path(CLIENT_PATH).write_text(instrumented_client)

    start_time = time.time()
    try:
        try:
            result = subprocess.run(
                [SCRIPT_PATH],
                cwd=PROJECT_DIR,
                capture_output=True,
                text=True,
                timeout=30,
            )
        except subprocess.TimeoutExpired as exc:
            result = subprocess.CompletedProcess(
                [SCRIPT_PATH], 124, exc.stdout or "", (exc.stderr or "") + "\nTimed out"
            )
        duration = time.time() - start_time
        lingering = server_processes()
    finally:
        terminate_servers(server_processes())
        Path(SERVER_PATH).write_text(original_server)
        Path(CLIENT_PATH).write_text(original_client)

    def marker_time(path):
        try:
            return float(path.read_text().strip().splitlines()[-1])
        except (FileNotFoundError, ValueError, IndexError):
            return None

    return {
        "result": result,
        "duration": duration,
        "sources_unchanged": sources_unchanged,
        "preexisting": preexisting,
        "lingering": lingering,
        "server_started": marker_time(server_started),
        "server_request": marker_time(server_request),
        "client_started": marker_time(client_started),
        "client_success": marker_time(client_success),
    }


def test_only_build_script_was_modified(run_script):
    assert run_script["sources_unchanged"], "server.py or client_test.py was modified."


def test_script_execution(run_script):
    assert run_script["result"].returncode == 0, f"Script failed to execute properly. Stderr: {run_script['result'].stderr}"


def test_sleep_in_script_and_duration(run_script):
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "sleep 2" in content, "The script does not contain 'sleep 2' to pause for the server."
    assert run_script["duration"] >= 2.0, "The script finished in less than 2 seconds, indicating it did not actually pause."


def test_end_to_end_pipeline_was_run(run_script):
    assert not run_script["preexisting"], f"A server.py process was already running before the script: {run_script['preexisting']}"
    assert run_script["server_started"] is not None, "build_and_test.sh did not start server.py successfully."
    assert run_script["client_started"] is not None, "build_and_test.sh did not execute client_test.py."
    assert run_script["server_request"] is not None, "The spawned server did not receive the client's RPC request."
    assert run_script["client_success"] is not None, "client_test.py did not complete successfully."
    assert run_script["client_started"] - run_script["server_started"] >= 1.8, "client_test.py was not run after the required two-second server startup pause."
    assert run_script["server_started"] <= run_script["server_request"] <= run_script["client_success"], "The recorded server/client events are not in the expected order."


def test_libmathops_linked_libm():
    assert os.path.isfile(SO_PATH), f"{SO_PATH} was not created."
    result = subprocess.run(["ldd", SO_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"ldd failed on {SO_PATH}"
    assert "libm.so" in result.stdout, "libmathops.so is not linked against the math library (libm.so)."


def test_result_log_success():
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} was not created."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"Expected exact string 'SUCCESS' in result.log, got '{content}'"


def test_server_process_terminated(run_script):
    assert not run_script["lingering"], f"The server.py process was still running when build_and_test.sh exited: {run_script['lingering']}"
    result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
    running_servers = [
        line for line in result.stdout.splitlines()
        if "server.py" in line and "grep" not in line and "pytest" not in line
    ]
    assert len(running_servers) == 0, f"The server.py process is still running in the background: {running_servers}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
