#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tarfile
import tempfile

ROOT = "/home/user/math_eval"
ARTIFACT = "/home/user/artifact.tar.gz"
FOUR_DP = re.compile(r"^-?[0-9]+\.[0-9]{4}$")


def run_binary(path, commands):
    proc = subprocess.run(
        [path],
        input="\n".join(commands) + "\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert proc.returncode == 0, f"{path} exited with {proc.returncode}: {proc.stderr}"
    return proc.stdout.replace("\r", "").splitlines()


def eval_rpn(tokens, x=None):
    stack = []
    for token in tokens:
        if token == "x":
            assert x is not None
            stack.append(float(x))
        elif token in {"+", "-", "*", "/"}:
            assert len(stack) >= 2
            b = stack.pop()
            a = stack.pop()
            if token == "+":
                stack.append(a + b)
            elif token == "-":
                stack.append(a - b)
            elif token == "*":
                stack.append(a * b)
            else:
                stack.append(a / b)
        else:
            stack.append(float(token))
    assert len(stack) == 1
    return stack[0]


def trapezoid(tokens, start, end, steps):
    h = (end - start) / steps
    total = 0.5 * eval_rpn(tokens, start) + 0.5 * eval_rpn(tokens, end)
    for i in range(1, steps):
        total += eval_rpn(tokens, start + i * h)
    return total * h


def generated_cases():
    rng = random.SystemRandom()
    cases = []

    # Generate fresh evaluation cases so answers cannot be satisfied by a fixed table.
    for _ in range(6):
        a = rng.randint(-40, 40)
        b = rng.randint(1, 19)
        c = rng.randint(-15, 15)
        tokens = [str(a), str(b), "/", str(c), "+"]
        cases.append(("EVAL " + " ".join(tokens), eval_rpn(tokens)))

    # Use nonlinear integrands and varying bounds/subinterval counts to exercise
    # the actual trapezoidal rule rather than an analytic or hardcoded answer.
    for _ in range(5):
        qa = rng.choice([i for i in range(-5, 6) if i != 0])
        qb = rng.randint(-7, 7)
        qc = rng.randint(-9, 9)
        start = rng.randint(-4, 0)
        end = rng.randint(1, 6)
        steps = rng.randint(7, 47)
        tokens = ["x", "x", "*", str(qa), "*", "x", str(qb), "*", "+", str(qc), "+"]
        command = f"INTEGRATE {' '.join(tokens)} {start} {end} {steps}"
        cases.append((command, trapezoid(tokens, start, end, steps)))

    # Interleave command types to expose state retained between evaluations.
    rng.shuffle(cases)
    return cases


def assert_calculator(path):
    cases = generated_cases()
    commands = [case[0] for case in cases]
    expected = [case[1] for case in cases]
    batch = run_binary(path, commands)
    assert len(batch) == len(expected), f"Expected {len(expected)} output lines, got {len(batch)}"

    for i, (line, value) in enumerate(zip(batch, expected), 1):
        assert FOUR_DP.fullmatch(line), f"Line {i} is not formatted to exactly four decimal places: {line!r}"
        assert math.isfinite(float(line))
        assert abs(float(line) - value) <= 0.000051, \
            f"Line {i} has value {line}; expected {value:.10f} for {commands[i-1]!r}"

    # Results from the same process must match results from fresh processes.
    isolated = [run_binary(path, [command]) for command in commands]
    isolated_lines = [lines[0] if len(lines) == 1 else None for lines in isolated]
    assert batch == isolated_lines, "Results differ between batch and isolated evaluations (state leakage)."


def test_source_files_exist():
    """Verify that the required source files exist."""
    assert os.path.isfile(os.path.join(ROOT, "main.cpp")), "main.cpp is missing."
    assert os.path.isfile(os.path.join(ROOT, "Makefile")), "Makefile is missing."
    assert os.path.isfile(os.path.join(ROOT, "run_tests.sh")), "run_tests.sh is missing."


def test_makefile_build_and_source_program():
    """Build through the submitted Makefile and independently compile the C++17 source."""
    subprocess.run(["make", "clean"], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                   text=True, timeout=30, check=True)
    built = subprocess.run(["make"], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           text=True, timeout=60)
    assert built.returncode == 0, f"make failed:\n{built.stdout}\n{built.stderr}"
    calc = os.path.join(ROOT, "calc_tool")
    assert os.path.isfile(calc), "Makefile did not produce calc_tool."
    assert os.access(calc, os.X_OK), "Makefile's calc_tool is not executable."
    assert_calculator(calc)

    with tempfile.TemporaryDirectory() as td:
        direct = os.path.join(td, "calc_tool")
        compiled = subprocess.run(
            ["g++", "-std=c++17", os.path.join(ROOT, "main.cpp"), "-o", direct],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
        )
        assert compiled.returncode == 0, f"main.cpp does not compile as C++17:\n{compiled.stderr}"
        assert_calculator(direct)


def test_artifact_exists_and_contains_files():
    """Verify that the artifact tarball exists and contains the correct files."""
    assert os.path.isfile(ARTIFACT), "artifact.tar.gz is missing."

    with tarfile.open(ARTIFACT, "r:gz") as tar:
        members = [m.name for m in tar.getmembers()]
        calc_tool_found = any(m.endswith("calc_tool") for m in members)
        test_output_found = any(m.endswith("test_output.txt") for m in members)
        assert calc_tool_found, "calc_tool binary not found in tarball."
        assert test_output_found, "test_output.txt not found in tarball."

        binaries = [m for m in tar.getmembers() if os.path.basename(m.name) == "calc_tool" and m.isfile()]
        assert binaries, "The packaged calc_tool is not a regular file."
        member = binaries[0]
        assert member.mode & 0o111, "The packaged calc_tool is not executable."
        data = tar.extractfile(member).read()
        assert data, "The packaged calc_tool is empty."

    with tempfile.TemporaryDirectory() as td:
        packaged_calc = os.path.join(td, "calc_tool")
        with open(packaged_calc, "wb") as f:
            f.write(data)
        os.chmod(packaged_calc, 0o700)
        assert_calculator(packaged_calc)


def test_test_output_contents():
    """Verify that test_output.txt inside the tarball has the original required values."""
    assert os.path.isfile(ARTIFACT), "artifact.tar.gz is missing."
    expected_output = ["6.0000", "333.3333", "40.0000", "39.7500"]

    extracted_lines = []
    with tarfile.open(ARTIFACT, "r:gz") as tar:
        for member in tar.getmembers():
            if member.name.endswith("test_output.txt"):
                f = tar.extractfile(member)
                if f is not None:
                    content = f.read().decode("utf-8")
                    extracted_lines = [line.strip() for line in content.strip().split("\n")]
                break

    assert extracted_lines, "test_output.txt was empty or could not be read from the tarball."
    assert len(extracted_lines) == len(expected_output), \
        f"Expected {len(expected_output)} lines, got {len(extracted_lines)}."
    for i, (actual, expected) in enumerate(zip(extracted_lines, expected_output)):
        assert actual == expected, f"Line {i+1} mismatch: expected {expected!r}, got {actual!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
