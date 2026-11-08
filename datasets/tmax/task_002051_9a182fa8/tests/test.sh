#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import math
import os
import re
import statistics
import subprocess
import sys
import types
import uuid


def test_migrate_patched():
    path = "/home/user/migrate.py"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "statistics.mean" in content, f"{path} was not patched correctly (missing statistics.mean)."
    assert "sum(v1_data" not in content, f"{path} still contains the bug."

    spec = importlib.util.spec_from_file_location("verified_migrate", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    migrate = module.migrate_v1_to_v2

    cases = [
        {"id": 17, "data": [1.0, 3.0]},
        {"id": -9, "data": [-100.0, 100.0, 50.0]},
        {"id": 123456, "data": [0.1, 0.2, 0.3, -0.4]},
    ]
    for v1_data in cases:
        result = migrate(v1_data)
        expected = statistics.mean(v1_data["data"])
        assert isinstance(result, dict)
        assert result["record_id"] == v1_data["id"]
        assert math.isclose(result["mean"], expected, rel_tol=1e-12, abs_tol=1e-12)


def test_test_migration_py_created():
    path = "/home/user/test_migration.py"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "test_migration_invariants" in content, "Test function 'test_migration_invariants' not found."
    assert "@given" in content, "@given decorator from hypothesis not found in the test file."
    assert "isclose" in content, "math.isclose not found in the test file."

    tree = ast.parse(content, filename=path)
    matching_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = node.func.attr if isinstance(node.func, ast.Attribute) else (
            node.func.id if isinstance(node.func, ast.Name) else None
        )
        if name != "isclose":
            continue
        kwargs = {kw.arg: kw.value for kw in node.keywords if kw.arg is not None}
        try:
            rel_tol = ast.literal_eval(kwargs["rel_tol"])
            abs_tol = ast.literal_eval(kwargs["abs_tol"])
        except (KeyError, ValueError, TypeError):
            continue
        if rel_tol == 1e-5 and abs_tol == 1e-8:
            matching_calls.append(node)
    assert matching_calls, "math.isclose must use rel_tol=1e-5 and abs_tol=1e-8."


def _run_submitted_property(mode):
    observations = []
    fake_migrate = types.ModuleType("migrate")

    def migrate_v1_to_v2(v1_data):
        assert isinstance(v1_data, dict)
        assert set(v1_data) >= {"id", "data"}
        assert type(v1_data["id"]) is int
        data = v1_data["data"]
        assert isinstance(data, list)
        assert 1 <= len(data) <= 100
        assert all(type(value) is float for value in data)
        assert all(math.isfinite(value) and -100.0 <= value <= 100.0 for value in data)
        observations.append(v1_data)

        mean = statistics.mean(data)
        record_id = v1_data["id"]
        if mode == "bad_id":
            record_id += 1
        elif mode == "bad_mean":
            mean += 1.0
        return {
            "record_id": record_id,
            "mean": mean,
            "normalized_data": [value - mean for value in data],
        }

    fake_migrate.migrate_v1_to_v2 = migrate_v1_to_v2
    old_migrate = sys.modules.get("migrate")
    sys.modules["migrate"] = fake_migrate
    module_name = "submitted_test_" + uuid.uuid4().hex
    try:
        spec = importlib.util.spec_from_file_location(module_name, "/home/user/test_migration.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        spec.loader.exec_module(module)
        test_function = getattr(module, "test_migration_invariants", None)
        assert callable(test_function), "test_migration_invariants is not callable."
        assert hasattr(test_function, "hypothesis"), "test_migration_invariants is not a Hypothesis test."
        test_function()
        return False, observations
    except BaseException:
        return True, observations
    finally:
        sys.modules.pop(module_name, None)
        if old_migrate is None:
            sys.modules.pop("migrate", None)
        else:
            sys.modules["migrate"] = old_migrate


def test_property_test_executes_and_checks_invariants():
    failed, observations = _run_submitted_property("correct")
    assert not failed, "The submitted property test fails against a correct migration implementation."
    assert observations, "The Hypothesis test did not pass generated records to migrate_v1_to_v2."

    failed, observations = _run_submitted_property("bad_id")
    assert observations, "The property test did not exercise migrate_v1_to_v2."
    assert failed, "The property test did not reject an incorrect record_id."

    failed, observations = _run_submitted_property("bad_mean")
    assert observations, "The property test did not exercise migrate_v1_to_v2."
    assert failed, "The property test did not reject an incorrect arithmetic mean."


def test_submitted_pytest_really_passes():
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "/home/user/test_migration.py"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stdout + "\n" + result.stderr
    assert re.search(r"\b1 passed\b", result.stdout) is not None, (
        "Executing the submitted test did not report exactly one passing test.\n" + result.stdout
    )


def test_test_results_log():
    path = "/home/user/test_results.log"
    assert os.path.isfile(path), f"File {path} does not exist. Did you redirect the pytest output?"
    with open(path, "r") as f:
        content = f.read()

    # Pytest output usually ends with something like "1 passed in 0.12s"
    assert re.search(r"\b1 passed\b", content) is not None, "Log file does not indicate that 1 test passed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
