#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import random
import subprocess
import sys
from fractions import Fraction

import pytest

PROJECT = "/home/user/qa_project"


def test_qa_project_directory_exists():
    assert os.path.isdir(PROJECT), "Directory /home/user/qa_project does not exist."


def _exact_sample_variance(values):
    xs = [Fraction.from_float(float(x)) for x in values]
    mean = sum(xs, Fraction(0)) / len(xs)
    return float(sum((x - mean) ** 2 for x in xs) / (len(xs) - 1))


class SinglePassList(list):
    def __init__(self, values):
        super().__init__(values)
        self.iterations = 0

    def __iter__(self):
        self.iterations += 1
        if self.iterations > 1:
            raise AssertionError("calculate_sample_variance iterated over the input more than once")
        return super().__iter__()


def test_welford_implementation():
    welford_path = os.path.join(PROJECT, "welford.py")
    assert os.path.isfile(welford_path), f"File {welford_path} does not exist."

    sys.path.insert(0, PROJECT)
    try:
        from welford import calculate_sample_variance
    except ImportError:
        pytest.fail("Could not import calculate_sample_variance from welford.py")
    finally:
        sys.path.pop(0)

    # Preserve the original fixed checks.
    assert math.isclose(calculate_sample_variance([1, 2, 3]), 1.0), \
        "Variance calculation is incorrect for small numbers."

    large_offset = 1e9
    data = [large_offset + 1, large_offset + 2, large_offset + 3]
    assert math.isclose(calculate_sample_variance(data), 1.0), \
        "Variance calculation is not numerically stable (did you use Welford's algorithm?)."

    with pytest.raises(ValueError):
        calculate_sample_variance([1.0])
    with pytest.raises(ValueError):
        calculate_sample_variance([])

    # Exercise many verifier-derived inputs and require an online, single-pass computation.
    rng = random.Random(827361)
    for _ in range(60):
        values = [rng.uniform(-1000.0, 1000.0) for _ in range(rng.randint(2, 60))]
        expected = _exact_sample_variance(values)
        online_input = SinglePassList(values)
        actual = calculate_sample_variance(online_input)
        assert online_input.iterations == 1
        assert math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=5e-11, abs_tol=1e-9), \
            f"Incorrect sample variance for verifier-generated input: {values!r}"

    # Large offsets expose unstable one-pass sum/sum-of-squares implementations.
    for offset in (1e9, 1e12, 1e15):
        for _ in range(12):
            values = [offset + rng.randint(-1000, 1000) for _ in range(rng.randint(3, 40))]
            expected = _exact_sample_variance(values)
            online_input = SinglePassList(values)
            actual = calculate_sample_variance(online_input)
            assert online_input.iterations == 1
            assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-8), \
                "Variance calculation is not numerically stable on large-offset data"


