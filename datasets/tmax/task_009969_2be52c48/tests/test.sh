#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import shutil
import subprocess

import numpy as np
import pytest
from scipy.stats import wasserstein_distance

SCRIPT_PATH = "/home/user/evaluate_drift.py"
OUTPUT_PATH = "/home/user/drift_metrics.json"
TRAIN_PATH = "/home/user/train_feature.txt"
VAL_PATH = "/home/user/val_feature.txt"


def test_drift_metrics_file_exists():
    path = OUTPUT_PATH
    assert os.path.isfile(path), f"Missing output file: {path}"


def test_drift_metrics_format_and_values():
    path = OUTPUT_PATH
    assert os.path.isfile(path), f"Missing output file: {path}"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not a valid JSON.")

    required_keys = {"distance", "ci_lower", "ci_upper"}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in JSON output: {missing_keys}"

    for key in required_keys:
        assert isinstance(data[key], (int, float)), f"Value for '{key}' must be a number."

    expected_distance = 0.2081
    expected_ci_lower = 0.0531
    expected_ci_upper = 0.3541

    assert abs(data["distance"] - expected_distance) < 1e-4, \
        f"Expected distance around {expected_distance}, got {data['distance']}"
    assert abs(data["ci_lower"] - expected_ci_lower) < 1e-4, \
        f"Expected ci_lower around {expected_ci_lower}, got {data['ci_lower']}"
    assert abs(data["ci_upper"] - expected_ci_upper) < 1e-4, \
        f"Expected ci_upper around {expected_ci_upper}, got {data['ci_upper']}"


def _call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = _call_name(node.value)
        return (prefix + "." if prefix else "") + node.attr
    return ""


def _constant_number(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.UnaryOp):
        value = _constant_number(node.operand)
        if value is None:
            return None
        if isinstance(node.op, ast.USub):
            return -value
        if isinstance(node.op, ast.UAdd):
            return value
    if isinstance(node, ast.BinOp):
        left = _constant_number(node.left)
        right = _constant_number(node.right)
        if left is None or right is None:
            return None
        try:
            if isinstance(node.op, ast.Add):
                return left + right
            if isinstance(node.op, ast.Sub):
                return left - right
            if isinstance(node.op, ast.Mult):
                return left * right
            if isinstance(node.op, ast.Div):
                return left / right
            if isinstance(node.op, ast.Pow):
                return left ** right
        except Exception:
            return None
    return None


def _contains_named_call(node, endings):
    for child in ast.walk(node):
        if isinstance(child, ast.Call):
            name = _call_name(child.func)
            if any(name == ending or name.endswith("." + ending) for ending in endings):
                return True
    return False


def _find_seed_statement(tree, seed_call):
    result = []

    def visit_body(body):
        for index, statement in enumerate(body):
            if any(child is seed_call for child in ast.walk(statement)):
                result.append((body, index))
            for child in ast.iter_child_nodes(statement):
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    visit_body(child.body)
                elif isinstance(child, (ast.For, ast.AsyncFor, ast.While, ast.If,
                                        ast.With, ast.AsyncWith, ast.Try)):
                    for field in ("body", "orelse", "finalbody"):
                        nested = getattr(child, field, None)
                        if nested:
                            visit_body(nested)
                    for handler in getattr(child, "handlers", []):
                        visit_body(handler.body)

    visit_body(tree.body)
    return result


