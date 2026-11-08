#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import pytest

HOME = "/home/user"


@pytest.fixture(scope="session", autouse=True)
def execute_artifacts_and_compile_source():
    script = os.path.join(HOME, "run_ci.sh")
    assert os.path.isfile(script), f"{script} is missing."
    assert os.access(script, os.X_OK), f"{script} is not executable."

    result = subprocess.run(
        [script], cwd=HOME, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"run_ci.sh failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    source_binary = os.path.join(
        tempfile.gettempdir(), f"vm_from_source_{secrets.token_hex(8)}"
    )
    result = subprocess.run(
        ["g++", "-std=c++17", os.path.join(HOME, "vm.cpp"), "-o", source_binary],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"vm.cpp does not compile with g++ -std=c++17: {result.stderr}"
    )
    assert os.access(source_binary, os.X_OK)
    yield source_binary
    try:
        os.remove(source_binary)
    except FileNotFoundError:
        pass


def read_instructions(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_valid_instruction(line):
    parts = line.split()
    assert parts, "Empty instruction"
    op = parts[0]
    assert op in {"LOAD", "ADD", "SUB", "OUT"}, f"Unsupported instruction: {line}"
    if op == "LOAD":
        assert len(parts) == 3, f"Malformed LOAD: {line}"
        assert parts[1] in {"R0", "R1"}, f"Invalid register: {line}"
        int(parts[2])
    elif op in {"ADD", "SUB"}:
        assert len(parts) == 3, f"Malformed {op}: {line}"
        assert parts[1] in {"R0", "R1"} and parts[2] in {"R0", "R1"}, line
    else:
        assert len(parts) == 2, f"Malformed OUT: {line}"
        assert parts[1] in {"R0", "R1"}, f"Invalid register: {line}"


def run_program(binary, instructions):
    fd, path = tempfile.mkstemp(prefix=f"program_{secrets.token_hex(6)}_", suffix=".asm")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(instructions) + "\n")
        return subprocess.run(
            [binary, path], capture_output=True, text=True, timeout=10
        )
    finally:
        os.remove(path)


def test_vm_cpp_exists():
    assert os.path.isfile("/home/user/vm.cpp"), "/home/user/vm.cpp is missing."


def test_vm_executable_exists():
    assert os.path.isfile("/home/user/vm"), "/home/user/vm is missing."
    assert os.access("/home/user/vm", os.X_OK), "/home/user/vm is not executable."


def test_test_success_asm():
    path = "/home/user/test_success.asm"
    assert os.path.isfile(path), f"{path} is missing."
    lines = read_instructions(path)
    assert len(lines) <= 10, f"{path} contains more than 10 instructions."
    for line in lines:
        assert_valid_instruction(line)
    ops = [line.split()[0] for line in lines]
    assert "LOAD" in ops, f"{path} must contain at least one LOAD instruction."
    assert "ADD" in ops, f"{path} must contain at least one ADD instruction."
    assert "OUT" in ops, f"{path} must print its result using OUT."


def test_test_limit_asm():
    path = "/home/user/test_limit.asm"
    assert os.path.isfile(path), f"{path} is missing."
    lines = read_instructions(path)
    assert len(lines) == 12, f"{path} does not contain exactly 12 instructions."
    assert all(line.split() == ["LOAD", "R0", "1"] for line in lines), (
        f"{path} must contain 12 LOAD R0 1 instructions."
    )


def test_run_ci_sh():
    path = "/home/user/run_ci.sh"
    assert os.path.isfile(path), f"{path} is missing."
    assert os.access(path, os.X_OK), f"{path} is not executable."


def test_ci_summary_txt():
    path = "/home/user/ci_summary.txt"
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read()

    assert "SUCCESS_TEST_OUTPUT: 15" in content, "SUCCESS_TEST_OUTPUT: 15 not found in ci_summary.txt"
    assert "LIMIT_TEST_EXIT_CODE: 42" in content, "LIMIT_TEST_EXIT_CODE: 42 not found in ci_summary.txt"
    assert content == "SUCCESS_TEST_OUTPUT: 15\nLIMIT_TEST_EXIT_CODE: 42\n", (
        "ci_summary.txt does not have the required exact format."
    )


def test_vm_behavior_limit():
    result = subprocess.run(
        ["/home/user/vm", "/home/user/test_limit.asm"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 42, f"VM did not exit with code 42 on limit test. Exit code was {result.returncode}"
    assert "QUOTA_EXCEEDED" in result.stderr, "VM did not print QUOTA_EXCEEDED to stderr."


def test_vm_behavior_success():
    result = subprocess.run(
        ["/home/user/vm", "/home/user/test_success.asm"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"VM did not exit with code 0 on success test. Exit code was {result.returncode}"
    assert result.stdout.strip() == "15", f"VM did not output 15 on success test. Output was {result.stdout.strip()}"


def test_vm_dynamic_instruction_semantics(execute_artifacts_and_compile_source):
    a = secrets.randbelow(101) - 50
    b = secrets.randbelow(101) - 50
    c = secrets.randbelow(101) - 50
    program = [
        f"LOAD R0 {a}",
        f"LOAD R1 {b}",
        "ADD R0 R1",
        "OUT R0",
        "SUB R0 R1",
        "OUT R0",
        f"LOAD R1 {c}",
        "SUB R1 R0",
        "ADD R1 R0",
        "OUT R1",
    ]
    expected = f"{a + b}\n{a}\n{c}\n"

    for binary in ("/home/user/vm", execute_artifacts_and_compile_source):
        result = run_program(binary, program)
        assert result.returncode == 0, (
            f"{binary} rejected a valid 10-instruction program: {result.stderr!r}"
        )
        assert result.stdout == expected, (
            f"{binary} produced {result.stdout!r}; expected {expected!r}"
        )
        assert "QUOTA_EXCEEDED" not in result.stderr


def test_vm_dynamic_quota_boundary(execute_artifacts_and_compile_source):
    value = secrets.randbelow(1000) + 2
    eleven = [f"LOAD R0 {value + i}" for i in range(10)] + ["OUT R0"]

    for binary in ("/home/user/vm", execute_artifacts_and_compile_source):
        result = run_program(binary, eleven)
        assert result.returncode == 42, (
            f"{binary} did not reject an attempted 11th instruction."
        )
        assert result.stdout == "", "The 11th instruction was executed before quota enforcement."
        assert "QUOTA_EXCEEDED" in result.stderr.splitlines(), (
            f"{binary} did not print QUOTA_EXCEEDED to stderr."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