def _number(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return float(node.value)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        value = _number(node.operand)
        return None if value is None else -value
    return None


def _call_name(call):
    if not isinstance(call, ast.Call):
        return ""
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        return call.func.attr
    return ""


def test_test_welford_contains_hypothesis():
    test_file = os.path.join(PROJECT, "test_welford.py")
    assert os.path.isfile(test_file), f"File {test_file} does not exist."

    with open(test_file, "r", encoding="utf-8") as f:
        content = f.read()
    assert "@given" in content, "test_welford.py does not contain '@given' decorator from hypothesis."

    try:
        tree = ast.parse(content, filename=test_file)
    except SyntaxError as exc:
        pytest.fail(f"test_welford.py is not valid Python: {exc}")

    given_tests = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test"):
            if any(_call_name(decorator) == "given" for decorator in node.decorator_list):
                given_tests.append(node)
    assert given_tests, "No pytest test function is actually decorated with hypothesis.given"

    nodes = [child for test in given_tests for child in ast.walk(test)]
    calls = [node for node in nodes if isinstance(node, ast.Call)]
    assert any(_call_name(call) == "calculate_sample_variance" for call in calls), \
        "The Hypothesis tests do not call calculate_sample_variance"

    valid_list_strategy = False
    for call in calls:
        if _call_name(call) != "lists" or not call.args or _call_name(call.args[0]) != "floats":
            continue
        list_kw = {kw.arg: kw.value for kw in call.keywords if kw.arg}
        float_kw = {kw.arg: kw.value for kw in call.args[0].keywords if kw.arg}
        minimum_size = _number(list_kw.get("min_size"))
        minimum = _number(float_kw.get("min_value"))
        maximum = _number(float_kw.get("max_value"))
        if (minimum_size is not None and minimum_size >= 2 and
                minimum is not None and minimum >= -1000.0 and
                maximum is not None and maximum <= 1000.0):
            valid_list_strategy = True
            break
    assert valid_list_strategy, \
        "Hypothesis must generate float lists bounded to [-1000, 1000] with min_size at least 2"

    has_nonnegative_check = any(
        isinstance(node, ast.Compare)
        and any(isinstance(op, ast.GtE) for op in node.ops)
        and any(value is not None and math.isclose(value, -1e-9, rel_tol=0, abs_tol=1e-15)
                for value in (_number(comp) for comp in node.comparators))
        for node in nodes
    )
    assert has_nonnegative_check, \
        "A @given test must assert that variance is >= -1e-9"

    isclose_calls = [call for call in calls if _call_name(call) == "isclose"]
    has_required_isclose = False
    for call in isclose_calls:
        keywords = {kw.arg: _number(kw.value) for kw in call.keywords if kw.arg}
        if (keywords.get("rel_tol") == 1e-5 and keywords.get("abs_tol") == 1e-8):
            has_required_isclose = True
            break
    variance_call_count = sum(_call_name(call) == "calculate_sample_variance" for call in calls)
    has_addition = any(isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add) for node in nodes)
    assert has_required_isclose and variance_call_count >= 2 and has_addition, \
        "A @given test must compare original and shifted variances with the required math.isclose tolerances"


def test_run_pipeline_script():
    script_path = os.path.join(PROJECT, "run_pipeline.sh")
    test_path = os.path.join(PROJECT, "test_welford.py")
    log_path = "/home/user/pipeline_result.log"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(test_path, "rb") as f:
        original_tests = f.read()

    try:
        # A deliberately failing pytest test must make the pipeline report failure.
        with open(test_path, "ab") as f:
            f.write(b"\n\ndef test_verifier_injected_failure():\n    assert False\n")
        if os.path.exists(log_path):
            os.remove(log_path)
        subprocess.run([script_path], cwd=PROJECT, timeout=300, check=False)
        assert os.path.isfile(log_path), "Pipeline did not create pipeline_result.log on test failure"
        with open(log_path, "r", encoding="utf-8") as f:
            assert f.read().strip() == "PIPELINE_FAILURE", \
                "Pipeline did not report PIPELINE_FAILURE when pytest failed"

        # Restore the submitted suite and require a real successful pipeline run.
        with open(test_path, "wb") as f:
            f.write(original_tests)
        if os.path.exists(log_path):
            os.remove(log_path)
        result = subprocess.run([script_path], cwd=PROJECT, timeout=300, check=False)
        assert result.returncode == 0, "run_pipeline.sh failed on the submitted test suite"
    finally:
        with open(test_path, "wb") as f:
            f.write(original_tests)

    venv_python = os.path.join(PROJECT, "venv", "bin", "python")
    assert os.path.isfile(venv_python), "Pipeline did not create the required virtual environment"
    subprocess.run(
        [venv_python, "-c", "import pytest, hypothesis"],
        cwd=PROJECT,
        timeout=30,
        check=True,
    )


def test_pipeline_result_log():
    log_path = "/home/user/pipeline_result.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "PIPELINE_SUCCESS", f"Expected PIPELINE_SUCCESS in {log_path}, got {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
