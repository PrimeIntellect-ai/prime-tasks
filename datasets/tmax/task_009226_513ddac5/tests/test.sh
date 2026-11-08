#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import random
import subprocess
import sys

import pytest


@pytest.fixture(scope="session", autouse=True)
def validate_and_run_simulation():
    script_path = "/home/user/simulation.py"
    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."

    spec = importlib.util.spec_from_file_location("submitted_simulation", script_path)
    assert spec is not None and spec.loader is not None, "simulation.py is not importable."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    assert callable(getattr(module, "run_diffusion", None)), "run_diffusion is missing or not callable."
    assert callable(getattr(module, "find_equilibrium", None)), "find_equilibrium is missing or not callable."

    rng = random.SystemRandom()
    grid_sizes = list(dict.fromkeys([11] + rng.sample(range(5, 40), 6)))
    for grid_size in grid_sizes:
        initial = [0.0] * grid_size
        initial[grid_size // 2] = 100.0
        expected = initial[:]
        for i in range(1, grid_size - 1):
            expected[i] = initial[i] + 0.1 * (
                initial[i - 1] - 2 * initial[i] + initial[i + 1]
            )

        actual = module.run_diffusion(grid_size)
        assert isinstance(actual, list), "run_diffusion must return a list."
        assert len(actual) == grid_size, "run_diffusion returned the wrong grid size."
        assert actual == pytest.approx(expected), (
            f"run_diffusion({grid_size}) produced an incorrect diffusion step."
        )

    initial_values = [10.0, -250.0, 175.5] + [rng.uniform(-1000.0, 1000.0) for _ in range(4)]
    for init_val in initial_values:
        equilibrium = module.find_equilibrium(init_val)
        assert isinstance(equilibrium, (int, float)), "find_equilibrium must return a number."
        assert math.isfinite(equilibrium), "find_equilibrium diverged to a non-finite value."
        assert math.isclose(equilibrium, 50.0, rel_tol=0.0, abs_tol=1e-6), (
            f"find_equilibrium({init_val}) did not converge to 50.0."
        )

    success_path = "/home/user/success.json"
    if os.path.lexists(success_path):
        if os.path.isdir(success_path) and not os.path.islink(success_path):
            pytest.fail(f"Path {success_path} is a directory and cannot be regenerated as a JSON file.")
        os.unlink(success_path)

    completed = subprocess.run(
        [sys.executable, script_path, "--run-all"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "Running 'python /home/user/simulation.py --run-all' failed.\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.isfile(success_path), "The executed script did not generate /home/user/success.json."


def test_anomaly_file_exists_and_correct():
    anomaly_path = "/home/user/anomaly.txt"
    assert os.path.exists(anomaly_path), f"File {anomaly_path} does not exist."
    assert os.path.isfile(anomaly_path), f"Path {anomaly_path} is not a file."

    with open(anomaly_path, "r") as f:
        content = f.read().strip()

    assert content == "RUN_742", f"Expected 'RUN_742' in {anomaly_path}, but got '{content}'."


def test_success_json_exists_and_correct():
    success_path = "/home/user/success.json"
    assert os.path.exists(success_path), f"File {success_path} does not exist. Did the script run successfully?"
    assert os.path.isfile(success_path), f"Path {success_path} is not a file."

    with open(success_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {success_path} does not contain valid JSON.")

    assert "diffusion_center" in data, "Key 'diffusion_center' missing in success.json."
    assert "equilibrium" in data, "Key 'equilibrium' missing in success.json."

    assert data["diffusion_center"] == 80.0, f"Expected diffusion_center to be 80.0, got {data['diffusion_center']}."
    assert data["equilibrium"] == 50.0, f"Expected equilibrium to be 50.0, got {data['equilibrium']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
