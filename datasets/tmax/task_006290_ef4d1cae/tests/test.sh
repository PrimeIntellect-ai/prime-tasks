#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import base64
import random
import shutil
import subprocess
import tempfile
import pytest

PROJECT_DIR = "/home/user/project"
EXECUTABLE_PATH = os.path.join(PROJECT_DIR, "evaluator")
LIBRARY_PATH = os.path.join(PROJECT_DIR, "libexpr.so")


def assert_dynamic_expr_binary(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} must be a compiled ELF executable, not a script."

    dynamic = subprocess.run(
        ["readelf", "-d", path], capture_output=True, text=True, check=True
    ).stdout
    assert re.search(r"\(NEEDED\).*\[libexpr\.so\]", dynamic), \
        f"{path} does not have a dynamic dependency on libexpr.so."

    ldd_result = subprocess.run(
        ["ldd", path], cwd=PROJECT_DIR, capture_output=True, text=True, check=True
    )
    match = re.search(r"libexpr\.so\s+=>\s+(\S+)", ldd_result.stdout)
    assert match, f"ldd did not show a resolved libexpr.so dependency:\n{ldd_result.stdout}"
    assert os.path.realpath(match.group(1)) == os.path.realpath(LIBRARY_PATH), \
        f"{path} resolved libexpr.so from {match.group(1)}, not {LIBRARY_PATH}."


def run_and_check(path, expression, expected, env=None):
    result = subprocess.run(
        [path, expression],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=5,
        env=env,
    )
    assert result.returncode == 0, \
        f"Evaluator failed for {expression!r}: {result.stderr}"
    assert result.stdout.strip() == str(expected), \
        f"Expected {expected} for {expression!r}, got {result.stdout.strip()!r}."


def make_expression(rng, leaves):
    if leaves == 1:
        value = rng.randrange(10)
        return [str(value)], value
    left_count = rng.randrange(1, leaves)
    left_tokens, left_value = make_expression(rng, left_count)
    right_tokens, right_value = make_expression(rng, leaves - left_count)
    op = rng.choice(["+", "-", "*"])
    if op == "+":
        value = left_value + right_value
    elif op == "-":
        value = left_value - right_value
    else:
        value = left_value * right_value
    return left_tokens + right_tokens + [op], value


def generated_cases():
    rng = random.SystemRandom()
    cases = [("3 4 +", 7), ("9 4 - 5 *", 25), ("7 3 * 2 +", 23)]
    for _ in range(40):
        tokens, value = make_expression(rng, rng.randrange(2, 8))
        cases.append((" ".join(tokens), value))
    return cases


CASES = generated_cases()


@pytest.fixture(scope="module")
def interposer():
    directory = tempfile.mkdtemp(prefix="expr_interposer_")
    source = os.path.join(directory, "interpose.c")
    library = os.path.join(directory, "interpose.so")
    with open(source, "w") as f:
        f.write("int evaluate_postfix(const char *expr) { (void)expr; return 123456789; }\n")
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", library, source],
        capture_output=True,
        text=True,
        check=True,
    )
    yield library
    shutil.rmtree(directory)


def assert_calls_dynamic_evaluate_postfix(path, interposer):
    env = os.environ.copy()
    env["LD_PRELOAD"] = interposer
    run_and_check(path, "1 2 +", 123456789, env=env)


def test_evaluator_executable_exists_and_runs(interposer):
    executable_path = os.path.join(PROJECT_DIR, "evaluator")
    assert os.path.isfile(executable_path), f"Executable {executable_path} not found."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."

    # Preserve the original smoke test.
    try:
        result = subprocess.run(
            [executable_path, "3 4 +"],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            check=True
        )
        assert result.stdout.strip() == "7", f"Expected evaluator to output '7' for '3 4 +', got '{result.stdout.strip()}'"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running evaluator failed with error: {e.stderr}. This might indicate a missing shared library or linking issue.")

    assert_dynamic_expr_binary(executable_path)
    for expression, expected in CASES:
        run_and_check(executable_path, expression, expected)
    assert_calls_dynamic_evaluate_postfix(executable_path, interposer)


def test_repaired_sources_compile_and_use_library(interposer):
    source_path = os.path.join(PROJECT_DIR, "evaluator.cpp")
    assert os.path.isfile(source_path), f"Source file {source_path} is missing."

    fd, rebuilt_path = tempfile.mkstemp(prefix=".verifier_rebuild_", dir=PROJECT_DIR)
    os.close(fd)
    os.unlink(rebuilt_path)
    try:
        compile_result = subprocess.run(
            [
                "g++", "-std=c++17", source_path,
                "-L" + PROJECT_DIR,
                "-Wl,-rpath,$ORIGIN",
                "-lexpr",
                "-o", rebuilt_path,
            ],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
        )
        assert compile_result.returncode == 0, \
            f"The repaired evaluator.cpp still fails to link against the C library:\n{compile_result.stderr}"
        assert_dynamic_expr_binary(rebuilt_path)
        for expression, expected in CASES:
            run_and_check(rebuilt_path, expression, expected)
        assert_calls_dynamic_evaluate_postfix(rebuilt_path, interposer)
    finally:
        if os.path.exists(rebuilt_path):
            os.unlink(rebuilt_path)


def test_v2_schema_json_correctness():
    v1_path = os.path.join(PROJECT_DIR, "v1_schema.txt")
    v2_path = os.path.join(PROJECT_DIR, "v2_schema.json")

    assert os.path.isfile(v1_path), f"File {v1_path} is missing."
    assert os.path.isfile(v2_path), f"File {v2_path} is missing. The migration step was not completed."

    with open(v1_path, "r") as f:
        v1_lines = f.read().splitlines()

    expected_data = []
    for line in v1_lines:
        if not line.strip():
            continue
        decoded_expr = base64.b64decode(line).decode("utf-8").strip()

        stack = []
        for char in decoded_expr:
            if char.isdigit():
                stack.append(int(char))
            elif char == '+':
                b = stack.pop()
                a = stack.pop()
                stack.append(a + b)
            elif char == '-':
                b = stack.pop()
                a = stack.pop()
                stack.append(a - b)
            elif char == '*':
                b = stack.pop()
                a = stack.pop()
                stack.append(a * b)

        expected_data.append({
            "expression": decoded_expr,
            "value": stack[0] if stack else 0
        })

    with open(v2_path, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {v2_path} is not strictly valid JSON.")

    assert isinstance(actual_data, list), "The root of v2_schema.json must be a JSON array."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} items in v2_schema.json, got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} in v2_schema.json is not a JSON object."
        assert "expression" in actual, f"Item at index {i} is missing the 'expression' key."
        assert "value" in actual, f"Item at index {i} is missing the 'value' key."
        assert actual["expression"] == expected["expression"], f"Expected expression '{expected['expression']}' at index {i}, got '{actual['expression']}'."
        assert actual["value"] == expected["value"], f"Expected value {expected['value']} at index {i}, got {actual['value']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
