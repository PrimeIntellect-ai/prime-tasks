#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import textwrap
import pytest

SCRIPT_PATH = "/home/user/edge_monitor.py"
LOG_DIR = "/home/user/edge_logs"


def test_script_exists():
    """Check if the edge_monitor.py script exists and is a file."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist or is not a file."


def test_log_directory_exists():
    """Check if the edge_logs directory was created."""
    assert os.path.isdir(LOG_DIR), f"Directory {LOG_DIR} does not exist."


def test_log_files_exist():
    """Check if the log rotation created the expected files."""
    expected_files = ["status.log", "status.log.1", "status.log.2", "status.log.3"]
    for filename in expected_files:
        filepath = os.path.join(LOG_DIR, filename)
        assert os.path.isfile(filepath), f"Log file {filepath} is missing. Log rotation may not be configured correctly."


def test_log_content():
    """Check if the current log file contains the expected output."""
    log_path = os.path.join(LOG_DIR, "status.log")
    with open(log_path, "r") as f:
        content = f.read()
    assert "Ping successful" in content, f"Expected 'Ping successful' in {log_path}, but got: {content}"


def test_container_stopped():
    """Check that the apptainer instance 'iot_worker' is stopped."""
    result = subprocess.run(
        ["apptainer", "instance", "list"],
        capture_output=True,
        text=True,
        check=False
    )
    assert "iot_worker" not in result.stdout, "Apptainer instance 'iot_worker' is still running. Cleanup failed."


def _constant_int(node):
    return node.value if isinstance(node, ast.Constant) and isinstance(node.value, int) else None


def test_script_structure():
    """Require the requested subprocess, loop, rotating handler, and raw formatter constructs."""
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    imports_subprocess = any(
        (isinstance(n, ast.Import) and any(a.name == "subprocess" for a in n.names)) or
        (isinstance(n, ast.ImportFrom) and n.module == "subprocess")
        for n in ast.walk(tree)
    )
    assert imports_subprocess, "The script must use Python's subprocess module."

    subprocess_calls = [
        n for n in ast.walk(tree)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
        and isinstance(n.func.value, ast.Name) and n.func.value.id == "subprocess"
    ]
    assert subprocess_calls, "No subprocess command execution was found."

    handler_ok = False
    formatter_ok = False
    exact_loop = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            name = node.func.attr if isinstance(node.func, ast.Attribute) else (node.func.id if isinstance(node.func, ast.Name) else "")
            if name == "RotatingFileHandler":
                kwargs = {kw.arg: kw.value for kw in node.keywords if kw.arg}
                if _constant_int(kwargs.get("maxBytes")) == 40 and _constant_int(kwargs.get("backupCount")) == 3:
                    handler_ok = True
            if name == "Formatter":
                values = list(node.args) + [kw.value for kw in node.keywords if kw.arg == "fmt"]
                if any(isinstance(v, ast.Constant) and v.value == "%(message)s" for v in values):
                    formatter_ok = True
        if isinstance(node, ast.For) and isinstance(node.iter, ast.Call):
            call = node.iter
            if isinstance(call.func, ast.Name) and call.func.id == "range" and not call.keywords:
                vals = [_constant_int(a) for a in call.args]
                if all(v is not None for v in vals) and 1 <= len(vals) <= 3:
                    try:
                        if len(range(*vals)) == 8:
                            exact_loop = True
                    except ValueError:
                        pass

    assert handler_ok, "RotatingFileHandler must use maxBytes=40 and backupCount=3."
    assert formatter_ok, "The log formatter must be exactly %(message)s."
    assert exact_loop, "The diagnostic loop must iterate exactly 8 times."


def test_execute_script_and_validate_behavior(tmp_path):
    """Execute the submitted artifact against a controlled Apptainer command."""
    fake_dir = tmp_path / "bin"
    fake_dir.mkdir()
    trace_path = tmp_path / "trace.log"
    state_path = tmp_path / "running"
    count_path = tmp_path / "count"
    fake = fake_dir / "apptainer"
    fake.write_text(textwrap.dedent(r'''#!/usr/bin/env python3
import json
import os
import sys
import time

args = sys.argv[1:]
trace = os.environ["EDGE_TEST_TRACE"]
state = os.environ["EDGE_TEST_STATE"]
count_file = os.environ["EDGE_TEST_COUNT"]

def event(kind, code=None):
    with open(trace, "a", encoding="utf-8") as f:
        row = [kind, args]
        if code is not None:
            row.append(code)
        f.write(json.dumps(row) + "\n")

def finish(code):
    event("END", code)
    sys.exit(code)

event("BEGIN")
time.sleep(0.05)

if args == ["instance", "start", "docker://alpine:latest", "iot_worker"]:
    if os.path.exists(state):
        finish(90)
    open(state, "w").close()
    with open(count_file, "w") as f:
        f.write("0")
    print("controlled start diagnostic", file=sys.stderr)
    finish(0)

if args == ["exec", "instance://iot_worker", "ping", "-c", "1", "127.0.0.1"]:
    if not os.path.exists(state):
        finish(91)
    try:
        with open(count_file) as f:
            count = int(f.read()) + 1
    except Exception:
        finish(92)
    with open(count_file, "w") as f:
        f.write(str(count))
    print("controlled ping diagnostic", file=sys.stderr)
    finish(0 if count % 2 == 1 else 1)

if args == ["instance", "stop", "iot_worker"]:
    try:
        with open(count_file) as f:
            count = int(f.read())
    except Exception:
        count = -1
    if not os.path.exists(state) or count != 8:
        finish(93)
    os.unlink(state)
    print("controlled stop diagnostic", file=sys.stderr)
    finish(0)

finish(94)
'''), encoding="utf-8")
    fake.chmod(0o755)

    os.makedirs(LOG_DIR, exist_ok=True)
    for name in os.listdir(LOG_DIR):
        if name == "status.log" or name.startswith("status.log."):
            path = os.path.join(LOG_DIR, name)
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)

    env = os.environ.copy()
    env["PATH"] = str(fake_dir) + os.pathsep + env.get("PATH", "")
    env["EDGE_TEST_TRACE"] = str(trace_path)
    env["EDGE_TEST_STATE"] = str(state_path)
    env["EDGE_TEST_COUNT"] = str(count_path)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, f"Script failed under controlled diagnostics. stdout={result.stdout!r}, stderr={result.stderr!r}"
    assert not state_path.exists(), "The controlled iot_worker instance was not stopped."

    start = ["instance", "start", "docker://alpine:latest", "iot_worker"]
    ping = ["exec", "instance://iot_worker", "ping", "-c", "1", "127.0.0.1"]
    stop = ["instance", "stop", "iot_worker"]
    expected = [["BEGIN", start], ["END", start, 0]]
    for i in range(8):
        code = 0 if i % 2 == 0 else 1
        expected.extend([["BEGIN", ping], ["END", ping, code]])
    expected.extend([["BEGIN", stop], ["END", stop, 0]])

    with open(trace_path, "r", encoding="utf-8") as f:
        actual = [json.loads(line) for line in f if line.strip()]
    assert actual == expected, "Commands must run synchronously in start, eight pings, stop order with the exact arguments."

    expected_names = {"status.log", "status.log.1", "status.log.2", "status.log.3"}
    actual_names = {n for n in os.listdir(LOG_DIR) if n == "status.log" or n.startswith("status.log.")}
    assert actual_names == expected_names, "Execution did not produce exactly the expected four rotated log files."

    messages = []
    for name in ["status.log.3", "status.log.2", "status.log.1", "status.log"]:
        with open(os.path.join(LOG_DIR, name), "r", encoding="utf-8") as f:
            messages.extend(f.read().splitlines())
    assert messages == ["Ping successful", "Ping failed"] * 4, \
        f"Logs must reflect all eight controlled ping return codes using exact raw messages; got {messages!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
