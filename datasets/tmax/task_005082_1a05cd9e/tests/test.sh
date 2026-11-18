#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import shutil
import subprocess

import pytest


@pytest.fixture(scope="session")
def expected_bc(tmp_path_factory):
    work = tmp_path_factory.mktemp("expected_patch")
    source = work / "rules.bc"
    output = work / "rules_patched.bc"
    shutil.copyfile("/app/rules.bc", source)
    proc = subprocess.run(
        ["patch", str(source), "-i", "/app/hotfix.patch", "-o", str(output)],
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, proc.stderr.decode("utf-8", errors="replace")
    assert output.is_file()
    return output


@pytest.fixture(scope="session")
def rebuilt_go(tmp_path_factory):
    source = "/home/user/telemetry_eval.go"
    assert os.path.isfile(source), "The Go source /home/user/telemetry_eval.go is missing."
    output = tmp_path_factory.mktemp("go_build") / "telemetry_eval"
    proc = subprocess.run(
        ["go", "build", "-o", str(output), source],
        capture_output=True,
        timeout=60,
    )
    assert proc.returncode == 0, (
        "The submitted Go source does not compile:\n"
        + proc.stderr.decode("utf-8", errors="replace")
    )
    return output


def emulate(bytecode, values):
    stack = []
    previous_smooth = 0.0
    inputs = iter(values)
    output = []

    for instruction in bytecode.decode("utf-8").splitlines():
        instruction = instruction.strip()
        if instruction == "LOAD":
            try:
                stack.append(next(inputs))
            except StopIteration:
                pass
        elif instruction == "ADD" and len(stack) >= 2:
            a, b = stack[-2], stack[-1]
            del stack[-2:]
            stack.append(a + b)
        elif instruction == "MUL" and len(stack) >= 2:
            a, b = stack[-2], stack[-1]
            del stack[-2:]
            stack.append(a * b)
        elif instruction == "SMOOTH" and stack:
            value = stack.pop()
            current = 0.75 * value + 0.25 * previous_smooth + 15.0
            previous_smooth = current
            stack.append(math.floor(current))
        elif instruction == "OUT" and stack:
            output.append(str(stack.pop()))

    return (("\n".join(output) + "\n") if output else "").encode("utf-8")


def run_program(binary, bytecode, values):
    input_bytes = ("\n".join(str(v) for v in values) + "\n").encode("utf-8")
    return subprocess.run(
        [str(binary), str(bytecode)],
        input=input_bytes,
        capture_output=True,
        timeout=5,
    )


def test_rules_patched_exists():
    assert os.path.isfile("/home/user/rules_patched.bc"), "The patched bytecode file /home/user/rules_patched.bc is missing."


def test_rules_patched_is_exact_hotfix_result(expected_bc):
    assert open("/home/user/rules_patched.bc", "rb").read() == expected_bc.read_bytes(), (
        "/home/user/rules_patched.bc is not the result of applying /app/hotfix.patch to /app/rules.bc."
    )


def test_rust_patcher_fixed_built_and_functional(expected_bc, tmp_path):
    manifest = "/app/bc-patcher/Cargo.toml"
    source = "/app/bc-patcher/src/main.rs"
    assert os.path.isfile(source), "The Rust patcher source is missing."

    build = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", manifest],
        capture_output=True,
        timeout=120,
    )
    assert build.returncode == 0, (
        "The Rust patcher does not compile in release mode:\n"
        + build.stderr.decode("utf-8", errors="replace")
    )

    patcher = "/app/bc-patcher/target/release/bc-patcher"
    assert os.path.isfile(patcher) and os.access(patcher, os.X_OK), "The release Rust patcher binary is missing."

    source_copy = tmp_path / "rules.bc"
    output = tmp_path / "patched.bc"
    shutil.copyfile("/app/rules.bc", source_copy)
    proc = subprocess.run(
        [patcher, str(source_copy), "/app/hotfix.patch", str(output)],
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, proc.stderr.decode("utf-8", errors="replace")
    assert output.is_file(), "The Rust patcher did not create its requested output."
    assert output.read_bytes() == expected_bc.read_bytes(), "The Rust patcher produced incorrect bytecode."


def test_telemetry_eval_exists():
    assert os.path.isfile("/home/user/telemetry_eval"), "The Go compiled binary /home/user/telemetry_eval is missing."
    assert os.access("/home/user/telemetry_eval", os.X_OK), "The Go compiled binary /home/user/telemetry_eval is not executable."
    with open("/home/user/telemetry_eval", "rb") as submitted:
        assert submitted.read(4) == b"\x7fELF", "The submitted executable is not a compiled ELF binary."


def test_submission_is_not_reference_binary():
    with open("/home/user/telemetry_eval", "rb") as submitted, open("/app/oracle_bin", "rb") as oracle:
        assert submitted.read() != oracle.read(), "The submitted executable is byte-identical to the reference implementation."


def test_fuzz_equivalence(expected_bc, rebuilt_go):
    oracle_bin = "/app/oracle_bin"
    agent_bin = "/home/user/telemetry_eval"

    assert os.path.isfile(oracle_bin), f"Oracle binary missing at {oracle_bin}"

    bytecode = expected_bc.read_bytes()
    random.seed(42)
    N = 100

    for i in range(N):
        num_ints = random.randint(10, 50)
        values = [random.randint(0, 1000) for _ in range(num_ints)]
        input_str = "\n".join(str(v) for v in values) + "\n"
        input_bytes = input_str.encode("utf-8")

        oracle_proc = subprocess.run(
            [oracle_bin, str(expected_bc)], input=input_bytes, capture_output=True, timeout=5
        )
        agent_proc = subprocess.run(
            [agent_bin, str(expected_bc)], input=input_bytes, capture_output=True, timeout=5
        )
        rebuilt_proc = subprocess.run(
            [str(rebuilt_go), str(expected_bc)], input=input_bytes, capture_output=True, timeout=5
        )
        expected_out = emulate(bytecode, values)

        assert oracle_proc.returncode == agent_proc.returncode, (
            f"Return code mismatch on input {i}.\nInput:\n{input_str}\n"
            f"Oracle return code: {oracle_proc.returncode}\n"
            f"Agent return code: {agent_proc.returncode}\n"
            f"Oracle stderr: {oracle_proc.stderr.decode('utf-8', errors='replace')}\n"
            f"Agent stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
        )
        assert oracle_proc.stdout == agent_proc.stdout, (
            f"Output mismatch on input {i}.\nInput:\n{input_str}\n"
            f"Oracle output:\n{oracle_proc.stdout.decode('utf-8', errors='replace')}\n"
            f"Agent output:\n{agent_proc.stdout.decode('utf-8', errors='replace')}"
        )
        assert oracle_proc.returncode == 0
        assert oracle_proc.stdout == expected_out
        assert agent_proc.stdout == expected_out
        assert rebuilt_proc.returncode == 0, rebuilt_proc.stderr.decode("utf-8", errors="replace")
        assert rebuilt_proc.stdout == expected_out
        assert expected_out, "The trusted patched bytecode unexpectedly produced no output."


def test_all_opcodes_and_negative_flooring(rebuilt_go, tmp_path):
    cases = [
        ("LOAD\nLOAD\nADD\nSMOOTH\nOUT\n", [-20, 3]),
        ("LOAD\nLOAD\nMUL\nSMOOTH\nOUT\n", [-7, 9]),
        ("LOAD\nSMOOTH\nLOAD\nSMOOTH\nADD\nOUT\n", [-100, 17]),
        ("LOAD\nSMOOTH\nOUT\nLOAD\nSMOOTH\nOUT\n", [8, -33]),
    ]

    for index, (program, values) in enumerate(cases):
        bytecode = tmp_path / f"case_{index}.bc"
        bytecode.write_text(program)
        expected = emulate(program.encode("utf-8"), values)
        for binary in ("/home/user/telemetry_eval", str(rebuilt_go)):
            proc = run_program(binary, bytecode, values)
            assert proc.returncode == 0, proc.stderr.decode("utf-8", errors="replace")
            assert proc.stdout == expected, (
                f"Incorrect output from {binary} for bytecode:\n{program}\n"
                f"Expected {expected!r}, got {proc.stdout!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
