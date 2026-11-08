#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import types
import uuid

import pytest

WORKSPACE = "/home/user/workspace"
COMPUTE_STATS = os.path.join(WORKSPACE, "src", "compute_stats.py")


def load_compute_stats():
    spec = importlib.util.spec_from_file_location("compute_stats", COMPUTE_STATS)
    module = importlib.util.module_from_spec(spec)
    sys.modules["compute_stats"] = module
    spec.loader.exec_module(module)
    return module


def test_makefile_fixed():
    makefile_path = os.path.join(WORKSPACE, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile is missing at {makefile_path}"

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "METRICS_DIR=/home/user/workspace/data" in content, "Makefile does not contain the correct METRICS_DIR path."


def test_compute_stats_fixed():
    assert os.path.isfile(COMPUTE_STATS), f"compute_stats.py is missing at {COMPUTE_STATS}"
    compute_stats = load_compute_stats()
    assert hasattr(compute_stats, "calculate_variance"), "calculate_variance function is missing."

    try:
        result = compute_stats.calculate_variance([42.0])
        assert result == 0.0, f"Expected calculate_variance([42.0]) to return 0.0, got {result}"
    except ZeroDivisionError:
        pytest.fail("calculate_variance([42.0]) raised ZeroDivisionError. The bug is not fixed.")

    assert compute_stats.calculate_variance([]) == 0.0, "Empty input must return exactly 0.0."

    rng = random.SystemRandom()
    singleton = [rng.uniform(-10000, 10000)]
    assert compute_stats.calculate_variance(singleton) == 0.0

    for size in (2, 3, 7, 13):
        values = [rng.uniform(-1000, 1000) for _ in range(size)]
        expected = statistics.variance(values)
        actual = compute_stats.calculate_variance(values)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), \
            f"Incorrect sample variance for {values}: expected {expected}, got {actual}"


def test_regression_script_exists_and_runs():
    regression_test_path = os.path.join(WORKSPACE, "test_regression.py")
    assert os.path.isfile(regression_test_path), f"Regression test script missing at {regression_test_path}"

    completed = subprocess.run(
        [sys.executable, regression_test_path],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, f"Regression test failed when executed:\n{completed.stdout}"

    wrapper = r'''
import runpy
import sys
import types

script = sys.argv[1]
return_value = float(sys.argv[2])
calls = []

import src
fake = types.ModuleType("src.compute_stats")
def calculate_variance(data):
    calls.append(list(data))
    return return_value
fake.calculate_variance = calculate_variance
sys.modules["src.compute_stats"] = fake
src.compute_stats = fake

runpy.run_path(script, run_name="__main__")
assert any(len(call) == 1 for call in calls), "Regression test did not call calculate_variance with a single-element list"
'''

    positive = subprocess.run(
        [sys.executable, "-c", wrapper, regression_test_path, "0.0"],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert positive.returncode == 0, f"Regression test does not exercise the required singleton case:\n{positive.stdout}"

    negative = subprocess.run(
        [sys.executable, "-c", wrapper, regression_test_path, "1e-12"],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert negative.returncode != 0, "Regression test does not assert that the result is exactly 0.0."


def test_logs_exist_and_correct():
    test_output_path = os.path.join(WORKSPACE, "test_output.log")
    build_success_path = os.path.join(WORKSPACE, "build_success.log")

    assert os.path.isfile(test_output_path), f"Test output log missing at {test_output_path}"
    assert os.path.isfile(build_success_path), f"Build success log missing at {build_success_path}"

    with open(build_success_path, "r") as f:
        build_content = f.read()

    assert "Variance: 0.0000" in build_content, "build_success.log does not contain 'Variance: 0.0000'. The build process might not have run successfully or the bug wasn't fixed."


def test_make_stats_executes_with_correct_environment_and_results():
    data_path = os.path.join(WORKSPACE, "data")
    backup_path = os.path.join(WORKSPACE, ".verifier-data-backup-" + uuid.uuid4().hex)
    source_backup = COMPUTE_STATS + ".verifier-backup"
    rng = random.SystemRandom()

    os.rename(data_path, backup_path)
    os.mkdir(data_path)
    try:
        datasets = {
            "singleton_" + uuid.uuid4().hex + ".txt": [rng.uniform(-500, 500)],
            "multi_" + uuid.uuid4().hex + ".txt": [rng.uniform(-500, 500) for _ in range(6)],
            "pair_" + uuid.uuid4().hex + ".txt": [rng.uniform(-500, 500) for _ in range(2)],
        }
        for name, values in datasets.items():
            with open(os.path.join(data_path, name), "w") as f:
                for value in values:
                    f.write(repr(value) + "\n")

        env = os.environ.copy()
        env.pop("METRICS_DIR", None)
        completed = subprocess.run(
            ["make", "-B", "stats"],
            cwd=WORKSPACE,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
        assert completed.returncode == 0, f"make stats failed:\n{completed.stdout}"

        for name, values in datasets.items():
            expected = 0.0 if len(values) <= 1 else statistics.variance(values)
            expected_line = f"File: {name}, Variance: {expected:.4f}"
            assert expected_line in completed.stdout, \
                f"make stats did not produce the expected result {expected_line!r}:\n{completed.stdout}"

        shutil.copy2(COMPUTE_STATS, source_backup)
        try:
            marker = "METRICS_ENV_PROBE_" + uuid.uuid4().hex
            with open(COMPUTE_STATS, "w") as f:
                f.write("import os\n")
                f.write(f"print({marker!r} + '=' + repr(os.environ.get('METRICS_DIR')))\n")

            probe = subprocess.run(
                ["make", "-B", "stats"],
                cwd=WORKSPACE,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=30,
            )
            assert probe.returncode == 0, f"make stats failed during environment probe:\n{probe.stdout}"
            assert marker + "='/home/user/workspace/data'" in probe.stdout, \
                f"The stats target did not pass the correct METRICS_DIR to the Python process:\n{probe.stdout}"
        finally:
            if os.path.exists(source_backup):
                os.replace(source_backup, COMPUTE_STATS)
    finally:
        if os.path.exists(source_backup):
            os.replace(source_backup, COMPUTE_STATS)
        shutil.rmtree(data_path, ignore_errors=True)
        os.rename(backup_path, data_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
