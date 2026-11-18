#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import time
import urllib.request

import pytest

RELEASE_DIR = "/home/user/emulator_release"
BINARY_PATH = os.path.join(RELEASE_DIR, "emulator_server")
SERVER_PROCESS = None


def post_json(payload):
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        "http://localhost:8080/load_and_run",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=3) as response:
        return response.read()


def test_01_emulator_server_compiled():
    assert os.path.isfile(BINARY_PATH), (
        f"The binary {BINARY_PATH} was not found. Did the code compile successfully?"
    )
    assert os.access(BINARY_PATH, os.X_OK), f"The file {BINARY_PATH} is not executable."

    with open(BINARY_PATH, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "emulator_server is not a compiled ELF binary."

    build = subprocess.run(
        [
            "g++", "-std=c++17", "-pthread",
            "main.cpp", "machine.cpp",
            "-o", "/tmp/emulator_source_build_check",
        ],
        cwd=RELEASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert build.returncode == 0, "The submitted C++ sources do not compile:\n" + build.stdout


def test_02_schema_migration():
    state1_path = "/home/user/states/state_1.json"
    assert os.path.isfile(state1_path), f"The state file {state1_path} is missing."

    with open(state1_path, "r") as f:
        try:
            data1 = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {state1_path} does not contain valid JSON.")

    expected_state1 = {
        "machine_state": {
            "data_stack": [10, 20],
            "instruction_pointer": 0
        },
        "version": 2
    }
    assert data1 == expected_state1, f"The schema migration for {state1_path} is incorrect. Expected {expected_state1}, got {data1}."

    state2_path = "/home/user/states/state_2.json"
    assert os.path.isfile(state2_path), f"The state file {state2_path} is missing."

    with open(state2_path, "r") as f:
        try:
            data2 = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {state2_path} does not contain valid JSON.")

    expected_state2 = {
        "machine_state": {
            "data_stack": [5],
            "instruction_pointer": 1
        },
        "version": 2
    }
    assert data2 == expected_state2, f"The schema migration for {state2_path} is incorrect. Expected {expected_state2}, got {data2}."


@pytest.fixture(scope="session")
def running_server():
    global SERVER_PROCESS

    # Replace the agent-started instance with a fresh execution of the submitted artifact.
    subprocess.run(["pkill", "-x", "emulator_server"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.3)

    output = open("/tmp/emulator_server_verifier.log", "wb")
    SERVER_PROCESS = subprocess.Popen(
        [BINARY_PATH],
        cwd=RELEASE_DIR,
        stdout=output,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    probe = {
        "machine_state": {"data_stack": [3, 17], "instruction_pointer": 0},
        "version": 2,
    }
    last_error = None
    for _ in range(40):
        if SERVER_PROCESS.poll() is not None:
            output.flush()
            with open("/tmp/emulator_server_verifier.log", "rb") as log:
                details = log.read().decode("utf-8", errors="replace")
            pytest.fail(f"emulator_server exited instead of remaining active: {details}")
        try:
            assert post_json(probe) == b"SUCCESS: Stack top is 17"
            break
        except Exception as exc:
            last_error = exc
            time.sleep(0.15)
    else:
        pytest.fail(f"emulator_server did not begin serving localhost:8080: {last_error}")

    yield SERVER_PROCESS
    # Intentionally do not terminate it: the deployment requires the server to remain running.


def test_03_server_executes_dynamic_requests(running_server):
    for _ in range(3):
        stack = [secrets.randbelow(2001) - 1000 for _ in range(3)]
        expected_top = secrets.randbelow(2001) - 1000
        stack.append(expected_top)
        payload = {
            "machine_state": {
                "data_stack": stack,
                "instruction_pointer": secrets.randbelow(20),
            },
            "version": 2,
        }
        response = post_json(payload)
        assert response == f"SUCCESS: Stack top is {expected_top}".encode("utf-8")
        assert running_server.poll() is None, "emulator_server stopped while requests were being tested."


def test_04_deployment_log(running_server):
    log_path = "/home/user/deployment_log.txt"
    assert os.path.isfile(log_path), f"The deployment log file {log_path} is missing. Did you run the curl command and save the output?"

    with open(log_path, "r") as f:
        log_content = f.read().strip()

    expected_content = "SUCCESS: Stack top is 20"
    assert log_content == expected_content, f"The deployment log content is incorrect. Expected '{expected_content}', got '{log_content}'."

    with open("/home/user/states/state_1.json", "r") as state_file:
        migrated_state = json.load(state_file)
    live_response = post_json(migrated_state)
    with open(log_path, "rb") as log_file:
        exact_log = log_file.read()
    assert exact_log == live_response, "deployment_log.txt is not exactly the response returned for state_1.json."


def test_05_server_remains_running_and_listening(running_server):
    assert running_server.poll() is None, "emulator_server is no longer running."
    payload = {
        "machine_state": {"data_stack": [41, 73], "instruction_pointer": 2},
        "version": 2,
    }
    assert post_json(payload) == b"SUCCESS: Stack top is 73"
    assert running_server.poll() is None, "emulator_server did not remain running after validation."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
