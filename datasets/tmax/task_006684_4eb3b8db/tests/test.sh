#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest
import stat
import math
import random
import difflib
import importlib.util
import socket
import socketserver
import threading
import urllib.request
import subprocess
import time


def test_matrix_csv_patched():
    file_path = "/home/user/matrix.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip().replace("\r\n", "\n")

    expected_content = "1.0, 2.0, 3.0\n4.0, 10.0, 6.0\n7.0, 8.0, 9.0"
    assert content == expected_content, f"Content of {file_path} does not match the expected patched state. Found:\n{content}"


def test_result_json_exists_and_correct():
    file_path = "/home/user/result.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing. The e2e_test.sh script might not have generated it."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert "trace" in data, "JSON result is missing the 'trace' key."
    assert "frobenius" in data, "JSON result is missing the 'frobenius' key."

    trace_val = float(data["trace"])
    frob_val = float(data["frobenius"])

    assert abs(trace_val - 20.0) < 1e-4, f"Expected trace to be 20.0, got {trace_val}"
    assert abs(frob_val - 18.9737) < 1e-4, f"Expected frobenius to be 18.9737, got {frob_val}"


def test_e2e_test_script_exists_and_executable():
    file_path = "/home/user/e2e_test.sh"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    st = os.stat(file_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {file_path} is not executable."


def test_server_py_modified():
    file_path = "/home/user/server.py"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read()

    assert "TODO" not in content or len(content.splitlines()) > 25, "server.py doesn't seem to be fully implemented."


def matrix_text(matrix):
    return "\n".join(", ".join(f"{value:.1f}" for value in row) for row in matrix) + "\n"


def make_patch(old_text, new_text):
    return "".join(difflib.unified_diff(
        old_text.splitlines(True), new_text.splitlines(True),
        fromfile="matrix.csv", tofile="matrix.csv"
    ))


def expected_values(matrix):
    trace = sum(matrix[i][i] for i in range(min(len(matrix), len(matrix[0]))))
    frobenius = math.sqrt(sum(value * value for row in matrix for value in row))
    return round(trace, 4), round(frobenius, 4)


def assert_response(body, matrix):
    try:
        data = json.loads(body)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Response is not valid JSON: {body!r}: {exc}")
    assert "trace" in data and "frobenius" in data
    assert not isinstance(data["trace"], bool)
    assert not isinstance(data["frobenius"], bool)
    actual_trace = float(data["trace"])
    actual_frobenius = float(data["frobenius"])
    expected_trace, expected_frobenius = expected_values(matrix)
    assert math.isfinite(actual_trace) and math.isfinite(actual_frobenius)
    assert abs(actual_trace - expected_trace) < 0.00005
    assert abs(actual_frobenius - expected_frobenius) < 0.00005


def port_open(port=8000):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.15):
            return True
    except OSError:
        return False


def random_matrix(rng):
    return [[rng.randint(-150, 220) / 10.0 for _ in range(3)] for _ in range(3)]


def test_live_endpoint_and_e2e_orchestration():
    rng = random.SystemRandom()

    # Exercise the submitted request handler directly on an unpredictable patch.
    base = random_matrix(rng)
    updated = random_matrix(rng)
    while updated == base:
        updated = random_matrix(rng)
    base_text = matrix_text(base)
    updated_text = matrix_text(updated)
    with open("/home/user/matrix.csv", "w") as f:
        f.write(base_text)

    spec = importlib.util.spec_from_file_location("submitted_server", "/home/user/server.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "MatrixRequestHandler"), "server.py does not define MatrixRequestHandler"

    old_cwd = os.getcwd()
    os.chdir("/home/user")
    httpd = socketserver.TCPServer(("127.0.0.1", 0), module.MatrixRequestHandler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        request = urllib.request.Request(
            f"http://127.0.0.1:{httpd.server_address[1]}/apply",
            data=make_patch(base_text, updated_text).encode("utf-8"),
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=8) as response:
            assert response.status == 200
            body = response.read().decode("utf-8")
        assert_response(body, updated)
        with open("/home/user/matrix.csv") as f:
            assert f.read() == updated_text
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=3)
        os.chdir(old_cwd)

    # Exercise the submitted orchestration script with a second unpredictable patch.
    base2 = random_matrix(rng)
    updated2 = random_matrix(rng)
    while updated2 == base2:
        updated2 = random_matrix(rng)
    base2_text = matrix_text(base2)
    updated2_text = matrix_text(updated2)
    with open("/home/user/matrix.csv", "w") as f:
        f.write(base2_text)
    with open("/home/user/test.patch", "w") as f:
        f.write(make_patch(base2_text, updated2_text))
    try:
        os.remove("/home/user/result.json")
    except FileNotFoundError:
        pass

    assert not port_open(), "Port 8000 was already occupied before e2e_test.sh ran"
    proc = subprocess.Popen(
        ["/home/user/e2e_test.sh"], cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    observed_server = False
    deadline = time.time() + 8
    while time.time() < deadline and proc.poll() is None:
        if port_open():
            observed_server = True
            break
        time.sleep(0.05)
    try:
        stdout, stderr = proc.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        pytest.fail(f"e2e_test.sh timed out. stdout={stdout!r}, stderr={stderr!r}")

    assert proc.returncode == 0, f"e2e_test.sh failed. stdout={stdout!r}, stderr={stderr!r}"
    assert observed_server, "e2e_test.sh never started a server listening on port 8000"
    assert os.path.isfile("/home/user/result.json"), "e2e_test.sh did not create result.json"
    with open("/home/user/result.json") as f:
        assert_response(f.read(), updated2)
    with open("/home/user/matrix.csv") as f:
        assert f.read() == updated2_text

    deadline = time.time() + 5
    while time.time() < deadline and port_open():
        time.sleep(0.1)
    assert not port_open(), "e2e_test.sh did not terminate the API server"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
