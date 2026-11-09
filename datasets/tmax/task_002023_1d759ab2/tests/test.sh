#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import shutil
import string
import subprocess
import tempfile
import tokenize

import pytest

KEY_FILE = "/home/user/key.txt"
VERIFY_SCRIPT = "/home/user/verify.py"
LEGACY_SERVICE = "/home/user/legacy_service"
EXPECTED_KEY = "OpsFix99"


def run_command(command, timeout=5):
    try:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {command!r} timed out.")


def test_key_file_exists_and_correct():
    """Test that the key file exists and contains the correct key."""
    assert os.path.exists(KEY_FILE), f"The file {KEY_FILE} does not exist."
    assert os.path.isfile(KEY_FILE), f"The path {KEY_FILE} is not a file."

    with open(KEY_FILE, "r") as f:
        content = f.read()

    assert content == EXPECTED_KEY, (
        f"The file {KEY_FILE} does not contain the correct key. "
        f"Expected '{EXPECTED_KEY}', got '{content}'."
    )


def test_verify_script_exists_and_runs():
    """Keep the original check that verify.py exists and succeeds normally."""
    assert os.path.exists(VERIFY_SCRIPT), f"The file {VERIFY_SCRIPT} does not exist."
    assert os.path.isfile(VERIFY_SCRIPT), f"The path {VERIFY_SCRIPT} is not a file."

    result = run_command(["python3", VERIFY_SCRIPT])
    assert result.returncode == 0, (
        f"Execution of {VERIFY_SCRIPT} failed with exit code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\n"
        f"STDERR: {result.stderr}"
    )


def test_verify_script_reads_key_executes_service_and_asserts_return_code():
    """Exercise verify.py against a controlled service implementation."""
    with tokenize.open(VERIFY_SCRIPT) as source_file:
        tree = ast.parse(source_file.read(), filename=VERIFY_SCRIPT)
    assert any(isinstance(node, ast.Assert) for node in ast.walk(tree)), (
        f"{VERIFY_SCRIPT} must contain a Python assert statement."
    )

    alphabet = string.ascii_letters + string.digits
    probe_key = "".join(secrets.choice(alphabet) for _ in range(8))

    workdir = tempfile.mkdtemp(prefix="verify_behavior_")
    invocation_log = os.path.join(workdir, "invocations.jsonl")
    exit_code_file = os.path.join(workdir, "exit_code")
    assertion_marker = os.path.join(workdir, "assertion_seen")
    trace_runner = os.path.join(workdir, "trace_runner.py")

    fd, service_backup = tempfile.mkstemp(prefix=".legacy_service_backup_", dir="/home/user")
    os.close(fd)
    os.unlink(service_backup)
    original_key = None

    wrapper = f'''#!/usr/bin/python3
import json
import sys
with open({invocation_log!r}, "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
with open({exit_code_file!r}, "r") as control:
    code = int(control.read())
sys.exit(code)
'''

    runner = '''import os
import runpy
import sys

target = os.path.abspath(sys.argv[1])
marker = sys.argv[2]

def trace(frame, event, arg):
    if event == "exception" and isinstance(arg[1], AssertionError):
        if os.path.abspath(frame.f_code.co_filename) == target:
            with open(marker, "a") as output:
                output.write("assertion raised\\n")
    return trace

sys.settrace(trace)
sys.argv = [target]
runpy.run_path(target, run_name="__main__")
'''

    try:
        with open(KEY_FILE, "rb") as f:
            original_key = f.read()

        os.replace(LEGACY_SERVICE, service_backup)
        with open(LEGACY_SERVICE, "w") as f:
            f.write(wrapper)
        os.chmod(LEGACY_SERVICE, 0o755)

        with open(trace_runner, "w") as f:
            f.write(runner)

        with open(KEY_FILE, "wb") as f:
            f.write(probe_key.encode("ascii"))

        # Exit code 0 must be accepted, and the service must receive the key
        # read from key.txt as its sole argument.
        with open(exit_code_file, "w") as f:
            f.write("0")
        result = run_command(["python3", trace_runner, VERIFY_SCRIPT, assertion_marker])
        assert result.returncode == 0, (
            f"{VERIFY_SCRIPT} did not accept a successful service execution.\n"
            f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )

        # Nonzero service results must cause an assert in verify.py and make
        # verification fail. Check two values rather than trusting one case.
        for code in (7, 23):
            if os.path.exists(assertion_marker):
                os.unlink(assertion_marker)
            with open(exit_code_file, "w") as f:
                f.write(str(code))

            result = run_command(["python3", trace_runner, VERIFY_SCRIPT, assertion_marker])
            assert result.returncode != 0, (
                f"{VERIFY_SCRIPT} incorrectly succeeded when the service exited {code}."
            )
            assert os.path.exists(assertion_marker), (
                f"{VERIFY_SCRIPT} did not use its Python assert statement to reject "
                f"service exit code {code}."
            )

        with open(invocation_log, "r") as f:
            invocations = [json.loads(line) for line in f if line.strip()]
        assert len(invocations) >= 3, (
            f"{VERIFY_SCRIPT} did not execute {LEGACY_SERVICE} for every test run."
        )
        assert all(args == [probe_key] for args in invocations), (
            f"{VERIFY_SCRIPT} must execute {LEGACY_SERVICE} with the contents of "
            f"{KEY_FILE} as its sole argument; observed {invocations!r}."
        )
    finally:
        if original_key is not None:
            with open(KEY_FILE, "wb") as f:
                f.write(original_key)
        if os.path.lexists(LEGACY_SERVICE):
            os.unlink(LEGACY_SERVICE)
        if os.path.exists(service_backup):
            os.replace(service_backup, LEGACY_SERVICE)
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
