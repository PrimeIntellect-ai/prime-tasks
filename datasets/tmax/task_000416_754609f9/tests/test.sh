#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile
from fractions import Fraction

import pytest

CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
EXECUTABLE = "/app/build/mathscript"
SOURCE_DIR = "/app/src"


def run_command(args, timeout=10):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"Command timed out: {args}: {exc}")


def test_cmake_rebuild():
    cmake_file = os.path.join(SOURCE_DIR, "CMakeLists.txt")
    assert os.path.isfile(cmake_file), f"CMakeLists.txt missing at {cmake_file}"

    configure = run_command(["cmake", "-S", SOURCE_DIR, "-B", "/app/build"], timeout=30)
    assert configure.returncode == 0, f"CMake configuration failed:\n{configure.stdout}\n{configure.stderr}"

    build = run_command(["cmake", "--build", "/app/build", "--clean-first"], timeout=60)
    assert build.returncode == 0, f"CMake build failed:\n{build.stdout}\n{build.stderr}"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as executable_file:
        assert executable_file.read(4) == b"\x7fELF", "mathscript must be a compiled ELF executable"


def test_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS):
        pytest.fail(f"Clean corpus directory missing at {CLEAN_CORPUS}")

    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    assert len(clean_files) > 0, "No clean files found"

    failed_files = []
    for f in clean_files:
        result = run_command([EXECUTABLE, "verify", f])
        if result.returncode != 0 or result.stdout.strip() != "SAFE":
            failed_files.append((os.path.basename(f), result.returncode, result.stdout.strip()))

    if failed_files:
        msg = f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected.\n"
        msg += "Offending files:\n" + "\n".join([f"{name}: exit={code}, out={out}" for name, code, out in failed_files[:10]])
        pytest.fail(msg)


def test_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS):
        pytest.fail(f"Evil corpus directory missing at {EVIL_CORPUS}")

    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    assert len(evil_files) > 0, "No evil files found"

    failed_files = []
    for f in evil_files:
        result = run_command([EXECUTABLE, "verify", f])
        if result.returncode != 1 or result.stdout.strip() != "UNSAFE":
            failed_files.append((os.path.basename(f), result.returncode, result.stdout.strip()))

    if failed_files:
        msg = f"{len(failed_files)} of {len(evil_files)} evil files bypassed.\n"
        msg += "Offending files:\n" + "\n".join([f"{name}: exit={code}, out={out}" for name, code, out in failed_files[:10]])
        pytest.fail(msg)


def test_generated_adversarial_inputs():
    rng = random.SystemRandom()

    safe_expressions = [
        "x + 1",
        "x / (2 + 3)",
        "  ( 12 + 8 ) * 3 / 5  ",
        "1 + 2 * 3 - 4 / 2",
        "((7))",
    ]
    for _ in range(12):
        a, b, c, d = [rng.randint(1, 1000) for _ in range(4)]
        safe_expressions.append(f"(({a} + {b}) * ({c} + {d})) / {rng.randint(1, 25)}")

    zero_a = rng.randint(10, 100000)
    zero_b = rng.randint(2, 500)
    deep_parentheses = "(" * 36 + str(rng.randint(1, 9)) + ")" * 36
    deep_ast = "1"
    for _ in range(40):
        deep_ast = f"1 + ({deep_ast})"

    evil_expressions = [
        "1 / 0",
        "x / 0",
        f"17 / ({zero_a} - {zero_a})",
        f"9 / ({zero_b} * 3 - {zero_b * 3})",
        "1 +",
        "(1 + 2",
        "1 + 2)",
        "1 ** 2",
        "1 @ 2",
        "()",
        "1 2",
        ")1(",
        deep_parentheses,
        deep_ast,
    ]

    cases = [(expr, True) for expr in safe_expressions] + [(expr, False) for expr in evil_expressions]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="mathscript-generated-") as directory:
        for index, (expression, should_be_safe) in enumerate(cases):
            path = os.path.join(directory, f"case-{rng.getrandbits(64):016x}-{index}.ms")
            with open(path, "w", encoding="utf-8") as expression_file:
                expression_file.write(expression)
            result = run_command([EXECUTABLE, "verify", path])
            expected_code = 0 if should_be_safe else 1
            expected_output = "SAFE" if should_be_safe else "UNSAFE"
            assert result.returncode == expected_code, (
                f"Incorrect classification for generated expression {expression!r}: "
                f"exit={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert result.stdout.strip() == expected_output, (
                f"Incorrect output for generated expression {expression!r}: {result.stdout!r}"
            )

        binary_path = os.path.join(directory, f"invalid-{rng.getrandbits(64):016x}.ms")
        with open(binary_path, "wb") as expression_file:
            expression_file.write(b"1 + \xff 2")
        result = run_command([EXECUTABLE, "verify", binary_path])
        assert result.returncode == 1 and result.stdout.strip() == "UNSAFE", (
            f"Invalid token stream was not rejected: exit={result.returncode}, "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )


