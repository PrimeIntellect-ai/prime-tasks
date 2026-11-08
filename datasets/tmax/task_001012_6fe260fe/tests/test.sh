#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import secrets
import signal
import socket
import subprocess
import time

import pytest

BASE_DIR = "/home/user/api_integration"
API_PATH = os.path.join(BASE_DIR, "api.py")
RUNNER_PATH = os.path.join(BASE_DIR, "test_runner.py")

EXPECTED_C_SOURCE = '''#include <stdio.h>
#include <string.h>

const char* get_data() {
    return "[{\\"id\\": 3, \\"name\\": \\"Alice\\", \\"role\\": \\"admin\\"}, {\\"id\\": 1, \\"name\\": \\"Bob\\", \\"role\\": \\"user\\"}, {\\"id\\": 2, \\"name\\": \\"Charlie\\", \\"role\\": \\"moderator\\"}]";
}
'''

EXPECTED_CPP_SOURCE = '''#include <iostream>
#include <string>

extern "C" {
    const char* get_data() {
        return "[{\\"id\\": 1, \\"name\\": \\"Bob\\", \\"role\\": \\"user\\"}, {\\"id\\": 3, \\"name\\": \\"Alice\\", \\"role\\": \\"admin\\"}, {\\"id\\": 2, \\"name\\": \\"Charlie\\", \\"role\\": \\"moderator\\"}]";
    }
}
'''

EXPECTED_API_SOURCE = '''import ctypes
import json
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/api/v1/data')
def v1_data():
    try:
        lib = ctypes.CDLL('./libbackend_c.so')
        lib.get_data.restype = ctypes.c_char_p
        data = lib.get_data()
        return jsonify(json.loads(data.decode('utf-8')))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/v2/data')
def v2_data():
    try:
        lib = ctypes.CDLL('./libbackend_cpp.so')
        lib.get_data.restype = ctypes.c_char_p
        data = lib.get_data()
        return jsonify(json.loads(data.decode('utf-8')))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(port=5000)
'''

EXPECTED_DATA = [
    {"id": 1, "name": "Bob", "role": "user"},
    {"id": 2, "name": "Charlie", "role": "moderator"},
    {"id": 3, "name": "Alice", "role": "admin"},
]


def port_5000_open():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.25)
        return sock.connect_ex(("127.0.0.1", 5000)) == 0


def run_runner():
    result = subprocess.run(
        ["python3", RUNNER_PATH],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=35,
    )
    assert result.returncode == 0, (
        "test_runner.py failed.\nSTDOUT:\n" + result.stdout +
        "\nSTDERR:\n" + result.stderr
    )
    time.sleep(0.3)
    assert not port_5000_open(), "The API server on port 5000 was not terminated by test_runner.py."


