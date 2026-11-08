#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

PROJECT = "/home/user/math_feature"
EXE = os.path.join(PROJECT, "rpn_vm")
RESULT = os.path.join(PROJECT, "result.txt")


def run_vm(expression):
    result = subprocess.run(
        [EXE, expression], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, (
        f"Execution of rpn_vm failed for {expression!r}: {result.stderr}"
    )
    return result.stdout.strip()


def c_div(a, b):
    assert b != 0
    quotient = abs(a) // abs(b)
    return -quotient if (a < 0) != (b < 0) else quotient


def random_int(low, high):
    return low + secrets.randbelow(high - low + 1)


def random_nonzero(low, high):
    while True:
        value = random_int(low, high)
        if value != 0:
            return value


def test_result_txt():
    result_path = "/home/user/math_feature/result.txt"
    assert os.path.isfile(result_path), f"File {result_path} does not exist. Did you save the result?"
    with open(result_path, "r") as f:
        content = f.read().strip()
    assert content == "25", f"Expected result.txt to contain '25', but got '{content}'."


def test_compilation():
    # Remove any prebuilt artifact so success requires the submitted Makefile to build it.
    if os.path.lexists(EXE):
        os.unlink(EXE)
    build = subprocess.run(
        ["make"], cwd=PROJECT, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, (
        "Running make failed.\nstdout:\n"
        + build.stdout
        + "\nstderr:\n"
        + build.stderr
    )

    exe_path = "/home/user/math_feature/rpn_vm"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist. Did you fix the Makefile and run make?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "rpn_vm must be a compiled native executable."


def test_rpn_vm_correctness():
    exe_path = "/home/user/math_feature/rpn_vm"

    # Preserve the original fixed checks.
    result_div = subprocess.run([exe_path, "10 2 /"], capture_output=True, text=True)
    assert result_div.returncode == 0, "Execution of rpn_vm failed for division test."
    assert result_div.stdout.strip() == "5", f"Expected '10 2 /' to yield 5, but got '{result_div.stdout.strip()}'. The division bug is not fixed correctly."

    result_sub = subprocess.run([exe_path, "10 2 -"], capture_output=True, text=True)
    assert result_sub.returncode == 0, "Execution of rpn_vm failed for subtraction test."
    assert result_sub.stdout.strip() == "8", f"Expected '10 2 -' to yield 8, but got '{result_sub.stdout.strip()}'. The subtraction bug is not fixed correctly."

    # Exercise subtraction and C integer-division semantics on unpredictable inputs.
    for _ in range(30):
        a = random_int(-10000, 10000)
        b = random_int(-10000, 10000)
        expression = f"{a} {b} -"
        assert run_vm(expression) == str(a - b), f"Incorrect result for {expression!r}"

        denominator = random_nonzero(-200, 200)
        expression = f"{a} {denominator} /"
        assert run_vm(expression) == str(c_div(a, denominator)), (
            f"Incorrect result for {expression!r}"
        )

    # Also test operand ordering inside compound RPN expressions.
    for _ in range(20):
        a = random_int(-5000, 5000)
        b = random_int(-5000, 5000)
        divisor = random_nonzero(-50, 50)
        multiplier = random_int(-20, 20)
        addend = random_int(-500, 500)
        expression = f"{a} {b} - {divisor} / {multiplier} * {addend} +"
        expected = c_div(a - b, divisor) * multiplier + addend
        assert run_vm(expression) == str(expected), f"Incorrect result for {expression!r}"

    required_expression = "100 20 5 - / 3 * 7 +"
    required_output = run_vm(required_expression)
    assert required_output == "25", (
        f"Expected required expression to yield 25, but got {required_output!r}."
    )
    with open(RESULT, "r") as f:
        saved_output = f.read().strip()
    assert saved_output == required_output, (
        "result.txt does not contain the output of the required expression."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
