#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess

import pytest

PROJECT_DIR = "/home/user/math_eval/evaluator"
BINARY_PATH = os.path.join(PROJECT_DIR, "target/release/evaluator")
DATASET_PATH = "/home/user/dataset.txt"
BENCHMARK_PATH = "/home/user/math_eval/benchmark.sh"
RESULT_PATH = "/home/user/benchmark_result.txt"


class EvalError(Exception):
    pass


def oracle_eval(expr):
    s = expr.replace(" ", "")

    def parse(idx):
        if idx >= len(s):
            raise EvalError()

        if s[idx] == "-" or s[idx].isdigit():
            start = idx
            if s[idx] == "-":
                idx += 1
                if idx >= len(s) or not s[idx].isdigit():
                    raise EvalError()
            while idx < len(s) and s[idx].isdigit():
                idx += 1
            return int(s[start:idx]), idx

        op = None
        for candidate in ("add", "sub", "mul", "div"):
            if s.startswith(candidate, idx):
                op = candidate
                break
        if op is None:
            raise EvalError()

        idx += 3
        if idx >= len(s) or s[idx] != "(":
            raise EvalError()
        left, idx = parse(idx + 1)
        if idx >= len(s) or s[idx] != ",":
            raise EvalError()
        right, idx = parse(idx + 1)
        if idx >= len(s) or s[idx] != ")":
            raise EvalError()
        idx += 1

        if op == "add":
            return left + right, idx
        if op == "sub":
            return left - right, idx
        if op == "mul":
            return left * right, idx
        if right == 0:
            raise EvalError()
        quotient = abs(left) // abs(right)
        if (left < 0) != (right < 0):
            quotient = -quotient
        return quotient, idx

    value, end = parse(0)
    if end != len(s):
        raise EvalError()
    return value


def dataset_sum(lines):
    total = 0
    for line in lines:
        try:
            total += oracle_eval(line.strip())
        except EvalError:
            pass
    return total


def run_binary(expression=None, extra_args=None):
    args = [BINARY_PATH]
    if expression is not None:
        args.append(expression)
    if extra_args:
        args.extend(extra_args)
    return subprocess.run(args, capture_output=True, text=True, timeout=10)


def make_valid_expression(rng, depth=0):
    if depth >= 4 or rng.random() < 0.32:
        value = rng.randint(-20, 20)
        return str(value), value

    op = rng.choice(["add", "sub", "mul", "div"])
    left_expr, left = make_valid_expression(rng, depth + 1)
    right_expr, right = make_valid_expression(rng, depth + 1)
    if op == "div" and right == 0:
        right = rng.choice([i for i in range(-9, 10) if i != 0])
        right_expr = str(right)

    separator = rng.choice([",", ", ", " , "])
    expression = f"{op}({left_expr}{separator}{right_expr})"
    if op == "add":
        value = left + right
    elif op == "sub":
        value = left - right
    elif op == "mul":
        value = left * right
    else:
        value = abs(left) // abs(right)
        if (left < 0) != (right < 0):
            value = -value
    return expression, value


def run_benchmark():
    assert os.path.isfile(BENCHMARK_PATH), f"Benchmark script not found at {BENCHMARK_PATH}."
    with open(BENCHMARK_PATH, "r", errors="replace") as f:
        first_line = f.readline().lower()
    command = ["python3", BENCHMARK_PATH] if "python" in first_line else ["bash", BENCHMARK_PATH]
    result = subprocess.run(
        command,
        cwd="/home/user/math_eval",
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Benchmark script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), f"Benchmark result file not found at {RESULT_PATH}."
    with open(RESULT_PATH, "r") as f:
        output = f.read().strip()
    assert output and (output.isdigit() or (output.startswith("-") and output[1:].isdigit())), (
        f"Benchmark result must be a simple integer, got {output!r}."
    )
    return int(output)


def test_legacy_c_moved():
    old_path = "/home/user/legacy.c"
    new_path = "/home/user/math_eval/legacy/legacy.c"
    assert not os.path.exists(old_path), f"Legacy file still exists at {old_path}, it should have been moved."
    assert os.path.isfile(new_path), f"Legacy file not found at {new_path}."


