#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import pytest

PACKAGE_DIR = "/app/email_quota_monitor-1.2.0"
BINARY_PATH = os.path.join(PACKAGE_DIR, "build/eqm_util")
MAIN_C = os.path.join(PACKAGE_DIR, "main.c")
MAKEFILE = os.path.join(PACKAGE_DIR, "Makefile")
AGENT_BIN = "/home/user/quota_wrapper"
AGENT_SOURCE = "/home/user/quota_wrapper.c"
ORACLE_BIN = "/opt/legacy/quota_oracle"


def run_program(path, *, env=None, input_text=None, timeout=10):
    try:
        return subprocess.run(
            [path],
            env=env,
            input=input_text,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {path} timed out.")


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {path} to be a compiled ELF binary."


def test_eqm_util_built_and_correct():
    assert os.path.isfile(MAIN_C), f"Expected source file {MAIN_C} does not exist."
    assert os.path.isfile(MAKEFILE), f"Expected Makefile {MAKEFILE} does not exist."

    # Prove that the repaired package can recreate the requested artifact using make.
    if os.path.lexists(BINARY_PATH):
        os.remove(BINARY_PATH)
    build = subprocess.run(
        ["make"], cwd=PACKAGE_DIR, capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, (
        f"make failed with exit code {build.returncode}.\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    assert os.path.isfile(BINARY_PATH), f"Expected compiled binary at {BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled binary {BINARY_PATH} is not executable."
    assert_elf(BINARY_PATH)

    # Retain the original fixed-value assertion.
    env = os.environ.copy()
    env["QUOTA_WARN_LEVEL"] = "85"
    result = run_program(BINARY_PATH, env=env, timeout=5)
    assert "Warning Level: 85%" in result.stdout, (
        f"Expected output to contain 'Warning Level: 85%', but got stdout:\n"
        f"{result.stdout}\nstderr:\n{result.stderr}"
    )

    # Compile main.c independently so the requested source patch itself is exercised.
    rebuilt_from_source = "/tmp/eqm_util_from_main"
    compile_result = subprocess.run(
        ["gcc", "-o", rebuilt_from_source, MAIN_C],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"main.c did not compile.\nstdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )

    levels = ["0", "1", "42", "100", str(secrets.randbelow(900000000) + 100000000)]
    for executable in (BINARY_PATH, rebuilt_from_source):
        assert_elf(executable)
        for level in levels:
            case_env = os.environ.copy()
            case_env["QUOTA_WARN_LEVEL"] = level
            case_env["QUOTA_WARN_LVL"] = "wrong-variable-value"
            case = run_program(executable, env=case_env, timeout=5)
            assert case.returncode == 0
            assert case.stdout == f"Warning Level: {level}%\n", (
                f"Incorrect output from {executable} for QUOTA_WARN_LEVEL={level!r}: "
                f"{case.stdout!r}"
            )

        unset_env = os.environ.copy()
        unset_env.pop("QUOTA_WARN_LEVEL", None)
        unset_env.pop("QUOTA_WARN_LVL", None)
        unset_case = run_program(executable, env=unset_env, timeout=5)
        assert unset_case.returncode == 0
        assert unset_case.stdout == "Warning Level: Not Set\n"


def test_wrapper_fuzz_equivalence():
    assert os.path.isfile(AGENT_SOURCE), f"Agent source {AGENT_SOURCE} does not exist."
    assert os.path.isfile(AGENT_BIN), f"Agent binary {AGENT_BIN} does not exist."
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary {AGENT_BIN} is not executable."
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary {ORACLE_BIN} does not exist."
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary {ORACLE_BIN} is not executable."
    assert_elf(AGENT_BIN)

    with open(AGENT_BIN, "rb") as agent_file, open(ORACLE_BIN, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), (
            "The submitted wrapper must not be a byte-for-byte copy of the legacy oracle."
        )

    # Retain the original 1000-input oracle equivalence check.
    random.seed(42)
    N = 1000
    inputs = [str(random.randint(0, 5000000)) for _ in range(N)]
    input_str = "\n".join(inputs) + "\n"

    oracle_result = run_program(ORACLE_BIN, input_text=input_str, timeout=10)
    agent_result = run_program(AGENT_BIN, input_text=input_str, timeout=10)

    oracle_lines = oracle_result.stdout.strip().split('\n')
    agent_lines = agent_result.stdout.strip().split('\n')

    assert len(agent_lines) == len(oracle_lines), (
        f"Line count mismatch. Oracle produced {len(oracle_lines)} lines, "
        f"agent produced {len(agent_lines)} lines."
    )

    for i, (oracle_line, agent_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert oracle_line == agent_line, (
            f"Output mismatch on input {inputs[i]}.\n"
            f"Oracle output: {oracle_line}\nAgent output:  {agent_line}\n"
            f"Line number:   {i+1}"
        )

    # Compile and execute the required source, and use independently derived answers.
    source_binary = "/tmp/quota_wrapper_from_source"
    compile_result = subprocess.run(
        ["gcc", "-o", source_binary, AGENT_SOURCE],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"quota_wrapper.c did not compile.\nstdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )
    assert_elf(source_binary)

    dynamic_values = [-1, 0, 1, 1048575, 1048576, 1048577]
    dynamic_values.extend(secrets.randbelow(10000001) - 1000000 for _ in range(200))
    dynamic_input = "\n".join(map(str, dynamic_values)) + "\n"
    expected = "".join("EXCEEDED\n" if value > 1048576 else "OK\n" for value in dynamic_values)

    for executable in (AGENT_BIN, source_binary):
        result = run_program(executable, input_text=dynamic_input, timeout=10)
        assert result.returncode == 0, f"{executable} exited with {result.returncode}."
        assert result.stdout == expected, f"Incorrect wrapper output from {executable}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