def load_library_data(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\\x7fELF", f"{path} is not an ELF shared library."
    try:
        library = ctypes.CDLL(path)
        function = library.get_data
        function.restype = ctypes.c_char_p
        raw = function()
        assert raw is not None
        return json.loads(raw.decode("utf-8"))
    except Exception as exc:
        pytest.fail(f"Could not load and call get_data from {path}: {exc}")


def test_00_inputs_unmodified_and_shared_libraries_work():
    with open(os.path.join(BASE_DIR, "backend_c.c"), encoding="utf-8") as f:
        assert f.read() == EXPECTED_C_SOURCE, "backend_c.c was modified."
    with open(os.path.join(BASE_DIR, "backend_cpp.cpp"), encoding="utf-8") as f:
        assert f.read() == EXPECTED_CPP_SOURCE, "backend_cpp.cpp was modified."
    with open(API_PATH, encoding="utf-8") as f:
        assert f.read() == EXPECTED_API_SOURCE, "api.py was modified."

    lib_c = os.path.join(BASE_DIR, "libbackend_c.so")
    lib_cpp = os.path.join(BASE_DIR, "libbackend_cpp.so")
    assert os.path.isfile(lib_c), f"Expected shared library {lib_c} does not exist. Did you compile backend_c.c?"
    assert os.path.isfile(lib_cpp), f"Expected shared library {lib_cpp} does not exist. Did you compile backend_cpp.cpp?"
    assert sorted(load_library_data(lib_c), key=lambda item: item["id"]) == EXPECTED_DATA
    assert sorted(load_library_data(lib_cpp), key=lambda item: item["id"]) == EXPECTED_DATA


def test_01_runner_really_orchestrates_http_and_is_executed():
    assert os.path.isfile(RUNNER_PATH), f"{RUNNER_PATH} does not exist."
    with open(RUNNER_PATH, encoding="utf-8") as f:
        runner_source = f.read()
    try:
        tree = ast.parse(runner_source)
    except SyntaxError as exc:
        pytest.fail(f"test_runner.py is not valid Python: {exc}")

    assert "diff -u v1_sorted.json v2_sorted.json" in runner_source, \
        "test_runner.py does not contain the required diff command."
    command_calls = {"system", "popen", "run", "Popen", "call", "check_call", "check_output"}
    assert any(
        isinstance(node, ast.Call) and (
            (isinstance(node.func, ast.Name) and node.func.id in command_calls) or
            (isinstance(node.func, ast.Attribute) and node.func.attr in command_calls)
        )
        for node in ast.walk(tree)
    ), "test_runner.py does not invoke a system command for the required diff."

    assert not port_5000_open(), "Port 5000 was already occupied before verification."
    original_api = open(API_PATH, "rb").read()
    token = secrets.token_hex(12)
    marker = f"/tmp/api_requests_{token}.log"
    pid_file = f"/tmp/api_pid_{token}.txt"
    ids = [secrets.randbelow(1000000) + 1000000 for _ in range(3)]
    records = [
        {"id": ids[0], "name": "dynamic-" + token + "-A", "role": "alpha"},
        {"id": ids[1], "name": "dynamic-" + token + "-B", "role": "beta"},
        {"id": ids[2], "name": "dynamic-" + token + "-C", "role": "gamma"},
    ]
    expected = sorted(records, key=lambda item: item["id"])
    probe_api = f'''import os
from flask import Flask, jsonify
app = Flask(__name__)
open({pid_file!r}, "w").write(str(os.getpid()))
def mark(value):
    with open({marker!r}, "a") as f:
        f.write(value + "\\n")
@app.route("/api/v1/data")
def v1():
    mark("v1")
    return jsonify({[records[2], records[0], records[1]]!r})
@app.route("/api/v2/data")
def v2():
    mark("v2")
    return jsonify({[records[1], records[2], records[0]]!r})
if __name__ == "__main__":
    app.run(port=5000)
'''

    for name in ("v1_sorted.json", "v2_sorted.json", "diff_output.txt"):
        try:
            os.remove(os.path.join(BASE_DIR, name))
        except FileNotFoundError:
            pass

    probe_pid = None
    try:
        with open(API_PATH, "w", encoding="utf-8") as f:
            f.write(probe_api)
        run_runner()
        assert os.path.isfile(marker), "The test runner did not make requests to the API server."
        with open(marker, encoding="utf-8") as f:
            requests_seen = f.read().splitlines()
        assert "v1" in requests_seen, "The test runner did not request /api/v1/data."
        assert "v2" in requests_seen, "The test runner did not request /api/v2/data."
        for filename in ("v1_sorted.json", "v2_sorted.json"):
            with open(os.path.join(BASE_DIR, filename), encoding="utf-8") as f:
                assert json.load(f) == expected, f"{filename} was not generated from the HTTP response and sorted by id."
        assert os.path.isfile(os.path.join(BASE_DIR, "diff_output.txt"))
        assert os.path.getsize(os.path.join(BASE_DIR, "diff_output.txt")) == 0
    finally:
        if os.path.exists(pid_file):
            try:
                with open(pid_file) as f:
                    probe_pid = int(f.read().strip())
            except Exception:
                pass
        if probe_pid:
            try:
                os.kill(probe_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        with open(API_PATH, "wb") as f:
            f.write(original_api)
        for path in (marker, pid_file):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    assert original_api.decode("utf-8") == EXPECTED_API_SOURCE
    for name in ("v1_sorted.json", "v2_sorted.json", "diff_output.txt"):
        try:
            os.remove(os.path.join(BASE_DIR, name))
        except FileNotFoundError:
            pass
    run_runner()


def test_shared_libraries_exist():
    lib_c = os.path.join(BASE_DIR, "libbackend_c.so")
    lib_cpp = os.path.join(BASE_DIR, "libbackend_cpp.so")

    assert os.path.isfile(lib_c), f"Expected shared library {lib_c} does not exist. Did you compile backend_c.c?"
    assert os.path.isfile(lib_cpp), f"Expected shared library {lib_cpp} does not exist. Did you compile backend_cpp.cpp?"


def test_json_files_exist_and_sorted():
    v1_path = os.path.join(BASE_DIR, "v1_sorted.json")
    v2_path = os.path.join(BASE_DIR, "v2_sorted.json")

    assert os.path.isfile(v1_path), f"{v1_path} does not exist."
    assert os.path.isfile(v2_path), f"{v2_path} does not exist."

    with open(v1_path, "r") as f1, open(v2_path, "r") as f2:
        try:
            v1_data = json.load(f1)
            v2_data = json.load(f2)
        except json.JSONDecodeError:
            pytest.fail("One or both of the generated JSON files contain invalid JSON.")

    assert isinstance(v1_data, list), "v1_sorted.json does not contain a JSON array."
    assert isinstance(v2_data, list), "v2_sorted.json does not contain a JSON array."
    v1_ids = [item.get("id") for item in v1_data]
    v2_ids = [item.get("id") for item in v2_data]
    assert v1_ids == sorted(v1_ids), "v1_sorted.json is not sorted by 'id' in ascending order."
    assert v2_ids == sorted(v2_ids), "v2_sorted.json is not sorted by 'id' in ascending order."
    assert v1_data == v2_data, "The parsed JSON contents of v1_sorted.json and v2_sorted.json do not match."
    assert v1_data == EXPECTED_DATA, "The JSON files do not contain the data returned by the supplied backends."
    for item in v1_data:
        assert set(item) == {"id", "name", "role"}, "Each user object must contain id, name, and role."


def test_json_files_strictly_identical():
    v1_path = os.path.join(BASE_DIR, "v1_sorted.json")
    v2_path = os.path.join(BASE_DIR, "v2_sorted.json")
    with open(v1_path, "rb") as f1, open(v2_path, "rb") as f2:
        data1 = f1.read()
        data2 = f2.read()
        assert data1 == data2, "v1_sorted.json and v2_sorted.json are not strictly identical byte-for-byte."
    expected_text = json.dumps(EXPECTED_DATA, indent=2)
    assert data1.decode("utf-8").rstrip("\n") == expected_text, "The JSON files were not saved using an indent of 2 spaces."


def test_diff_output_empty():
    diff_path = os.path.join(BASE_DIR, "diff_output.txt")
    assert os.path.isfile(diff_path), f"{diff_path} does not exist."
    assert os.path.getsize(diff_path) == 0, f"{diff_path} is not empty. The diff command likely found differences."


def test_api_server_terminated():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect(("127.0.0.1", 5000))
        server_running = True
    except ConnectionRefusedError:
        server_running = False
    finally:
        s.close()
    assert not server_running, "The API server on port 5000 is still running. It was not cleanly terminated."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
