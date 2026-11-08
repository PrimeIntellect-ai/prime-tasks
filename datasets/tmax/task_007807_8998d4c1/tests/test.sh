#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile

VM_C = "/home/user/vm.c"
VM = "/home/user/vm"
OUTPUT = "/home/user/vm_output.txt"


def instruction(opcode, arg1=0, arg2=0, arg3=0):
    return bytes((opcode, arg1 & 0xff, arg2 & 0xff, arg3 & 0xff))


def run_vm(executable, program_path, expected):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [executable, program_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert os.path.exists(OUTPUT), f"{executable} did not create {OUTPUT}"
    assert os.path.isfile(OUTPUT), f"Path {OUTPUT} is not a file."
    with open(OUTPUT, "r") as f:
        actual = f.read()
    assert actual == expected, f"Expected {expected!r}, got {actual!r}"


def write_program(data):
    fd, path = tempfile.mkstemp(prefix="vm_case_", suffix=".bin")
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    return path


def trunc_div(a, b):
    quotient = abs(a) // abs(b)
    return -quotient if (a < 0) != (b < 0) else quotient


def generated_cases():
    # Randomized arithmetic values make fixed output tables insufficient.
    a = -secrets.randbelow(19) - 2
    b = secrets.randbelow(8) + 2
    add = a + b
    sub = a - b
    product = add * sub
    quotient = trunc_div(product, b)
    arithmetic = b"".join([
        instruction(0x01, 0, 0, a),
        instruction(0x01, 1, 0, b),
        instruction(0x02, 2, 0, 1),
        instruction(0x03, 3, 0, 1),
        instruction(0x04, 2, 2, 3),
        instruction(0x05, 3, 2, 1),
        instruction(0x08, 0),
        instruction(0x08, 1),
        instruction(0x08, 2),
        instruction(0x08, 3),
        instruction(0x09),
    ])
    arithmetic_expected = f"{a}\n{b}\n{product}\n{quotient}\n"

    n = secrets.randbelow(5) + 4
    factorial_loop = b"".join([
        instruction(0x01, 0, 0, n),
        instruction(0x01, 1, 0, 1),
        instruction(0x01, 2, 0, 1),
        instruction(0x06, 0, 0, 3),
        instruction(0x04, 1, 1, 0),
        instruction(0x03, 0, 0, 2),
        instruction(0x07, 0, 0, -4),
        instruction(0x08, 1),
        instruction(0x09),
    ])
    factorial_expected = f"{math.factorial(n)}\n"

    x = secrets.randbelow(100) + 1
    forward_jumps = b"".join([
        instruction(0x01, 0, 0, x),
        instruction(0x06, 0, 0, 2),  # Must not jump.
        instruction(0x07, 0, 0, 1),  # Skip the following LOAD_IMM.
        instruction(0x01, 0, 0, -1),
        instruction(0x08, 0),
        instruction(0x09),
    ])
    forward_expected = f"{x}\n"

    return [
        (arithmetic, arithmetic_expected),
        (factorial_loop, factorial_expected),
        (forward_jumps, forward_expected),
    ]


def test_vm_c_exists():
    vm_c_path = "/home/user/vm.c"
    assert os.path.exists(vm_c_path), f"Source file {vm_c_path} does not exist. You need to write the C code."
    assert os.path.isfile(vm_c_path), f"Path {vm_c_path} is not a file."


def test_vm_executable_exists():
    vm_path = "/home/user/vm"
    assert os.path.exists(vm_path), f"Executable {vm_path} does not exist. Did you compile the C code?"
    assert os.path.isfile(vm_path), f"Path {vm_path} is not a file."
    assert os.access(vm_path, os.X_OK), f"File {vm_path} is not executable."
    with open(vm_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{vm_path} is not a compiled ELF executable."


def test_vm_output_correct():
    run_vm(VM, "/home/user/prog.bin", f"{math.factorial(10)}\n")

    output_path = "/home/user/vm_output.txt"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist. Did you run the VM?"
    assert os.path.isfile(output_path), f"Path {output_path} is not a file."

    with open(output_path, "r") as f:
        content = f.read()

    expected_output = f"{math.factorial(10)}\n"
    assert content == expected_output, f"Content of {output_path} is incorrect. Expected '{expected_output}', got '{content}'."


def test_executable_and_source_implement_vm():
    source_vm = "/tmp/vm_compiled_from_submission"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-o", source_vm, VM_C],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, (
        "vm.c did not compile with GCC: " + result.stderr.decode(errors="replace")
    )

    paths = []
    try:
        for program, expected in generated_cases():
            path = write_program(program)
            paths.append(path)
            run_vm(VM, path, expected)
            run_vm(source_vm, path, expected)
    finally:
        for path in paths:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