def parse_numeric_result(stdout):
    tokens = re.findall(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", stdout)
    assert tokens, f"eval did not print a numeric result: {stdout!r}"
    return float(tokens[-1])


def test_generated_eval_results():
    rng = random.SystemRandom()
    cases = []
    for _ in range(8):
        a, b, c = rng.randint(1, 500), rng.randint(1, 100), rng.randint(2, 20)
        cases.append((f"{a} + {b} * {c}", Fraction(a + b * c)))
        cases.append((f"({a} + {b}) * {c}", Fraction((a + b) * c)))

        quotient, divisor, offset = rng.randint(1, 500), rng.randint(2, 30), rng.randint(1, 100)
        numerator = quotient * divisor
        cases.append((f"(({numerator} + {offset}) - {offset}) / {divisor}", Fraction(quotient)))

    with tempfile.TemporaryDirectory(prefix="mathscript-eval-") as directory:
        for expression, expected in cases:
            path = os.path.join(directory, f"eval-{rng.getrandbits(64):016x}.ms")
            with open(path, "w", encoding="utf-8") as expression_file:
                expression_file.write(expression)
            result = run_command([EXECUTABLE, "eval", path])
            assert result.returncode == 0, (
                f"eval failed for {expression!r}: exit={result.returncode}, stderr={result.stderr!r}"
            )
            actual = parse_numeric_result(result.stdout)
            assert math.isclose(actual, float(expected), rel_tol=1e-9, abs_tol=1e-9), (
                f"Wrong result for {expression!r}: expected {float(expected)}, got {actual}"
            )


def test_memory_leaks_valgrind():
    if not os.path.isdir(CLEAN_CORPUS):
        pytest.fail(f"Clean corpus directory missing at {CLEAN_CORPUS}")

    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    assert len(clean_files) > 0, "No clean files found for valgrind test"

    sample_file = clean_files[0]
    result = subprocess.run(
        ["valgrind", "--error-exitcode=255", "--leak-check=full", EXECUTABLE, "eval", sample_file],
        capture_output=True, text=True
    )

    assert result.returncode == 0, f"Valgrind reported memory leaks or errors (exit code {result.returncode}):\n{result.stderr}"


def test_generated_inputs_under_valgrind():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="mathscript-valgrind-") as directory:
        safe_path = os.path.join(directory, f"safe-{rng.getrandbits(64):016x}.ms")
        with open(safe_path, "w", encoding="utf-8") as expression_file:
            expression_file.write("((123 + 456) * (78 - 12)) / 3")

        result = run_command([
            "valgrind", "--error-exitcode=255", "--leak-check=full",
            "--errors-for-leak-kinds=all", EXECUTABLE, "eval", safe_path
        ], timeout=30)
        assert result.returncode == 0, f"Valgrind found eval errors or leaks:\n{result.stderr}"

        bad_path = os.path.join(directory, f"bad-{rng.getrandbits(64):016x}.ms")
        with open(bad_path, "w", encoding="utf-8") as expression_file:
            expression_file.write("1 / (987654 - 987654)")

        result = run_command([
            "valgrind", "--error-exitcode=255", "--leak-check=full",
            "--errors-for-leak-kinds=all", EXECUTABLE, "verify", bad_path
        ], timeout=30)
        assert result.returncode == 1, f"Unsafe input was not cleanly rejected under Valgrind:\n{result.stderr}"
        assert result.stdout.strip() == "UNSAFE"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
