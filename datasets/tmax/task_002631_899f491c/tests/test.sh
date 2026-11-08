#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import random
import statistics
import subprocess
import tempfile
import pytest

PROCESSOR_PATH = "/home/user/app/processor.py"
DATA_PATH = "/home/user/app/data.csv"
MRE_PATH = "/home/user/mre.py"


def run_single_float(command):
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0, f"Running {' '.join(command)} failed with error: {result.stderr}"
    output = result.stdout.strip()
    try:
        value = float(output)
    except ValueError:
        pytest.fail(f"Output could not be parsed as a float. Output was: {output}")
    assert math.isfinite(value), f"Output must be a finite float, got: {output}"
    return value, output


def naive_variance(data):
    n = len(data)
    sum_x = sum(data)
    sum_sq = sum(x * x for x in data)
    return (sum_sq - (sum_x * sum_x) / n) / (n - 1)


def test_settings_json_exists_and_valid():
    settings_path = "/home/user/app/settings.json"
    assert os.path.isfile(settings_path), f"The file {settings_path} must exist."

    with open(settings_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{settings_path} does not contain valid JSON.")

    assert data == {}, f"{settings_path} should contain an empty JSON object {{}}."


def test_mre_py_exists_and_incorrect_variance():
    assert os.path.isfile(MRE_PATH), f"The file {MRE_PATH} must exist."

    with open(MRE_PATH, "r") as f:
        content = f.read()

    assert "1000000001.0" in content and "1000000002.0" in content and "1000000003.0" in content, \
        f"{MRE_PATH} must contain the hardcoded list of numbers."

    calculated_variance, _ = run_single_float(["python3", MRE_PATH])

    # The true sample variance is 1.0, while the required naive expression loses precision.
    assert calculated_variance != 1.0, \
        f"{MRE_PATH} is supposed to demonstrate the buggy naive formula, but it produced the correct variance (1.0)."

    original = [1000000001.0, 1000000002.0, 1000000003.0]
    assert calculated_variance == naive_variance(original), \
        f"{MRE_PATH} did not print the result of the required naive variance formula."

    # Replace the hardcoded list in the submitted AST with unpredictable values and
    # verify that the script still evaluates the same naive expression rather than
    # merely printing a fabricated constant.
    tree = ast.parse(content, filename=MRE_PATH)
    target = original

    class ReplaceTargetList(ast.NodeTransformer):
        def __init__(self, replacement):
            self.replacement = replacement
            self.replacements = 0

        def visit_List(self, node):
            self.generic_visit(node)
            values = []
            for elt in node.elts:
                if not isinstance(elt, ast.Constant) or not isinstance(elt.value, (int, float)):
                    return node
                values.append(float(elt.value))
            if values == target:
                self.replacements += 1
                return ast.copy_location(
                    ast.List(elts=[ast.Constant(value=x) for x in self.replacement], ctx=ast.Load()),
                    node,
                )
            return node

    rng = random.SystemRandom()
    cases = []
    while len(cases) < 3:
        base = float(10 ** rng.randrange(10, 15))
        offsets = sorted(rng.sample(range(1, 1000), 3))
        values = [base + float(x) for x in offsets]
        expected = naive_variance(values)
        correct = statistics.variance(values)
        if math.isfinite(expected) and expected != 0.0 and not math.isclose(expected, correct, rel_tol=1e-12, abs_tol=1e-12):
            cases.append((values, expected))

    for values, expected in cases:
        candidate_tree = ast.parse(content, filename=MRE_PATH)
        replacer = ReplaceTargetList(values)
        candidate_tree = replacer.visit(candidate_tree)
        ast.fix_missing_locations(candidate_tree)
        assert replacer.replacements >= 1, \
            f"{MRE_PATH} must contain the actual hardcoded list [1000000001.0, 1000000002.0, 1000000003.0]."

        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as temp:
            temp.write(ast.unparse(candidate_tree))
            temp_path = temp.name
        try:
            actual, _ = run_single_float(["python3", temp_path])
        finally:
            os.unlink(temp_path)
        assert actual == expected, \
            f"{MRE_PATH} does not implement the required naive variance calculation."


def test_processor_py_fixed():
    assert os.path.isfile(PROCESSOR_PATH), f"The file {PROCESSOR_PATH} must exist."

    calculated_variance, _ = run_single_float(["python3", PROCESSOR_PATH])
    assert abs(calculated_variance - 2.5) < 1e-5, \
        f"The variance calculated by {PROCESSOR_PATH} is incorrect. Expected 2.5, got {calculated_variance}."

    # Exercise the processor on unpredictable datasets so a fixed-output program
    # cannot pass. Restore the ticket's original data after each run.
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    rng = random.SystemRandom()
    dynamic_cases = [
        [rng.uniform(-5000.0, 5000.0) for _ in range(7)],
        [float(10 ** rng.randrange(11, 14)) + float(x) for x in rng.sample(range(1, 5000), 9)],
    ]

    try:
        for values in dynamic_cases:
            with open(DATA_PATH, "w") as f:
                for value in values:
                    f.write(repr(value) + "\n")

            actual, _ = run_single_float(["python3", PROCESSOR_PATH])
            expected = statistics.variance(values)
            assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-8), \
                f"The fixed processor returned {actual}; expected sample variance {expected}."
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)


def test_variance_output_txt_exists_and_correct():
    output_path = "/home/user/variance_output.txt"
    assert os.path.isfile(output_path), f"The file {output_path} must exist."

    with open(output_path, "r") as f:
        content = f.read().strip()

    try:
        saved_variance = float(content)
    except ValueError:
        pytest.fail(f"Content of {output_path} could not be parsed as a float. Content was: {content}")

    assert abs(saved_variance - 2.5) < 1e-5, \
        f"The variance saved in {output_path} is incorrect. Expected 2.5, got {saved_variance}."

    _, current_stdout = run_single_float(["python3", PROCESSOR_PATH])
    assert content == current_stdout, \
        f"{output_path} must contain the final standard output of the fixed processor."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
