#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import subprocess

BASE_DIR = "/home/user/libastmath"


def run(cmd, **kwargs):
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        **kwargs,
    )


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Binary {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF binary."


def expected_rpn(expr):
    stack = []
    for token in expr.split():
        if token in {"+", "-", "*", "/", "^"}:
            right = stack.pop()
            left = stack.pop()
            if token == "+":
                stack.append(left + right)
            elif token == "-":
                stack.append(left - right)
            elif token == "*":
                stack.append(left * right)
            elif token == "/":
                stack.append(left / right)
            else:
                stack.append(left ** right)
        else:
            stack.append(float(token))
    assert len(stack) == 1
    return stack[0]


def assert_evaluates(binary, expressions):
    for expr in expressions:
        proc = run([binary, expr])
        assert proc.returncode == 0, (
            f"{binary} failed for {expr!r}:\nstdout={proc.stdout}\nstderr={proc.stderr}"
        )
        lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        assert len(lines) == 1, f"Unexpected output from {binary}: {proc.stdout!r}"
        try:
            actual = float(lines[0])
        except ValueError as exc:
            raise AssertionError(f"Non-numeric output from {binary}: {proc.stdout!r}") from exc
        expected = expected_rpn(expr)
        assert math.isclose(actual, expected, rel_tol=1e-7, abs_tol=1e-7), (
            f"{binary} evaluated {expr!r} as {actual}, expected {expected}"
        )


def test_astmath_binaries_exist():
    astmath_path = os.path.join(BASE_DIR, "astmath")
    assert os.path.isfile(astmath_path), f"Binary {astmath_path} is missing. Did you run `make`?"
    assert os.access(astmath_path, os.X_OK), f"File {astmath_path} is not executable."

    astmath_embedded_path = os.path.join(BASE_DIR, "astmath_embedded")
    assert os.path.isfile(astmath_embedded_path), f"Binary {astmath_embedded_path} is missing. Did you run `make target=embedded`?"
    assert os.access(astmath_embedded_path, os.X_OK), f"File {astmath_embedded_path} is not executable."


def test_math_result():
    result_file = "/home/user/math_result.txt"
    assert os.path.isfile(result_file), f"File {result_file} is missing."

    with open(result_file, "r") as f:
        content = f.read().strip()

    assert "512.000000" in content, f"Expected 512.000000 in {result_file}, but found '{content}'."


def test_valgrind_report():
    report_file = "/home/user/valgrind_report.txt"
    assert os.path.isfile(report_file), f"File {report_file} is missing."

    with open(report_file, "r") as f:
        content = f.read()

    assert "definitely lost: 0 bytes" in content, f"Expected 'definitely lost: 0 bytes' in {report_file}. Memory leak might not be fully fixed."


def test_clean_builds_source_behavior_and_memory():
    expressions = [
        "2 3 2 ^ ^",
        "9 0.5 ^",
        "2 -3 ^",
        "5 2 ^ 7 + 3 *",
        "20 3 / 2 -",
        "8 3 - 4 * 2 /",
    ]

    # Force the Makefile to compile each conditional configuration from scratch.
    proc = run(["make", "clean"], cwd=BASE_DIR)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    proc = run(["make", "target=embedded"], cwd=BASE_DIR)
    assert proc.returncode == 0, "Embedded build failed:\n" + proc.stdout + proc.stderr
    embedded = os.path.join(BASE_DIR, "astmath_embedded")
    assert_elf_executable(embedded)
    assert_evaluates(embedded, expressions)
    verified_embedded = "/tmp/astmath_embedded.verified"
    shutil.copy2(embedded, verified_embedded)

    proc = run(["make", "clean"], cwd=BASE_DIR)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    proc = run(["make"], cwd=BASE_DIR)
    assert proc.returncode == 0, "Generic build failed:\n" + proc.stdout + proc.stderr
    generic = os.path.join(BASE_DIR, "astmath")
    assert_elf_executable(generic)
    assert_evaluates(generic, expressions)

    # Restore the already verified embedded artifact after the generic clean build.
    shutil.copy2(verified_embedded, embedded)

    # Independently compile the submitted C sources in both configurations so a
    # Makefile that merely fabricates executables cannot satisfy the verifier.
    for output, extra_flags in [
        ("/tmp/astmath_source_generic", []),
        ("/tmp/astmath_source_embedded", ["-DEMBEDDED_TARGET"]),
    ]:
        cmd = [
            "gcc", "-Wall", "-g", *extra_flags,
            os.path.join(BASE_DIR, "main.c"),
            os.path.join(BASE_DIR, "eval.c"),
            "-o", output, "-lm",
        ]
        proc = run(cmd)
        assert proc.returncode == 0, "Independent source compilation failed:\n" + proc.stdout + proc.stderr
        assert_elf_executable(output)
        assert_evaluates(output, expressions)

    # Execute the freshly built program under Valgrind rather than trusting the
    # agent-provided report text.
    proc = run([
        "valgrind",
        "--leak-check=full",
        "--show-leak-kinds=all",
        "--errors-for-leak-kinds=all",
        "--error-exitcode=97",
        generic,
        "4 5 + 2 *",
    ])
    assert proc.returncode == 0, "Valgrind detected an error or leak:\n" + proc.stderr
    assert "in use at exit: 0 bytes in 0 blocks" in proc.stderr, proc.stderr
    assert "ERROR SUMMARY: 0 errors" in proc.stderr, proc.stderr
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