def test_rust_project_initialized():
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    main_rs = os.path.join(PROJECT_DIR, "src/main.rs")
    assert os.path.isfile(cargo_toml), f"Rust project Cargo.toml not found at {cargo_toml}."
    assert os.path.isfile(main_rs), f"Rust main.rs not found at {main_rs}."


def test_rust_binary_behavior():
    build_result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build_result.returncode == 0, f"Rust project failed to compile:\n{build_result.stderr}"
    assert os.path.isfile(BINARY_PATH), "Compiled binary not found in target/release/evaluator."

    # Preserve the original fixed checks.
    valid_run = run_binary("add(10, 5)")
    assert valid_run.returncode == 0, "Binary failed on valid input."
    assert valid_run.stdout.strip() == "15", f"Expected '15', got '{valid_run.stdout.strip()}'"

    div_zero_run = run_binary("div(10, 0)")
    assert div_zero_run.returncode == 0, "Binary must exit with code 0 on division by zero."
    assert div_zero_run.stdout.strip() == "EVAL_ERROR", f"Expected 'EVAL_ERROR' on div by zero, got '{div_zero_run.stdout.strip()}'"

    malformed_run = run_binary("add(10, )")
    assert malformed_run.returncode == 0, "Binary must exit with code 0 on malformed input."
    assert malformed_run.stdout.strip() == "EVAL_ERROR", f"Expected 'EVAL_ERROR' on malformed input, got '{malformed_run.stdout.strip()}'"

    # Exercise unpredictable nested expressions so fixed-output implementations fail.
    rng = random.Random(secrets.randbits(128))
    for _ in range(70):
        expression, expected = make_valid_expression(rng)
        result = run_binary(expression)
        assert result.returncode == 0, f"Binary failed on valid expression {expression!r}."
        assert result.stdout.strip() == str(expected), (
            f"Incorrect result for {expression!r}: expected {expected}, got {result.stdout.strip()!r}."
        )

    invalid_inputs = [
        "div(123, sub(8, 8))",
        "mul(add(1, 2), div(9, 0))",
        "add(1,2)trailing",
        "unknown(1,2)",
        "sub((1),2)",
        "mul(1 2)",
        "div(1,)",
        "add(--2,3)",
        "",
    ]
    for expression in invalid_inputs:
        result = run_binary(expression)
        assert result.returncode == 0, f"Binary did not exit 0 for invalid input {expression!r}."
        assert result.stdout.strip() == "EVAL_ERROR", (
            f"Expected EVAL_ERROR for {expression!r}, got {result.stdout.strip()!r}."
        )

    no_arg = run_binary()
    assert no_arg.returncode == 0, "Binary must not panic when the expression argument is missing."
    assert no_arg.stdout.strip() == "EVAL_ERROR"


def test_benchmark_result():
    assert os.path.isfile(DATASET_PATH), f"Dataset not found at {DATASET_PATH}."
    with open(DATASET_PATH, "rb") as f:
        original_dataset = f.read()

    rng = random.Random(secrets.randbits(128))
    generated_lines = []
    for _ in range(75):
        expression, _ = make_valid_expression(rng)
        generated_lines.append(expression)
    generated_lines.extend([
        "div(77, 0)",
        "add(1, )",
        "mul(add(2, 3), sub(4, 4))",
        "not_an_expression",
    ])
    rng.shuffle(generated_lines)

    try:
        with open(DATASET_PATH, "w") as f:
            f.write("\n".join(generated_lines) + "\n")
        if os.path.exists(RESULT_PATH):
            os.remove(RESULT_PATH)
        actual = run_benchmark()
        expected = dataset_sum(generated_lines)
        assert actual == expected, f"Benchmark failed generated dataset: expected {expected}, got {actual}."
    finally:
        with open(DATASET_PATH, "wb") as f:
            f.write(original_dataset)

    # Preserve the original benchmark assertion, deriving the answer in the verifier.
    original_lines = original_dataset.decode().splitlines()
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    actual = run_benchmark()
    expected = dataset_sum(original_lines)
    assert actual == expected, f"Benchmark result sum is incorrect. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
