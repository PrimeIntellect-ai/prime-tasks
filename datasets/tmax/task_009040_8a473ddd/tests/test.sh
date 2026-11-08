#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import secrets
import subprocess

import pytest

BASE = "/home/user/ops_triage"
PIPELINE = os.path.join(BASE, "run_pipeline.sh")
MODEL = os.path.join(BASE, "model_optimizer.py")
OUTPUT = os.path.join(BASE, "optimized_weights.json")


def test_pipeline_executes_model_with_standard_numpy_and_generates_output():
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is missing."
    assert os.access(PIPELINE, os.X_OK), f"{PIPELINE} is not executable."
    assert os.path.isfile(MODEL), f"{MODEL} is missing."

    marker = "/tmp/ops_triage_pipeline_probe.json"
    token = secrets.token_hex(16)
    with open(MODEL, "rb") as f:
        original_model = f.read()

    probe = f'''import json
import os
import numpy as np

assert "bad_deps" not in os.path.realpath(np.__file__)
assert int(np.dot(np.array([2, 3]), np.array([4, 5]))) == 23
with open({marker!r}, "w") as f:
    json.dump({{"token": {token!r}, "numpy_path": np.__file__}}, f)
'''

    if os.path.exists(marker):
        os.remove(marker)
    try:
        with open(MODEL, "w") as f:
            f.write(probe)
        probe_run = subprocess.run(
            [PIPELINE], cwd=BASE, text=True, capture_output=True, timeout=30
        )
    finally:
        with open(MODEL, "wb") as f:
            f.write(original_model)

    assert probe_run.returncode == 0, (
        "run_pipeline.sh failed while executing a model that imports standard numpy.\n"
        f"stdout: {probe_run.stdout}\nstderr: {probe_run.stderr}"
    )
    assert os.path.isfile(marker), "run_pipeline.sh did not execute model_optimizer.py."
    with open(marker, "r") as f:
        marker_data = json.load(f)
    assert marker_data["token"] == token
    assert "bad_deps" not in os.path.realpath(marker_data["numpy_path"])

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    actual_run = subprocess.run(
        [PIPELINE], cwd=BASE, text=True, capture_output=True, timeout=30
    )
    assert actual_run.returncode == 0, (
        "The repaired optimization pipeline did not complete successfully.\n"
        f"stdout: {actual_run.stdout}\nstderr: {actual_run.stderr}"
    )
    assert os.path.isfile(OUTPUT), "The executed pipeline did not generate optimized_weights.json."


def test_optimized_weights_file_exists():
    file_path = "/home/user/ops_triage/optimized_weights.json"
    assert os.path.isfile(file_path), f"The output file {file_path} was not found. Did you run the pipeline successfully?"


def test_optimized_weights_content_correct():
    file_path = "/home/user/ops_triage/optimized_weights.json"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    assert "optimal_x" in data, "The JSON output is missing the 'optimal_x' key."
    assert data["optimal_x"] == -2.0, f"Expected optimal_x to be -2.0, but got {data['optimal_x']}."


def test_model_optimizer_bug_fixed():
    file_path = "/home/user/ops_triage/model_optimizer.py"
    assert os.path.isfile(file_path), f"{file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read()

    assert "x += grad * learning_rate" not in content, "The logical bug in model_optimizer.py (adding the gradient) is still present."
    assert "x -= grad * learning_rate" in content or "x = x - grad * learning_rate" in content, "The update rule in model_optimizer.py was not correctly fixed to subtract the gradient."


def test_optimizer_converges_for_derived_quadratic_minima():
    spec = importlib.util.spec_from_file_location("submitted_model_optimizer", MODEL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "optimize", None)), "model_optimizer.py has no callable optimize function."

    targets = []
    while len(targets) < 3:
        target = (secrets.randbelow(16001) - 8000) / 1000.0
        if abs(target + 2.0) > 0.25 and target not in targets:
            targets.append(target)

    original_gradient = module.gradient
    try:
        for target in targets:
            module.gradient = lambda x, target=target: 2.0 * (x - target)
            result = module.optimize()
            assert abs(result - target) < 1e-4, (
                f"optimize() did not converge under a quadratic gradient whose derived minimum is {target}; got {result}."
            )
    finally:
        module.gradient = original_gradient
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
