#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import shutil
import signal
import subprocess
import tempfile
import pytest

MINIMAL_LINES = ["ALLOC", "FREE", "PROCESS"]


def test_minimal_txt_content():
    path = "/home/user/minimal.txt"
    assert os.path.isfile(path), f"File {path} is missing. You must save the minimal set of commands here."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ["ALLOC", "FREE", "PROCESS"]
    assert lines == expected_lines, f"The contents of {path} are incorrect. Expected exactly the minimal commands to trigger the crash."


def test_crash_func_txt_content():
    path = "/home/user/crash_func.txt"
    assert os.path.isfile(path), f"File {path} is missing. You must write the crashing function name here."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "cmd_process", f"The function name in {path} is incorrect. Did you identify the correct function where the segfault occurs?"


def test_poc_py_exists_and_executable():
    path = "/home/user/poc.py"
    assert os.path.isfile(path), f"File {path} is missing. You must create your regression test script here."

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"File {path} is not executable. Please run chmod +x on it."


def run_poc_with_instrumented_target(mode):
    """Run the submitted PoC against a target that records and controls its outcome.

    The instrumented target first validates the supplied payload and executes the
    original vuln_bin on it. It then either segfaults, exits normally, or exits
    with a non-segfault error. This makes the PoC's signal classification
    testable despite the original allocator-dependent UAF not reliably faulting.
    """
    target = "/home/user/vuln_bin"
    poc = "/home/user/poc.py"

    with tempfile.TemporaryDirectory(prefix="poc_verify_") as td:
        original = os.path.join(td, "vuln_bin.original")
        log_path = os.path.join(td, "invocation.log")
        shutil.copy2(target, original)
        original_mode = stat.S_IMODE(os.stat(target).st_mode)

        probe = f'''#!/usr/bin/python3
import os
import signal
import subprocess
import sys

EXPECTED = ["ALLOC", "FREE", "PROCESS"]
MODE = {mode!r}
ORIGINAL = {original!r}
LOG = {log_path!r}

if len(sys.argv) != 2:
    sys.exit(20)
try:
    with open(sys.argv[1], "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
except Exception:
    sys.exit(21)
if lines != EXPECTED:
    sys.exit(22)

try:
    result = subprocess.run([ORIGINAL, sys.argv[1]], timeout=5)
except Exception:
    sys.exit(23)
if result.returncode != 0:
    sys.exit(24)

with open(LOG, "a") as f:
    f.write(MODE + "\\n")

if MODE == "segv":
    os.kill(os.getpid(), signal.SIGSEGV)
elif MODE == "normal":
    sys.exit(0)
else:
    sys.exit(42)
'''

        try:
            with open(target, "w") as f:
                f.write(probe)
            os.chmod(target, 0o755)

            try:
                result = subprocess.run([poc], capture_output=True, timeout=10)
            except subprocess.TimeoutExpired:
                pytest.fail(f"Execution of {poc} timed out. It should run and exit quickly.")
            except Exception as e:
                pytest.fail(f"Failed to execute {poc}: {e}")

            assert os.path.isfile(log_path), \
                f"{poc} did not execute /home/user/vuln_bin with the exact minimal payload."
            with open(log_path, "r") as f:
                invocations = [line.strip() for line in f if line.strip()]
            assert mode in invocations, \
                f"{poc} did not pass ALLOC, FREE, PROCESS in order to /home/user/vuln_bin."
            return result
        finally:
            shutil.copy2(original, target)
            os.chmod(target, original_mode)


def test_poc_py_execution():
    path = "/home/user/poc.py"
    assert os.path.isfile(path), f"File {path} is missing."

    result = run_poc_with_instrumented_target("segv")
    assert result.returncode == 0, \
        f"Running {path} did not yield exit code 0 (got {result.returncode}) when vuln_bin received SIGSEGV."


def test_poc_rejects_normal_exit():
    result = run_poc_with_instrumented_target("normal")
    assert result.returncode == 1, \
        f"Running /home/user/poc.py returned {result.returncode}; it must return 1 when vuln_bin exits normally."


def test_poc_rejects_non_segfault_error():
    result = run_poc_with_instrumented_target("error")
    assert result.returncode == 1, \
        f"Running /home/user/poc.py returned {result.returncode}; it must return 1 for a non-segfault error."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
