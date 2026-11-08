#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.util
import json
import os
import signal
import socket
import subprocess
import sys
import time
import uuid

import pytest
import requests

WORKSPACE = "/home/user/workspace"
DATA_DIR = os.path.join(WORKSPACE, "data")
RESULT_PATH = os.path.join(WORKSPACE, "e2e_result.json")


def port_5000_open():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(("127.0.0.1", 5000)) == 0


def stop_process(proc):
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass


def wait_for_server(proc, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if port_5000_open():
            return True
        if proc.poll() is not None:
            return False
        time.sleep(0.1)
    return False


def make_dynamic_case():
    token = uuid.uuid4().hex
    failed_name = f"a_failed_{token}.txt"
    good_name = f"m_good_{token}.txt"
    missing_name = f"z_missing_{token}.txt"
    failed_content = os.urandom(41)
    good_content = os.urandom(53)

    with open(os.path.join(DATA_DIR, failed_name), "wb") as f:
        f.write(failed_content)
    with open(os.path.join(DATA_DIR, good_name), "wb") as f:
        f.write(good_content)

    constraints = [
        {
            "filename": missing_name,
            "expected_sha256": hashlib.sha256(b"not present").hexdigest(),
        },
        {
            "filename": good_name,
            "expected_sha256": hashlib.sha256(good_content).hexdigest(),
        },
        {
            "filename": failed_name,
            "expected_sha256": hashlib.sha256(b"deliberately wrong").hexdigest(),
        },
    ]
    return constraints, [failed_name, missing_name], [failed_name, good_name]


def remove_case_files(names):
    for name in names:
        try:
            os.remove(os.path.join(DATA_DIR, name))
        except FileNotFoundError:
            pass


def test_verify_checksums_dynamic_inputs():
    hashing_path = os.path.join(WORKSPACE, "api", "utils", "hashing.py")
    assert os.path.isfile(hashing_path), f"File {hashing_path} is missing."

    spec = importlib.util.spec_from_file_location("submitted_hashing", hashing_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    assert callable(getattr(module, "verify_checksums", None)), "verify_checksums is missing or not callable."

    constraints, expected, created = make_dynamic_case()
    try:
        actual = module.verify_checksums(constraints)
        assert actual == expected, f"verify_checksums returned {actual!r}; expected {expected!r}."
    finally:
        remove_case_files(created)


def test_live_flask_endpoint_dynamic_inputs():
    assert not port_5000_open(), "Port 5000 was already in use before the verifier started the application."

    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join([
        WORKSPACE,
        os.path.join(WORKSPACE, "api"),
        env.get("PYTHONPATH", ""),
    ])
    commands = [
        [sys.executable, os.path.join(WORKSPACE, "api", "app.py")],
        [sys.executable, "-m", "api.app"],
    ]
    proc = None
    for command in commands:
        candidate = subprocess.Popen(
            command,
            cwd=WORKSPACE,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        if wait_for_server(candidate):
            proc = candidate
            break
        stop_process(candidate)

    assert proc is not None, "The Flask application could not be started on port 5000."
    constraints, expected, created = make_dynamic_case()
    try:
        response = requests.post(
            "http://127.0.0.1:5000/verify_files",
            json={"constraints": constraints},
            timeout=5,
        )
        assert response.status_code == 200, f"Endpoint returned HTTP {response.status_code}: {response.text}"
        assert response.json() == {"failed_files": expected}, (
            f"Endpoint returned {response.text!r}; expected failed_files {expected!r}."
        )
    finally:
        remove_case_files(created)
        stop_process(proc)


def test_execute_e2e_script():
    test_e2e_path = os.path.join(WORKSPACE, "test_e2e.py")
    assert os.path.isfile(test_e2e_path), f"File {test_e2e_path} is missing. The orchestrating script was not created."
    assert not port_5000_open(), "Port 5000 was in use before test_e2e.py was executed."

    try:
        os.remove(RESULT_PATH)
    except FileNotFoundError:
        pass

    try:
        completed = subprocess.run(
            [sys.executable, test_e2e_path],
            cwd=WORKSPACE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=40,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"test_e2e.py did not exit cleanly within 40 seconds: {exc}")

    assert completed.returncode == 0, (
        "test_e2e.py did not exit cleanly.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), "Running test_e2e.py did not create e2e_result.json."

    deadline = time.time() + 3
    while time.time() < deadline and port_5000_open():
        time.sleep(0.1)
    assert not port_5000_open(), "test_e2e.py exited without shutting down its Flask server."


def test_e2e_result():
    result_path = "/home/user/workspace/e2e_result.json"
    assert os.path.isfile(result_path), f"File {result_path} is missing. Did the e2e test script run and create it?"

    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {result_path} does not contain valid JSON.")

    assert "failed_files" in data, "The JSON response is missing the 'failed_files' key."
    assert isinstance(data["failed_files"], list), "'failed_files' should be a list."

    expected_failed = ["app.log", "missing.txt"]
    assert data["failed_files"] == expected_failed, f"Expected failed_files to be {expected_failed}, but got {data['failed_files']}"


def test_app_py_import_fixed():
    app_py_path = "/home/user/workspace/api/app.py"
    assert os.path.isfile(app_py_path), f"File {app_py_path} is missing."
    with open(app_py_path, "r") as f:
        content = f.read()

    # The broken import was `from hashing import verify_checksums`
    # Keep the original assertion that the exact broken import is gone.
    assert "from hashing import verify_checksums" not in content, "The import in app.py is still broken (still using 'from hashing import verify_checksums')."

    try:
        compile(content, app_py_path, 'exec')
    except SyntaxError as e:
        pytest.fail(f"Syntax error in app.py: {e}")


def test_test_e2e_py_exists():
    test_e2e_path = "/home/user/workspace/test_e2e.py"
    assert os.path.isfile(test_e2e_path), f"File {test_e2e_path} is missing. The orchestrating script was not created."

    with open(test_e2e_path, "r") as f:
        content = f.read()

    try:
        compile(content, test_e2e_path, 'exec')
    except SyntaxError as e:
        pytest.fail(f"Syntax error in test_e2e.py: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