def test_required_script_and_algorithm_structure():
    assert os.path.isfile(SCRIPT_PATH), f"Missing required script: {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a regular Python script"

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python: {exc}")

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]

    wasserstein_calls = [
        call for call in calls
        if _call_name(call.func) == "wasserstein_distance"
        or _call_name(call.func).endswith(".wasserstein_distance")
    ]
    assert wasserstein_calls, "Script must call scipy.stats.wasserstein_distance"

    percentile_calls = [
        call for call in calls
        if _call_name(call.func) == "percentile"
        or _call_name(call.func).endswith(".percentile")
    ]
    assert percentile_calls, "Script must use numpy.percentile for the confidence interval"
    assert all(not any(kw.arg in {"method", "interpolation"} for kw in call.keywords)
               for call in percentile_calls), \
        "numpy.percentile must use its default interpolation"

    numeric_values = [_constant_number(node) for node in ast.walk(tree)]
    assert any(value == 2.5 for value in numeric_values), "Missing the 2.5th percentile"
    assert any(value == 97.5 for value in numeric_values), "Missing the 97.5th percentile"
    assert any(value == 1000 for value in numeric_values), \
        "Bootstrap iteration/sample count must be exactly 1000"

    seed_calls = []
    for call in calls:
        name = _call_name(call.func)
        if name == "seed" or name.endswith(".random.seed"):
            seed_calls.append(call)
    assert len(seed_calls) == 1, "numpy.random.seed must be called exactly once"
    seed_call = seed_calls[0]
    assert len(seed_call.args) == 1 and _constant_number(seed_call.args[0]) == 42, \
        "The sole numpy.random.seed call must be numpy.random.seed(42)"

    resample_endings = {"choice", "randint", "random_integers"}
    assert _contains_named_call(tree, resample_endings), \
        "Script must generate bootstrap resamples with replacement"

    locations = _find_seed_statement(tree, seed_call)
    assert len(locations) == 1, "Could not determine the placement of numpy.random.seed(42)"
    body, index = locations[0]
    assert index + 1 < len(body), "numpy.random.seed(42) must immediately precede bootstrapping"
    next_statement = body[index + 1]
    next_is_bootstrap = (
        isinstance(next_statement, (ast.For, ast.AsyncFor, ast.While))
        or _contains_named_call(next_statement, resample_endings)
        or _contains_named_call(next_statement, {"bootstrap", "resample", "run_bootstrap"})
    )
    assert next_is_bootstrap, \
        "numpy.random.seed(42) must appear immediately before the bootstrap operation"

    assert not any(
        isinstance(call, ast.Call)
        and (_call_name(call.func) == "seed" or _call_name(call.func).endswith(".random.seed"))
        and getattr(call, "lineno", 0) > getattr(seed_call, "lineno", 0)
        for call in calls if call is not seed_call
    )


def _reference_bootstrap(train, val):
    np.random.seed(42)
    distances = []
    for _ in range(1000):
        train_sample = np.random.choice(train, size=train.size, replace=True)
        val_sample = np.random.choice(val, size=val.size, replace=True)
        distances.append(wasserstein_distance(train_sample, val_sample))
    return np.percentile(np.asarray(distances), [2.5, 97.5])


def test_script_executes_and_computes_from_current_inputs():
    backups = {}
    for path in (TRAIN_PATH, VAL_PATH, OUTPUT_PATH):
        backup = path + ".verifier_backup"
        if os.path.exists(path):
            shutil.copy2(path, backup)
            backups[path] = backup

    try:
        secret = int.from_bytes(os.urandom(8), "little")
        rng = np.random.default_rng(secret)
        train = rng.normal(-1.2, 0.55, 47)
        val = rng.normal(3.4, 0.75, 31)
        np.savetxt(TRAIN_PATH, train, fmt="%.17g")
        np.savetxt(VAL_PATH, val, fmt="%.17g")
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        completed = subprocess.run(
            ["python3", SCRIPT_PATH], cwd="/home/user",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        assert completed.returncode == 0, \
            f"evaluate_drift.py failed when executed:\n{completed.stderr}"
        assert os.path.isfile(OUTPUT_PATH), \
            "Executing evaluate_drift.py did not create drift_metrics.json"

        with open(OUTPUT_PATH, "r") as f:
            result = json.load(f)
        required_keys = {"distance", "ci_lower", "ci_upper"}
        assert not (required_keys - set(result)), "Executed script produced incomplete JSON"
        for key in required_keys:
            assert isinstance(result[key], (int, float)) and math.isfinite(result[key]), \
                f"Executed script produced an invalid {key}"

        expected_distance = round(float(wasserstein_distance(train, val)), 4)
        expected_ci = _reference_bootstrap(train, val)
        assert abs(result["distance"] - expected_distance) < 1e-4, \
            "Distance was not computed from the supplied feature files"
        # Equivalent loop and vectorized resampling layouts consume the seeded random
        # stream in different orders. This tolerance permits those valid layouts while
        # still deriving and checking the confidence interval independently.
        assert abs(result["ci_lower"] - round(float(expected_ci[0]), 4)) < 0.05, \
            "Bootstrap lower confidence bound is incorrect"
        assert abs(result["ci_upper"] - round(float(expected_ci[1]), 4)) < 0.05, \
            "Bootstrap upper confidence bound is incorrect"
        assert result["ci_lower"] <= result["distance"] <= result["ci_upper"], \
            "Confidence interval does not contain the measured distance"
    finally:
        for path in (TRAIN_PATH, VAL_PATH, OUTPUT_PATH):
            if path in backups:
                os.replace(backups[path], path)
            elif os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
