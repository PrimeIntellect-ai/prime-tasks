#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/analyze_artifacts.sh"
OUTPUT = "/home/user/closest.txt"
EXPERIMENTS = "/home/user/experiments"


@pytest.fixture(scope="session", autouse=True)
def execute_script_on_original_data():
    # Remove the pre-generated answer so the submitted artifact must recreate it.
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f"Script failed on the supplied experiment data with exit code {result.returncode}. "
        f"stderr: {result.stderr}"
    )


def test_script_exists_and_executable():
    script_path = "/home/user/analyze_artifacts.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist. The task requires creating this script."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable. Make sure to run 'chmod +x'."


def test_output_file_exists():
    output_path = "/home/user/closest.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. The script must generate this file."


def test_output_content():
    output_path = "/home/user/closest.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."
    with open(output_path, "r") as f:
        content = f.read()

    actual_id = content.strip()
    expected_id = "exp_alpha"
    assert actual_id == expected_id, f"Expected output to be '{expected_id}', but got '{actual_id}'. Check your filtering and distance calculation logic."


def oracle(objects):
    valid = []
    for obj in objects:
        if not isinstance(obj, dict) or set(obj) != {"id", "accuracy", "loss", "vector"}:
            continue
        if not isinstance(obj["id"], str):
            continue
        if type(obj["accuracy"]) not in (int, float) or type(obj["loss"]) not in (int, float):
            continue
        vector = obj["vector"]
        if not isinstance(vector, list) or len(vector) != 3:
            continue
        if any(type(value) not in (int, float) for value in vector):
            continue
        if obj["accuracy"] < 0.0 or obj["accuracy"] > 1.0 or obj["loss"] <= 0.0:
            continue
        distance = sum((value - target) ** 2 for value, target in zip(vector, (1.0, 2.0, 3.0)))
        valid.append((distance, obj["id"]))
    assert valid
    return min(valid)[1]


def run_case(objects):
    shutil.rmtree(EXPERIMENTS)
    os.makedirs(EXPERIMENTS, mode=0o777)
    random.SystemRandom().shuffle(objects)
    for index, obj in enumerate(objects):
        filename = f"case_{secrets.token_hex(5)}_{index}.json"
        with open(os.path.join(EXPERIMENTS, filename), "w") as handle:
            json.dump(obj, handle)

    expected = oracle(objects)
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f"Script exited with {result.returncode}: {result.stderr}"
    assert os.path.isfile(OUTPUT), "The executed script did not generate /home/user/closest.txt"
    with open(OUTPUT) as handle:
        actual = handle.read().strip()
    assert actual == expected, f"Expected dynamically derived id '{expected}', but got '{actual}'"


def test_z_script_behavior_on_unseen_data():
    backup_root = tempfile.mkdtemp(prefix="experiment_backup_")
    backup_experiments = os.path.join(backup_root, "experiments")
    shutil.copytree(EXPERIMENTS, backup_experiments)
    try:
        token = secrets.token_hex(6)
        delta = random.SystemRandom().uniform(0.02, 0.08)
        case_one = [
            {"id": f"boundary_winner_{token}", "accuracy": 0.0, "loss": 0.01, "vector": [1.0 + delta, 2.0, 3.0]},
            {"id": f"valid_far_{token}", "accuracy": 1.0, "loss": 2.5, "vector": [1.0 + 5 * delta, 2.0 + 3 * delta, 3.0]},
            {"id": f"bad_low_accuracy_{token}", "accuracy": -0.001, "loss": 0.1, "vector": [1.0, 2.0, 3.0]},
            {"id": f"bad_high_accuracy_{token}", "accuracy": 1.001, "loss": 0.1, "vector": [1.0, 2.0, 3.0]},
            {"id": f"bad_zero_loss_{token}", "accuracy": 0.5, "loss": 0.0, "vector": [1.0, 2.0, 3.0]},
            {"id": f"missing_loss_{token}", "accuracy": 0.5, "vector": [1.0, 2.0, 3.0]},
            {"id": f"wrong_vector_length_{token}", "accuracy": 0.5, "loss": 0.1, "vector": [1.0, 2.0, 3.0, 4.0]},
            {"id": f"wrong_vector_type_{token}", "accuracy": 0.5, "loss": 0.1, "vector": [1.0, "2.0", 3.0]},
            {"id": 12345, "accuracy": 0.5, "loss": 0.1, "vector": [1.0, 2.0, 3.0]},
            {"id": f"extra_key_{token}", "accuracy": 0.5, "loss": 0.1, "vector": [1.0, 2.0, 3.0], "notes": "not in schema"},
        ]
        run_case(case_one)

        token = secrets.token_hex(6)
        case_two = [
            {"id": f"x_axis_{token}", "accuracy": 0.7, "loss": 0.3, "vector": [1.04, 2.0, 3.0]},
            {"id": f"actual_nearest_{token}", "accuracy": 0.6, "loss": 0.4, "vector": [1.01, 2.01, 3.01]},
            {"id": f"high_accuracy_but_far_{token}", "accuracy": 0.999, "loss": 0.01, "vector": [4.0, -2.0, 8.0]},
            {"id": f"negative_loss_target_{token}", "accuracy": 0.8, "loss": -0.01, "vector": [1.0, 2.0, 3.0]},
            {"id": f"string_accuracy_{token}", "accuracy": "0.9", "loss": 0.1, "vector": [1.0, 2.0, 3.0]},
        ]
        run_case(case_two)
    finally:
        shutil.rmtree(EXPERIMENTS, ignore_errors=True)
        shutil.copytree(backup_experiments, EXPERIMENTS)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
