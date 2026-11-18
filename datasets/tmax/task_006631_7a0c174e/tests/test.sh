#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import secrets

ROOT = "/home/user/math_release"
BINARY = os.path.join(ROOT, "bin/math_eval")


def test_evaluator_patched():
    filepath = "/home/user/math_release/src/evaluator.cpp"
    assert os.path.isfile(filepath), f"File missing: {filepath}"
    with open(filepath, "r") as f:
        content = f.read()
    assert 'if (token == "-") s.push(a - b);' in content, "The evaluator.cpp file does not contain the patched subtraction logic."
    assert 'b - a' not in content, "The buggy line was not removed from evaluator.cpp."


def test_makefile_exists():
    filepath = "/home/user/math_release/Makefile"
    assert os.path.isfile(filepath), f"Makefile missing: {filepath}"
    with open(filepath, "r") as f:
        content = f.read()
    assert "all" in content, "The Makefile does not define an 'all' target."
    assert "g++" in content or "c++" in content, "The Makefile does not seem to use a C++ compiler."
    assert "-std=c++17" in content, "The Makefile does not use the -std=c++17 flag."


def test_make_builds_executable():
    if os.path.lexists(BINARY):
        os.remove(BINARY)
    result = subprocess.run(
        ["make", "all"], cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"make all failed:\n{result.stdout}"
    assert os.path.isfile(BINARY), "make all did not create bin/math_eval"


def test_bin_directory_exists():
    dirpath = "/home/user/math_release/bin"
    assert os.path.isdir(dirpath), f"Directory missing: {dirpath}"


def test_executable_exists():
    filepath = "/home/user/math_release/bin/math_eval"
    assert os.path.isfile(filepath), f"Executable missing: {filepath}"
    st = os.stat(filepath)
    assert bool(st.st_mode & stat.S_IXUSR), f"The file {filepath} is not executable."
    with open(filepath, "rb") as f:
        assert f.read(4) == b"\x7fELF", "math_eval is not a compiled native executable."


def evaluate_rpn(line):
    stack = []
    for token in line.split():
        if token in {"+", "-", "*"}:
            b = stack.pop()
            a = stack.pop()
            if token == "+":
                stack.append(a + b)
            elif token == "-":
                stack.append(a - b)
            else:
                stack.append(a * b)
        else:
            stack.append(int(token))
    assert len(stack) == 1
    return stack[0]


def run_evaluator(lines):
    result = subprocess.run(
        [BINARY], input="\n".join(lines) + "\n", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, f"math_eval failed: {result.stderr}"
    actual = result.stdout.splitlines()
    assert all(re.fullmatch(r"-?\d+", line) for line in actual), \
        f"math_eval emitted non-numeric output: {actual}"
    return actual


def test_executable_behavior_on_derived_cases():
    rng = secrets.SystemRandom()

    def expression(depth):
        if depth == 0:
            value = rng.randint(-12, 12)
            return str(value), value
        left_text, left_value = expression(depth - 1)
        right_text, right_value = expression(depth - 1)
        op = rng.choice(["+", "-", "*"])
        if op == "+":
            value = left_value + right_value
        elif op == "-":
            value = left_value - right_value
        else:
            value = left_value * right_value
        return f"{left_text} {right_text} {op}", value

    cases = [
        "17 5 -",
        "3 11 -",
        "7 2 4 + *",
        "9 3 - 2 * 5 +",
        "2 3 + 4 5 - *",
    ]
    expected = [str(evaluate_rpn(case)) for case in cases]
    for _ in range(40):
        case, value = expression(3)
        cases.append(case)
        expected.append(str(value))

    assert run_evaluator(cases) == expected


def test_deploy_results():
    filepath = "/home/user/math_release/deploy_results.log"
    assert os.path.isfile(filepath), f"Results log missing: {filepath}"
    with open(filepath, "r") as f:
        content = f.read().strip()

    expected_lines = ["8", "6", "10", "45"]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, f"deploy_results.log content is incorrect. Expected {expected_lines}, but got {actual_lines}"

    inputs_path = "/home/user/math_release/tests/inputs.txt"
    assert os.path.isfile(inputs_path), f"Input file missing: {inputs_path}"
    with open(inputs_path, "r") as f:
        input_lines = [line.strip() for line in f if line.strip()]
    derived_expected = [str(evaluate_rpn(line)) for line in input_lines]
    executable_output = run_evaluator(input_lines)
    assert executable_output == derived_expected, \
        f"math_eval produced {executable_output}, expected {derived_expected}"
    assert actual_lines == executable_output, \
        "deploy_results.log does not match output produced by the built math_eval on inputs.txt"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
