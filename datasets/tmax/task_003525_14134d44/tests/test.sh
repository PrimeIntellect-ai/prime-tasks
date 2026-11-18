#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import secrets
import subprocess
import sys

import pytest

BAD_LINE = '{"status": "error", "timestamp": "2023-10-12T10:00:00Z", "data": corrupted}'

SHELL_LOADER = r'''
unset LOG_REGION
for f in /etc/environment /etc/profile /etc/profile.d/*.sh /home/user/.profile /home/user/.bash_profile /home/user/.bash_login /home/user/.bashrc; do
    [ -f "$f" ] && . "$f"
done
if [ "${LOG_REGION:-}" != "us-east-1" ]; then
    echo "LOG_REGION was not persistently configured for user" >&2
    exit 41
fi
export LOG_REGION
exec "$@"
'''


def run_with_repaired_environment(args):
    return subprocess.run(
        [
            "runuser", "-u", "user", "--", "env", "HOME=/home/user",
            "bash", "-c", SHELL_LOADER, "verifier-shell", *args,
        ],
        capture_output=True,
        text=True,
    )


def load_process_logs():
    # The persistent environment repair is independently checked below. Use the
    # validated value while exercising the module in this pytest process.
    env_check = run_with_repaired_environment([
        sys.executable, "-c",
        "import os, process_logs; assert os.environ['LOG_REGION'] == 'us-east-1'",
    ])
    assert env_check.returncode == 0, (
        "LOG_REGION is not persistently repaired for the user, or process_logs "
        f"cannot import with that environment.\nSTDOUT:\n{env_check.stdout}\nSTDERR:\n{env_check.stderr}"
    )

    old = os.environ.get("LOG_REGION")
    os.environ["LOG_REGION"] = "us-east-1"
    try:
        spec = importlib.util.spec_from_file_location("process_logs", "/home/user/process_logs.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        if old is None:
            os.environ.pop("LOG_REGION", None)
        else:
            os.environ["LOG_REGION"] = old


def test_environment_repair():
    result = run_with_repaired_environment([
        sys.executable, "-c",
        "import os, process_logs; assert os.environ['LOG_REGION'] == 'us-east-1'",
    ])
    assert result.returncode == 0, (
        "The required LOG_REGION environment repair is missing or ineffective.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_bad_log_line_file():
    bad_log_path = "/home/user/bad_log_line.txt"
    assert os.path.isfile(bad_log_path), f"File {bad_log_path} does not exist."

    with open(bad_log_path, "r") as f:
        content = f.read().strip()

    expected_line = BAD_LINE
    assert content == expected_line, (
        f"Content of {bad_log_path} is incorrect. Expected: {expected_line}, Got: {content}"
    )

    # Confirm that the submitted line is the unique malformed line in the supplied log.
    malformed = []
    with open("/home/user/server.log", "r") as f:
        for number, line in enumerate(f, 1):
            try:
                json.loads(line)
            except json.JSONDecodeError:
                malformed.append((number, line.rstrip("\n")))
    assert malformed == [(743, content)], f"The isolated line is not the unique malformed log line: {malformed}"


def assert_log_format_error(process_logs, value):
    try:
        process_logs.process_line(value)
    except Exception as exc:
        assert type(exc) is process_logs.LogFormatError, (
            f"Expected LogFormatError, got {type(exc).__name__}: {exc}"
        )
        assert str(exc) == "Invalid log format", (
            f"Expected message 'Invalid log format', got {str(exc)!r}"
        )
    else:
        pytest.fail("process_line did not raise an exception for invalid JSON")


def test_process_logs_patched():
    process_logs_path = "/home/user/process_logs.py"
    assert os.path.isfile(process_logs_path), f"File {process_logs_path} does not exist."

    process_logs = load_process_logs()
    assert hasattr(process_logs, "process_line"), "process_line function is missing"
    assert hasattr(process_logs, "LogFormatError"), "LogFormatError class is missing"

    # Preserve the original exact-line assertion.
    assert_log_format_error(process_logs, BAD_LINE)

    # Exercise independently generated malformed JSON so the implementation
    # cannot pass by special-casing the known corrupt line.
    token = secrets.token_hex(16)
    malformed_inputs = [
        '{"status":"ok","data": broken_' + token + '}',
        '{"status":"' + token,
        '["' + token + '",]',
        '{"' + token + '": true,, "x": 1}',
        json.dumps({"status": token, "nested": [1, 2, 3]})[:-1],
    ]
    for value in malformed_inputs:
        with pytest.raises(json.JSONDecodeError):
            json.loads(value)
        assert_log_format_error(process_logs, value)

    # Valid JSON behavior must remain intact.
    assert process_logs.process_line(json.dumps({"status": token})) == token
    assert process_logs.process_line(json.dumps({"other": token})) == "unknown"

    # Only JSONDecodeError should be translated; unrelated input errors must not
    # be swallowed by a broad exception handler.
    with pytest.raises(TypeError):
        process_logs.process_line(None)


def test_regression_test_passes_and_is_meaningful():
    path = "/home/user/test_regression.py"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        tree = ast.parse(f.read(), filename=path)

    process_names = set()
    error_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "process_logs":
            for alias in node.names:
                if alias.name == "process_line":
                    process_names.add(alias.asname or alias.name)
                elif alias.name == "LogFormatError":
                    error_names.add(alias.asname or alias.name)
    assert process_names and error_names, (
        "test_regression.py must import process_line and LogFormatError from process_logs"
    )

    methods = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "test_corrupt_log_line"
    ]
    assert methods, "Missing unittest method test_corrupt_log_line"
    method = methods[0]
    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id in process_names
        for node in ast.walk(method)
    ), "test_corrupt_log_line does not call the imported process_line"
    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in {"assertRaises", "assertRaisesRegex"}
        and node.args
        and isinstance(node.args[0], ast.Name)
        and node.args[0].id in error_names
        for node in ast.walk(method)
    ), "test_corrupt_log_line must use unittest assertRaises for LogFormatError"

    # Run the requested command against the real implementation.
    result = run_with_repaired_environment([
        sys.executable, "-m", "unittest", path,
    ])
    assert result.returncode == 0, (
        f"Regression test failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )

    # Re-run under an instrumented process_logs module. This proves the named
    # unittest actually invokes process_line with the exact isolated bad line.
    harness = r'''
import importlib.util
import sys
import types
import unittest

BAD = '{"status": "error", "timestamp": "2023-10-12T10:00:00Z", "data": corrupted}'
calls = []
fake = types.ModuleType("process_logs")
class LogFormatError(Exception):
    pass
def process_line(value):
    calls.append(value)
    raise LogFormatError("Invalid log format")
fake.LogFormatError = LogFormatError
fake.process_line = process_line
sys.modules["process_logs"] = fake

spec = importlib.util.spec_from_file_location("submitted_regression", "/home/user/test_regression.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
suite = unittest.defaultTestLoader.loadTestsFromModule(module)

def flatten(s):
    for item in s:
        if isinstance(item, unittest.TestSuite):
            yield from flatten(item)
        else:
            yield item

selected = [t for t in flatten(suite) if t.id().endswith(".test_corrupt_log_line")]
if not selected:
    raise SystemExit("No discoverable unittest named test_corrupt_log_line")
result = unittest.TestResult()
unittest.TestSuite(selected).run(result)
if not result.wasSuccessful():
    raise SystemExit("test_corrupt_log_line did not pass under instrumentation: " + repr(result.errors + result.failures))
if BAD not in calls:
    raise SystemExit("test_corrupt_log_line did not pass the exact bad line to process_line")
'''
    instrumented = subprocess.run(
        [sys.executable, "-c", harness], capture_output=True, text=True
    )
    assert instrumented.returncode == 0, (
        "Regression test is empty, irrelevant, or does not test the exact corrupt line.\n"
        f"STDOUT:\n{instrumented.stdout}\nSTDERR:\n{instrumented.stderr}"
    )
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
