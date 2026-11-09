#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import contextlib
import ctypes
import json
import os
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

import pytest
import websockets

BASE_DIR = "/home/user/ws_calc"
LIB_PATH = os.path.join(BASE_DIR, "build", "libcalc.so")
SERVER_PATH = os.path.join(BASE_DIR, "server.py")
TEST_PATH = os.path.join(BASE_DIR, "tests", "test_ws.py")


def stop_existing_servers():
    subprocess.run(
        ["pkill", "-f", "[s]erver.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.2)


async def wait_for_server(proc, timeout=10):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"server.py exited during startup with status {proc.returncode}")
        try:
            async with websockets.connect("ws://localhost:8765"):
                return
        except Exception as exc:
            last_error = exc
            await asyncio.sleep(0.1)
    pytest.fail(f"server.py did not accept WebSocket connections: {last_error}")


@contextlib.contextmanager
def running_server():
    stop_existing_servers()
    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH],
        cwd=BASE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        asyncio.run(wait_for_server(proc))
        yield proc
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        stop_existing_servers()


def parse_junit(xml_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except ET.ParseError as e:
        pytest.fail(f"Failed to parse {xml_path} as XML: {e}")

    if root.tag == "testsuites":
        testsuites = root.findall("testsuite")
    elif root.tag == "testsuite":
        testsuites = [root]
    else:
        pytest.fail(f"Unexpected root tag '{root.tag}' in {xml_path}")

    totals = {"tests": 0, "failures": 0, "errors": 0}
    for ts in testsuites:
        for key in totals:
            totals[key] += int(ts.attrib.get(key, 0))
    return totals


def test_shared_library_exists():
    """Verify that the shared library was built and exists at the expected path."""
    assert os.path.isfile(LIB_PATH), f"Shared library not found at {LIB_PATH}. Did you build it?"


def test_process_data_exported_c_linkage():
    """Verify that process_data is exported with C linkage (unmangled)."""
    assert os.path.isfile(LIB_PATH), "Shared library is missing."

    try:
        output = subprocess.check_output(["nm", "-D", LIB_PATH], text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run nm on {LIB_PATH}: {e}")
    except FileNotFoundError:
        pytest.fail("The 'nm' command is not available.")

    lines = output.splitlines()
    found = False
    for line in lines:
        parts = line.split()
        if len(parts) >= 3 and parts[1] == "T" and parts[2] == "process_data":
            found = True
            break

    assert found, "Function 'process_data' is not exported with C linkage (unmangled). Did you forget 'extern \"C\"'?"


def test_process_data_actually_doubles_values():
    """Load and invoke the submitted shared library instead of trusting its symbol table."""
    lib = ctypes.CDLL(LIB_PATH)
    func = lib.process_data
    func.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    func.restype = None

    inputs = [-8.125, 0.0, 1.75, 19.0625]
    array = (ctypes.c_double * len(inputs))(*inputs)
    func(array, len(inputs))
    assert list(array) == pytest.approx([value * 2.0 for value in inputs])


def test_test_results_xml_exists():
    """Verify that the pytest JUnit XML report was generated."""
    xml_path = os.path.join(BASE_DIR, "test_results.xml")
    assert os.path.isfile(xml_path), f"Test results XML not found at {xml_path}. Did you run pytest with --junitxml?"


def test_test_results_xml_passed():
    """Verify that the test suite ran and passed according to the XML report."""
    xml_path = os.path.join(BASE_DIR, "test_results.xml")
    assert os.path.isfile(xml_path), "Test results XML is missing."
    totals = parse_junit(xml_path)
    assert totals["tests"] > 0, "No tests were reported as run in the XML results."
    assert totals["failures"] == 0, f"Expected 0 test failures, but found {totals['failures']}."
    assert totals["errors"] == 0, f"Expected 0 test errors, but found {totals['errors']}."


def test_test_ws_py_exists():
    """Verify that the test integration file was created."""
    assert os.path.isfile(TEST_PATH), f"Integration test file not found at {TEST_PATH}."


def test_websocket_server_computes_real_responses():
    """Start the submitted server and exercise both the required and derived requests."""
    async def exercise():
        cases = [
            [1.5, 2.5, 3.5],
            [-4.25, 0.125, 11.0, 20.75],
        ]
        async with websockets.connect("ws://localhost:8765") as websocket:
            for values in cases:
                await websocket.send(json.dumps({"op": "compute", "data": values}))
                response = json.loads(await asyncio.wait_for(websocket.recv(), timeout=5))
                assert response == {"result": [value * 2.0 for value in values]}

    with running_server() as proc:
        asyncio.run(exercise())
        assert proc.poll() is None, "server.py exited while serving requests"


def test_submitted_integration_test_has_required_scenario():
    """Ensure test_ws.py contains an asynchronous WebSocket pytest scenario and required values."""
    source = open(TEST_PATH, encoding="utf-8").read()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f"tests/test_ws.py is not valid Python: {exc}")

    constants = {node.value for node in ast.walk(tree) if isinstance(node, ast.Constant)}
    lowered = source.lower()
    assert "pytest" in lowered and "websocket" in lowered, "test_ws.py must use pytest and websockets"
    assert any(isinstance(node, ast.AsyncFunctionDef) for node in ast.walk(tree)), "Integration test must be asynchronous"
    assert "compute" in constants, "Integration test does not contain the required compute operation"
    for value in (1.5, 2.5, 3.5, 3.0, 5.0, 7.0):
        assert value in constants, f"Integration test is missing required value {value}"
    assert "ws://localhost:8765" in constants, "Integration test must connect to ws://localhost:8765"


def test_submitted_integration_test_really_runs_and_passes():
    """Run test_ws.py now and validate a fresh JUnit report rather than trusting the submitted report."""
    report = "/tmp/submitted_test_results.xml"
    if os.path.exists(report):
        os.unlink(report)

    stop_existing_servers()
    command = [sys.executable, "-m", "pytest", TEST_PATH, "-q", f"--junitxml={report}"]
    try:
        first = subprocess.run(command, cwd=BASE_DIR, timeout=30, check=False)
    except subprocess.TimeoutExpired:
        first = None

    if first is None or first.returncode != 0:
        if os.path.exists(report):
            os.unlink(report)
        with running_server():
            try:
                result = subprocess.run(command, cwd=BASE_DIR, timeout=30, check=False)
            except subprocess.TimeoutExpired:
                pytest.fail("tests/test_ws.py timed out")
    else:
        result = first

    assert result.returncode == 0, "The submitted tests/test_ws.py did not pass when executed"
    assert os.path.isfile(report), "Executing tests/test_ws.py did not produce a fresh JUnit report"
    totals = parse_junit(report)
    assert totals["tests"] > 0, "The submitted test file did not run any tests"
    assert totals["failures"] == 0 and totals["errors"] == 0, "The freshly executed integration test did not pass"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
