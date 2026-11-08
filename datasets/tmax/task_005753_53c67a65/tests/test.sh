#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import codecs
import ctypes
import json
import os
import secrets
import shutil
import string
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

APP = "/home/user/legacy_app"
SO_PATH = os.path.join(APP, "libprocessor.so")


def rot13(value):
    return codecs.encode(value, "rot_13")


def run_wrapper(value):
    program = r'''
import json
import sys
sys.path.insert(0, %r)
import wrapper
value = json.loads(sys.argv[1])
result = wrapper.transform(value)
assert type(result) is str, "transform() must return a Python 3 str"
print("WRAPPER_RESULT=" + json.dumps(result, ensure_ascii=False))
''' % APP
    completed = subprocess.run(
        [sys.executable, "-c", program, json.dumps(value, ensure_ascii=False)],
        cwd=APP,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        "wrapper.transform failed under Python 3:\n"
        + completed.stdout + completed.stderr
    )
    lines = [line for line in completed.stdout.splitlines()
             if line.startswith("WRAPPER_RESULT=")]
    assert lines, "Could not read wrapper.transform result."
    return json.loads(lines[-1].split("=", 1)[1])


def test_makefile_and_shared_library():
    if os.path.exists(SO_PATH):
        os.remove(SO_PATH)

    completed = subprocess.run(
        ["make"], cwd=APP, text=True, capture_output=True, timeout=30
    )
    assert completed.returncode == 0, (
        "Running make failed:\n" + completed.stdout + completed.stderr
    )
    assert os.path.isfile(SO_PATH), "libprocessor.so was not built."

    try:
        lib = ctypes.CDLL(SO_PATH)
    except Exception as e:
        assert False, (
            f"Failed to load libprocessor.so as a shared library: {e}. "
            "Make sure the Makefile uses -shared and -fPIC."
        )

    assert hasattr(lib, "process_string"), (
        "process_string symbol not found in libprocessor.so."
    )
    process = lib.process_string
    process.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    process.restype = None

    cases = [b"", b"Python2to3", b"Hello, World! 123"]
    alphabet = string.ascii_letters + string.digits + "-_.!"
    for _ in range(6):
        cases.append("".join(secrets.choice(alphabet) for _ in range(37)).encode())

    for raw in cases:
        output = ctypes.create_string_buffer(len(raw) + 1)
        process(raw, output)
        expected = rot13(raw.decode("ascii")).encode("ascii")
        assert output.value == expected, (
            f"process_string({raw!r}) returned {output.value!r}, expected {expected!r}"
        )


def test_python3_wrapper_and_ctypes_abi():
    cases = [
        "",
        "Python2to3",
        "Hello, World! 123",
        "café Ω — Привет",
    ]
    alphabet = string.ascii_letters + string.digits + " _-!?"
    for _ in range(6):
        cases.append("".join(secrets.choice(alphabet) for _ in range(41)))

    for value in cases:
        assert run_wrapper(value) == rot13(value)

    # Replace the library briefly with a same-ABI probe whose behavior differs
    # from ROT13. This proves wrapper.transform actually crosses the ctypes ABI.
    probe_input = "".join(secrets.choice(string.ascii_letters + string.digits)
                          for _ in range(31))
    with tempfile.TemporaryDirectory() as tempdir:
        backup = os.path.join(tempdir, "libprocessor.original.so")
        probe_c = os.path.join(tempdir, "probe.c")
        probe_so = os.path.join(tempdir, "libprocessor.probe.so")
        shutil.copy2(SO_PATH, backup)
        with open(probe_c, "w", encoding="utf-8") as f:
            f.write(r'''
#include <string.h>
void process_string(const char *input, char *output) {
    size_t n = strlen(input);
    for (size_t i = 0; i < n; ++i) output[i] = input[n - i - 1];
    output[n] = '\0';
}
''')
        built = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", probe_so, probe_c],
            text=True, capture_output=True, timeout=30
        )
        assert built.returncode == 0, built.stdout + built.stderr
        try:
            os.replace(probe_so, SO_PATH)
            assert run_wrapper(probe_input) == probe_input[::-1], (
                "wrapper.transform does not appear to call libprocessor.so's "
                "process_string function through ctypes."
            )
        finally:
            os.replace(backup, SO_PATH)


def test_api_imports_and_calls_wrapper_transform():
    api_path = os.path.join(APP, "api.py")
    assert os.path.isfile(api_path), "api.py is missing."
    with open(api_path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=api_path)

    aliases = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == "wrapper":
                    aliases[item.asname or "wrapper"] = "wrapper"
        elif isinstance(node, ast.ImportFrom) and node.module == "wrapper":
            for item in node.names:
                if item.name == "transform":
                    aliases[item.asname or "transform"] = "wrapper.transform"

    uses_transform = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            uses_transform |= aliases.get(node.func.id) == "wrapper.transform"
        elif isinstance(node.func, ast.Attribute) and node.func.attr == "transform":
            if isinstance(node.func.value, ast.Name):
                uses_transform |= aliases.get(node.func.value.id) == "wrapper"

    assert uses_transform, "api.py must import and call wrapper.transform."


def test_api_pid_file():
    pid_file = "/home/user/api.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} is missing."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), "PID file does not contain a valid integer."
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running."


def request_transform(value):
    query = urllib.parse.urlencode({"text": value})
    url = "http://127.0.0.1:8000/api/transform?" + query
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            status = response.getcode()
            content_type = response.headers.get("Content-Type", "")
            data = response.read().decode("utf-8")
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to API or API returned an error: {e}"

    assert status == 200, f"Expected HTTP 200, got {status}"
    assert "application/json" in content_type, (
        f"Expected Content-Type application/json, got {content_type}"
    )
    try:
        json_data = json.loads(data)
    except json.JSONDecodeError:
        assert False, f"API response is not valid JSON: {data}"

    assert "result" in json_data, "JSON response is missing 'result' key."
    assert json_data == {"result": rot13(value)}, (
        f"Expected {{'result': {rot13(value)!r}}}, got {json_data!r}"
    )


def test_rest_api_endpoint():
    request_transform("Python2to3")
    request_transform("")
    request_transform("spaces & punctuation!? / +")
    request_transform("café Ω")

    alphabet = string.ascii_letters + string.digits + " _-!?"
    for _ in range(8):
        value = "".join(secrets.choice(alphabet) for _ in range(43))
        request_transform(value)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
