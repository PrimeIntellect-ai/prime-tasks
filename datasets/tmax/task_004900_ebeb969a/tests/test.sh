#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import random
import re
import runpy
import subprocess
import sys

REPO = "/home/user/sensor_project"
MRE = "/home/user/mre.py"
BAD_COMMIT = "/home/user/bad_commit.txt"


def git(*args):
    return subprocess.run(
        ["git", *args], cwd=REPO, capture_output=True, text=True, check=True
    ).stdout


def calibration_from_source(source, filename):
    namespace = {"__name__": "historical_math_utils", "__file__": filename}
    exec(compile(source, filename, "exec"), namespace)
    fn = namespace.get("apply_calibration")
    assert callable(fn), f"{filename} does not define callable apply_calibration"
    return fn


def independently_find_bad_commit():
    stable_source = git("show", "v1.0:src/math_utils.py")
    stable_fn = calibration_from_source(stable_source, "v1.0:src/math_utils.py")
    expected = 100.023
    assert stable_fn(100.0) == expected, "v1.0 is not behaviorally stable"

    commits = git("rev-list", "--reverse", "v1.0..HEAD").splitlines()
    for commit in commits:
        source = git("show", f"{commit}:src/math_utils.py")
        fn = calibration_from_source(source, f"{commit}:src/math_utils.py")
        if fn(100.0) != expected:
            return commit
    raise AssertionError("No precision-regression commit found after v1.0")


def test_bad_commit_hash():
    assert os.path.exists(BAD_COMMIT), "/home/user/bad_commit.txt does not exist"
    with open(BAD_COMMIT, "r") as f:
        raw = f.read()
    assert re.fullmatch(r"[0-9a-f]{40}\n?", raw), "bad_commit.txt must contain only one full SHA-1 hash"
    actual_hash = raw.strip()

    # Retain the original exact commit assertion.
    result = subprocess.run(
        ["git", "log", "--grep=Introduce calibration rounding", "--format=%H"],
        cwd=REPO, capture_output=True, text=True, check=True
    )
    expected_hash = result.stdout.strip().split("\n")[0]
    assert expected_hash != "", "Could not find the expected bad commit in git history"
    assert actual_hash == expected_hash, f"Expected bad commit hash {expected_hash}, but got {actual_hash}"

    # Independently derive the first bad commit from historical behavior rather
    # than trusting the revealing commit message.
    behavioral_hash = independently_find_bad_commit()
    assert actual_hash == behavioral_hash, (
        f"Expected first behaviorally bad commit {behavioral_hash}, but got {actual_hash}"
    )


def recognized_calibration_call(node, imported_names):
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id in imported_names
        and len(node.args) == 1
        and not node.keywords
        and isinstance(node.args[0], ast.Constant)
        and type(node.args[0].value) is float
        and node.args[0].value == 100.0
    )


def test_mre_script():
    assert os.path.isfile(MRE), "/home/user/mre.py does not exist or is not a regular file"
    with open(MRE, "r") as f:
        content = f.read()

    # Retain the original content assertions.
    assert "apply_calibration" in content, "mre.py does not appear to use 'apply_calibration'"
    assert "100.0" in content, "mre.py does not appear to test the value 100.0"

    tree = ast.parse(content, filename=MRE)
    imported_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "src.math_utils":
            for alias in node.names:
                if alias.name == "apply_calibration":
                    imported_names.add(alias.asname or alias.name)
    assert imported_names, "mre.py must import apply_calibration from src.math_utils"

    assigned_results = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and recognized_calibration_call(node.value, imported_names):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assigned_results.add(target.id)
        elif isinstance(node, ast.AnnAssign) and recognized_calibration_call(node.value, imported_names):
            if isinstance(node.target, ast.Name):
                assigned_results.add(node.target.id)

    def is_result(expr):
        return recognized_calibration_call(expr, imported_names) or (
            isinstance(expr, ast.Name) and expr.id in assigned_results
        )

    def is_expected(expr):
        return isinstance(expr, ast.Constant) and type(expr.value) is float and expr.value == 100.023

    valid_assert = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assert) or not isinstance(node.test, ast.Compare):
            continue
        comparison = node.test
        if len(comparison.ops) != 1 or not isinstance(comparison.ops[0], ast.Eq) or len(comparison.comparators) != 1:
            continue
        left, right = comparison.left, comparison.comparators[0]
        if (is_result(left) and is_expected(right)) or (is_expected(left) and is_result(right)):
            valid_assert = True
            break
    assert valid_assert, "mre.py must assert that apply_calibration(100.0) equals exactly 100.023"

    env = os.environ.copy()
    env["PYTHONPATH"] = REPO
    result = subprocess.run(["python3", MRE], cwd="/home/user", capture_output=True, text=True, env=env)
    assert result.returncode == 0, (
        f"mre.py failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )

    # Verify that the assertion is active: with a deliberately incorrect
    # calibration result, the script must raise AssertionError.
    probe = r'''
import runpy, sys, types
src = types.ModuleType("src")
src.__path__ = []
math_utils = types.ModuleType("src.math_utils")
def apply_calibration(value):
    return 100.022
math_utils.apply_calibration = apply_calibration
src.math_utils = math_utils
sys.modules["src"] = src
sys.modules["src.math_utils"] = math_utils
try:
    runpy.run_path("/home/user/mre.py", run_name="__main__")
except AssertionError:
    sys.exit(0)
except BaseException:
    sys.exit(2)
sys.exit(1)
'''
    probe_result = subprocess.run(["python3", "-c", probe], cwd="/home/user", capture_output=True, text=True)
    assert probe_result.returncode == 0, "mre.py does not execute an effective assertion on the calibration result"


def test_apply_calibration_independently():
    path = os.path.join(REPO, "src", "math_utils.py")
    assert os.path.isfile(path), "src/math_utils.py does not exist or is not a regular file"
    spec = importlib.util.spec_from_file_location("submitted_math_utils", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    fn = getattr(module, "apply_calibration", None)
    assert callable(fn), "src/math_utils.py must define callable apply_calibration"

    values = [100.0, 50.0, 150.0, -17.125, 0.0, 1.23456789]
    rng = random.SystemRandom()
    values.extend(rng.uniform(-10000.0, 10000.0) for _ in range(25))
    for value in values:
        actual = fn(value)
        expected = value * 1.00023
        assert isinstance(actual, float), f"apply_calibration({value!r}) did not return a float"
        assert actual == expected, (
            f"apply_calibration({value!r}) returned {actual!r}; expected exact unrounded value {expected!r}"
        )


def test_pipeline_tests_pass():
    # Retain the original test invocation and repetition checks.
    for i in range(5):
        result = subprocess.run(
            ["pytest", "tests/test_pipeline.py"], cwd=REPO, capture_output=True, text=True
        )
        assert result.returncode == 0, (
            f"pytest failed on run {i+1}, indicating the precision bug is not fully fixed.\n"
            f"Output: {result.stdout}\nStderr: {result.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
