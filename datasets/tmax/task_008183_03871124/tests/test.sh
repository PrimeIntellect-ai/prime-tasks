#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import binascii
import importlib.util
import marshal
import os
import re
import subprocess
import sys
import tempfile
import types

MONITOR_PATH = "/home/user/monitor.pyc"
PAYLOAD_PATH = "/home/user/payload.txt"
SCRIPT_PATH = "/home/user/regression_test.py"
EXPECTED_PAYLOAD = b"HEARTBEAT||0x00|PANIC"
EXPECTED_SOURCE = (
    'def process_heartbeat(payload):\n'
    '    if payload.startswith(b"HEARTBEAT"):\n'
    '        parts = payload.split(b"|")\n'
    '        if len(parts) == 4:\n'
    '            if parts[2] == b"0x00":\n'
    '                if parts[3] == b"PANIC":\n'
    '                    raise RuntimeError("Panic on unwrap()")\n'
    '    return True\n'
)


def assert_monitor_integrity():
    assert os.path.isfile(MONITOR_PATH), f"Expected compiled module at {MONITOR_PATH}."
    with open(MONITOR_PATH, "rb") as f:
        pyc = f.read()

    assert len(pyc) > 16, "monitor.pyc is truncated."
    assert pyc[:4] == importlib.util.MAGIC_NUMBER, "monitor.pyc has an invalid Python magic number."

    try:
        actual_code = marshal.loads(pyc[16:])
    except Exception as e:
        raise AssertionError(f"monitor.pyc does not contain a valid code object: {e}")

    assert isinstance(actual_code, types.CodeType), "monitor.pyc payload is not a module code object."
    expected_code = compile(EXPECTED_SOURCE, "/home/user/monitor.py", "exec")
    assert marshal.dumps(actual_code) == marshal.dumps(expected_code), (
        "The supplied monitor.pyc was modified or replaced."
    )


def load_monitor():
    assert_monitor_integrity()
    spec = importlib.util.spec_from_file_location("monitor", MONITOR_PATH)
    assert spec is not None and spec.loader is not None
    monitor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(monitor)
    return monitor


def test_payload_txt_exists_and_triggers_crash():
    assert os.path.isfile(PAYLOAD_PATH), f"Expected payload file at {PAYLOAD_PATH} does not exist."

    with open(PAYLOAD_PATH, "r") as f:
        hex_str = f.read().strip()

    assert hex_str, "payload.txt is empty."
    assert re.fullmatch(r"[0-9a-fA-F]+", hex_str), (
        "payload.txt must contain one continuous hexadecimal string."
    )
    assert len(hex_str) % 2 == 0, "payload.txt contains an incomplete hexadecimal byte."

    try:
        payload = binascii.unhexlify(hex_str)
    except Exception as e:
        assert False, f"Failed to decode hex string in payload.txt: {e}"

    assert payload == EXPECTED_PAYLOAD, (
        "The payload is not the minimal byte sequence satisfying every branch condition."
    )

    monitor = load_monitor()

    exception_triggered = False
    try:
        monitor.process_heartbeat(payload)
    except RuntimeError as e:
        if str(e) == "Panic on unwrap()":
            exception_triggered = True
        else:
            assert False, f"Triggered RuntimeError but with unexpected message: {e}"
    except Exception as e:
        assert False, f"Triggered unexpected exception: {e}"

    assert exception_triggered, "The payload in payload.txt did not trigger the expected RuntimeError."


def test_regression_test_script():
    assert os.path.isfile(SCRIPT_PATH), f"Expected regression test script at {SCRIPT_PATH} does not exist."
    assert_monitor_integrity()

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        script_source = f.read()
    try:
        tree = ast.parse(script_source, filename=SCRIPT_PATH)
    except SyntaxError as e:
        raise AssertionError(f"regression_test.py is not valid Python: {e}")

    imports_monitor = any(
        (isinstance(node, ast.Import) and any(alias.name == "monitor" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "monitor")
        for node in ast.walk(tree)
    )
    assert imports_monitor, "regression_test.py must import the monitor module."

    # Preserve the original end-to-end execution assertion.
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"regression_test.py failed with return code {result.returncode}. Stderr: {result.stderr}"
    )
    assert "REPRODUCED" in result.stdout, (
        "regression_test.py did not print 'REPRODUCED' to standard output."
    )

    # Re-run with an instrumented monitor. Its function records the argument and
    # always raises RuntimeError, proving the script actually calls it with the
    # minimal payload and handles that exception rather than merely printing text.
    harness_source = f'''\
import contextlib
import io
import runpy
import sys
import types

expected = {EXPECTED_PAYLOAD!r}
called = []
monitor = types.ModuleType("monitor")

def process_heartbeat(payload):
    if not isinstance(payload, bytes):
        raise AssertionError("process_heartbeat must be called with bytes")
    if payload != expected:
        raise AssertionError("process_heartbeat was not called with the minimal payload")
    called.append(payload)
    raise RuntimeError("Panic on unwrap()")

monitor.process_heartbeat = process_heartbeat
sys.modules["monitor"] = monitor
out = io.StringIO()
with contextlib.redirect_stdout(out):
    runpy.run_path(sys.argv[1], run_name="__main__")
if not called:
    raise AssertionError("regression_test.py never called monitor.process_heartbeat")
if "REPRODUCED" not in out.getvalue():
    raise AssertionError("regression_test.py did not print REPRODUCED after handling RuntimeError")
print(out.getvalue(), end="")
'''
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as harness:
        harness.write(harness_source)
        harness_path = harness.name
    try:
        traced = subprocess.run(
            [sys.executable, "-I", harness_path, SCRIPT_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=10,
        )
    finally:
        os.unlink(harness_path)

    assert traced.returncode == 0, (
        "regression_test.py did not import and call monitor.process_heartbeat with the minimal "
        f"payload while catching RuntimeError. Stderr: {traced.stderr}"
    )
    assert "REPRODUCED" in traced.stdout
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
