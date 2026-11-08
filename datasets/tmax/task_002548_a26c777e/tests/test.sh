#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import socket
import struct
import subprocess
import sys
import tempfile
import time

import pytest

PROJECT = "/home/user/project"
LIBBACKEND = os.path.join(PROJECT, "libbackend.so")
LIBBACKEND_C = os.path.join(PROJECT, "libbackend.c")
EMULATOR = os.path.join(PROJECT, "emulator.py")
TEST_CLIENT = os.path.join(PROJECT, "test_client.py")
REPORT = os.path.join(PROJECT, "test_report.json")


def _defined_dynamic_symbols(path):
    result = subprocess.run(
        ["nm", "-D", "--defined-only", path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    return [line.split()[-1].split("@")[0] for line in result.stdout.splitlines() if line.split()]


def _start_emulator():
    proc = subprocess.Popen(
        [sys.executable, EMULATOR],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return proc


def _connect(proc):
    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            pytest.fail(f"emulator.py exited before accepting a connection: stdout={out!r}, stderr={err!r}")
        try:
            return socket.create_connection(("127.0.0.1", 8888), timeout=1)
        except OSError as exc:
            last_error = exc
            time.sleep(0.05)
    proc.terminate()
    pytest.fail(f"emulator.py did not listen on 127.0.0.1:8888: {last_error}")


def _recv_exact(sock, count):
    data = bytearray()
    while len(data) < count:
        part = sock.recv(count - len(data))
        assert part, f"Connection closed after {len(data)} of {count} expected bytes"
        data.extend(part)
    return bytes(data)


def _exercise_emulator(text):
    proc = _start_emulator()
    try:
        with _connect(proc) as sock:
            payload = text.encode("utf-8")
            frame = struct.pack(">H", len(payload)) + payload
            # Fragment the request so the implementation must actually honor the framing.
            sock.sendall(frame[:1])
            time.sleep(0.01)
            sock.sendall(frame[1:3])
            sock.sendall(frame[3:])
            length = struct.unpack(">H", _recv_exact(sock, 2))[0]
            response = _recv_exact(sock, length)
            assert response.decode("utf-8") == text[::-1]
            assert sock.recv(1) == b"", "Emulator did not close after its one response"
        rc = proc.wait(timeout=5)
        assert rc == 0, f"emulator.py exited with status {rc}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def test_backend_source_and_shared_library_are_valid():
    assert os.path.exists(LIBBACKEND_C), f"File {LIBBACKEND_C} is missing."
    assert os.path.isfile(LIBBACKEND_C), f"Expected {LIBBACKEND_C} to be a file."
    source = open(LIBBACKEND_C, encoding="utf-8").read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(r"\bvoid\s+backend_init\s*\(\s*(?:void\s*)?\)\s*\{\s*\}", source_without_comments), \
        "libbackend.c must define the empty function void backend_init() {}"

    assert open(LIBBACKEND, "rb").read(4) == b"\x7fELF", "libbackend.so is not an ELF shared library"
    assert _defined_dynamic_symbols(LIBBACKEND) == ["backend_init"], \
        "libbackend.so must export exactly the backend_init function"

    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, "libbackend.so")
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", LIBBACKEND_C, "-o", rebuilt],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
        )
        assert result.returncode == 0, f"libbackend.c does not compile as a shared library: {result.stderr}"
        assert _defined_dynamic_symbols(rebuilt) == ["backend_init"]

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    code = (
        "import ctypes; "
        f"b=ctypes.CDLL({LIBBACKEND!r}); b.backend_init(); "
        f"d=ctypes.CDLL({os.path.join(PROJECT, 'libdata.so')!r}); d.init()"
    )
    result = subprocess.run(
        [sys.executable, "-c", code], env=env, cwd=PROJECT,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
    )
    assert result.returncode == 0, f"The shared libraries could not be loaded and called: {result.stderr}"


def test_libbackend_so_exists():
    path = "/home/user/project/libbackend.so"
    assert os.path.exists(path), f"File {path} is missing. The dummy library was not compiled."
    assert os.path.isfile(path), f"Expected {path} to be a file."


def test_emulator_implements_protocol_and_reversal():
    assert os.path.isfile(EMULATOR), f"File {EMULATOR} is missing."
    ast.parse(open(EMULATOR, encoding="utf-8").read(), filename=EMULATOR)
    challenge = "Verifier-" + os.urandom(12).hex() + "-λ🙂"
    _exercise_emulator(challenge)
    _exercise_emulator("SystemsEngineering")


def test_required_pytest_fixture_and_test_exist():
    assert os.path.isfile(TEST_CLIENT), f"File {TEST_CLIENT} is missing."
    source = open(TEST_CLIENT, encoding="utf-8").read()
    tree = ast.parse(source, filename=TEST_CLIENT)
    functions = {node.name: node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    assert "emulator_service" in functions, "test_client.py must define the emulator_service fixture"
    fixture = functions["emulator_service"]
    assert any(
        (isinstance(d, ast.Name) and d.id == "fixture") or
        (isinstance(d, ast.Attribute) and d.attr == "fixture") or
        (isinstance(d, ast.Call) and ((isinstance(d.func, ast.Name) and d.func.id == "fixture") or
                                     (isinstance(d.func, ast.Attribute) and d.func.attr == "fixture")))
        for d in fixture.decorator_list
    ), "emulator_service must be decorated as a pytest fixture"
    fixture_text = ast.get_source_segment(source, fixture) or ""
    assert "emulator.py" in fixture_text and ("Popen" in fixture_text or "subprocess" in fixture_text), \
        "emulator_service must spawn emulator.py as a subprocess"

    assert "test_data_processing" in functions, "test_client.py must define test_data_processing"
    test_node = functions["test_data_processing"]
    assert "emulator_service" in [arg.arg for arg in test_node.args.args], \
        "test_data_processing must use the emulator_service fixture"
    constants = {node.value for node in ast.walk(test_node) if isinstance(node, ast.Constant) and isinstance(node.value, str)}
    assert "SystemsEngineering" in constants and "gnireenignEsmetsyS" in constants, \
        "test_data_processing must test the required input and expected response"
    assert any(isinstance(node, ast.Assert) for node in ast.walk(test_node)), \
        "test_data_processing must contain an assertion"
    assert any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "process_data"
               for node in ast.walk(test_node)), \
        "test_data_processing must call data_client.process_data"


def test_data_client_and_required_pytest_test_run_successfully():
    # Independently exercise data_client against the submitted emulator on an unpredictable input.
    challenge = "Client-" + os.urandom(10).hex() + "-Ω"
    proc = _start_emulator()
    try:
        # Wait without consuming the emulator's single accepted connection.
        time.sleep(0.15)
        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = PROJECT + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
        code = "import json,sys,data_client; print(json.dumps(data_client.process_data(sys.argv[1])))"
        result = subprocess.run(
            [sys.executable, "-c", code, challenge], cwd=PROJECT, env=env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
        )
        assert result.returncode == 0, f"data_client.process_data failed: {result.stderr}"
        assert json.loads(result.stdout.strip()) == challenge[::-1]
        assert proc.wait(timeout=5) == 0
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=2)

    # Run the required test through the submitted pipeline and create a genuine fresh report.
    if os.path.exists(REPORT):
        os.remove(REPORT)
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "test_client.py::test_data_processing",
         "--json-report", "--json-report-file=" + REPORT, "-q"],
        cwd=PROJECT, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
    )
    assert result.returncode == 0, f"The required pytest test failed:\n{result.stdout}"


def test_test_report_json_exists():
    path = "/home/user/project/test_report.json"
    assert os.path.exists(path), f"File {path} is missing. Did you run pytest with JSON report generation?"
    assert os.path.isfile(path), f"Expected {path} to be a file."


def test_test_report_passed():
    path = "/home/user/project/test_report.json"
    if not os.path.exists(path):
        pytest.fail(f"Cannot check test results because {path} is missing.")

    try:
        with open(path, "r") as f:
            data = json.load(f)
    except Exception as e:
        pytest.fail(f"Could not read or parse {path} as JSON: {e}")

    summary = data.get("summary", {})
    passed = summary.get("passed", 0)
    assert passed >= 1, f"Expected at least 1 passed test in the summary, but got {passed}. Full summary: {summary}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
