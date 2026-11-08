#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import stat
import string
import subprocess
import tempfile
import py_compile
import pytest

ORACLE_PATH = "/app/log_hasher"
AGENT_PATH = "/home/user/log_parser.py"
GENERATOR_PATH = "/home/user/generate_test_logs.py"
REGRESSION_PATH = "/home/user/test_parser.py"
NUM_TESTS = 5000
MAX_LEN = 500


def generate_random_string(length):
    chars = string.ascii_letters + string.digits + string.punctuation + " \t"
    return "".join(random.choice(chars) for _ in range(length))


def assert_python_artifact(path):
    assert os.path.exists(path), f"Required artifact not found at {path}"
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"Required artifact is not a regular file: {path}"
    assert os.path.getsize(path) > 0, f"Required artifact is empty: {path}"
    py_compile.compile(path, doraise=True)


def run_oracle(input_data):
    proc = subprocess.run(
        [ORACLE_PATH],
        input=input_data,
        text=True,
        capture_output=True,
        check=False,
        timeout=30,
    )
    assert proc.returncode == 0, f"Oracle program failed: {proc.stderr}"
    return proc.stdout


def demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def run_agent_without_delegation(input_data):
    fd, trace_path = tempfile.mkstemp(prefix="log_parser_trace_", dir="/tmp")
    os.close(fd)
    os.unlink(trace_path)
    try:
        proc = subprocess.run(
            ["strace", "-f", "-qq", "-e", "trace=process", "-o", trace_path,
             "python3", AGENT_PATH],
            input=input_data,
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
            preexec_fn=demote_to_user,
        )
        trace = ""
        if os.path.exists(trace_path):
            with open(trace_path, "r", encoding="utf-8", errors="replace") as handle:
                trace = handle.read()

        assert proc.returncode == 0, f"Agent program failed: {proc.stderr}"

        process_calls = re.findall(
            r"\b(execve|execveat|fork|vfork|clone|clone3)\(", trace
        )
        # The one permitted exec is strace starting the requested Python interpreter.
        exec_count = sum(name in ("execve", "execveat") for name in process_calls)
        child_calls = [name for name in process_calls if name not in ("execve", "execveat")]
        assert exec_count <= 1 and not child_calls, (
            "log_parser.py must implement the algorithm itself and may not delegate "
            f"to another process. Process syscalls observed: {process_calls}"
        )
        return proc.stdout
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass


def test_artifacts_and_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle program not found at {ORACLE_PATH}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle is not a regular file: {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle is not executable: {ORACLE_PATH}"

    assert_python_artifact(AGENT_PATH)
    assert_python_artifact(GENERATOR_PATH)
    assert_python_artifact(REGRESSION_PATH)

    with open(REGRESSION_PATH, "r", encoding="utf-8", errors="replace") as handle:
        regression_source = handle.read()
    assert "log_hasher" in regression_source, "test_parser.py does not reference the legacy hasher"
    assert "log_parser" in regression_source, "test_parser.py does not reference the replacement parser"

    generator_proc = subprocess.run(
        ["python3", GENERATOR_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        check=False,
        timeout=30,
    )
    assert generator_proc.returncode == 0, (
        f"generate_test_logs.py failed: {generator_proc.stderr}"
    )

    regression_proc = subprocess.run(
        ["python3", "-m", "pytest", REGRESSION_PATH, "-x", "--tb=short"],
        cwd="/home/user",
        text=True,
        capture_output=True,
        check=False,
        timeout=60,
    )
    assert regression_proc.returncode == 0, (
        "test_parser.py did not run successfully:\n"
        f"{regression_proc.stdout}\n{regression_proc.stderr}"
    )

    random.seed(42)
    inputs = []
    for _ in range(NUM_TESTS):
        length = random.randint(0, MAX_LEN)
        inputs.append(generate_random_string(length))

    inputs.append("")
    inputs.append("A" * MAX_LEN)
    inputs.append(" " * 50)
    input_data = "\n".join(inputs) + "\n"

    # Exercise fgets buffer boundaries and genuinely extreme logical lines.
    long_inputs = [
        "",
        "B" * 4094,
        "C" * 4095,
        "D" * 4096,
        "E" * 4097,
        ("long-line-0123456789" * 500),
        "Z" * 1000000,
    ]
    long_input_data = "\n".join(long_inputs) + "\n"

    oracle_stdout = run_oracle(input_data)
    long_oracle_stdout = run_oracle(long_input_data)
    oracle_outputs = oracle_stdout.strip("\n").split("\n")
    assert len(oracle_outputs) == len(inputs), "Oracle output line count mismatch"

    # Keep the required reverse-engineering target in place, but make it inaccessible
    # to the unprivileged process used for final verification.
    os.chmod(ORACLE_PATH, 0)
    assert stat.S_IMODE(os.stat(ORACLE_PATH).st_mode) == 0
    os.chmod(AGENT_PATH, 0o644)

    agent_stdout = run_agent_without_delegation(input_data)
    agent_outputs = agent_stdout.strip("\n").split("\n")
    assert len(agent_outputs) == len(inputs), "Agent output line count mismatch"

    for i, (oracle_out, agent_out) in enumerate(zip(oracle_outputs, agent_outputs)):
        if oracle_out != agent_out:
            failed_input = inputs[i]
            pytest.fail(
                f"Mismatch found!\n"
                f"Input (length {len(failed_input)}): {repr(failed_input)}\n"
                f"Expected (Oracle): {oracle_out}\n"
                f"Got (Agent):       {agent_out}"
            )

    long_agent_stdout = run_agent_without_delegation(long_input_data)
    assert long_agent_stdout == long_oracle_stdout, (
        "Output mismatch on buffer-boundary or extremely long log lines"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
