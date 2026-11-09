#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import glob
import random
import pytest


def get_pristine_experiments():
    rng = random.Random(42)
    learning_rates = [0.001, 0.005, 0.01, 0.05, 0.1]
    batch_sizes = [16, 32, 64, 128]
    num_layers = [2, 3, 4, 5]
    experiments = {}

    for i in range(40):
        run_id = f"run_valid_{i:03d}"
        lr = rng.choice(learning_rates)
        bs = rng.choice(batch_sizes)
        nl = rng.choice(num_layers)
        acc = 0.5 + (0.1 if bs == 64 else 0) + (0.1 if nl == 4 else 0) + rng.uniform(0.01, 0.05)
        experiments[f"/home/user/experiments/{run_id}.json"] = {
            "run_id": run_id,
            "learning_rate": lr,
            "batch_size": bs,
            "num_layers": nl,
            "metrics": {"val_accuracy": acc},
        }

    for i in range(10):
        run_id = f"run_invalid_{i:03d}"
        data = {
            "run_id": run_id,
            "learning_rate": rng.choice(learning_rates),
        }
        if i % 2 == 0:
            data["batch_size"] = str(rng.choice(batch_sizes))
            data["num_layers"] = rng.choice(num_layers)
            data["metrics"] = {"val_accuracy": 0.8}
        else:
            data["batch_size"] = rng.choice(batch_sizes)
            data["num_layers"] = rng.choice(num_layers)
            data["metrics"] = {"val_accuracy": 0.8, "extra": 1}
        experiments[f"/home/user/experiments/{run_id}.json"] = data

    return experiments


def get_valid_runs():
    valid_runs = []
    for filepath in glob.glob('/home/user/experiments/*.json'):
        with open(filepath, 'r') as f:
            try:
                data = json.load(f)
            except Exception:
                continue

            if not isinstance(data, dict):
                continue

            expected_keys = {"run_id", "learning_rate", "batch_size", "num_layers", "metrics"}
            if set(data.keys()) != expected_keys:
                continue

            if not isinstance(data["run_id"], str):
                continue
            if not isinstance(data["learning_rate"], float) and not (isinstance(data["learning_rate"], int) and not isinstance(data["learning_rate"], bool)):
                continue
            if not isinstance(data["batch_size"], int) or isinstance(data["batch_size"], bool):
                continue
            if not isinstance(data["num_layers"], int) or isinstance(data["num_layers"], bool):
                continue

            metrics = data["metrics"]
            if not isinstance(metrics, dict) or set(metrics.keys()) != {"val_accuracy"}:
                continue
            if not isinstance(metrics["val_accuracy"], float) and not (isinstance(metrics["val_accuracy"], int) and not isinstance(metrics["val_accuracy"], bool)):
                continue

            valid_runs.append(data)
    return valid_runs


def compute_expected_closest_runs(valid_runs):
    if not valid_runs:
        return []

    min_lr = min(r["learning_rate"] for r in valid_runs)
    max_lr = max(r["learning_rate"] for r in valid_runs)
    min_bs = min(r["batch_size"] for r in valid_runs)
    max_bs = max(r["batch_size"] for r in valid_runs)
    min_nl = min(r["num_layers"] for r in valid_runs)
    max_nl = max(r["num_layers"] for r in valid_runs)

    def scale(val, min_val, max_val):
        if max_val == min_val:
            return 0.0
        return (val - min_val) / (max_val - min_val)

    target = {"learning_rate": 0.005, "batch_size": 64, "num_layers": 3}
    t_lr = scale(target["learning_rate"], min_lr, max_lr)
    t_bs = scale(target["batch_size"], min_bs, max_bs)
    t_nl = scale(target["num_layers"], min_nl, max_nl)

    distances = []
    for r in valid_runs:
        s_lr = scale(r["learning_rate"], min_lr, max_lr)
        s_bs = scale(r["batch_size"], min_bs, max_bs)
        s_nl = scale(r["num_layers"], min_nl, max_nl)
        dist = math.sqrt((s_lr - t_lr)**2 + (s_bs - t_bs)**2 + (s_nl - t_nl)**2)
        distances.append((dist, r["run_id"]))

    distances.sort(key=lambda x: x[0])
    return [x[1] for x in distances[:3]]


def compute_expected_best_hyperparams(valid_runs):
    groups = {}
    for r in valid_runs:
        key = (r["batch_size"], r["num_layers"])
        groups.setdefault(key, []).append(r["metrics"]["val_accuracy"])

    best_pair = None
    best_mean = -1.0

    for (bs, nl), accuracies in groups.items():
        mean_acc = sum(accuracies) / len(accuracies)
        if mean_acc > best_mean:
            best_mean = mean_acc
            best_pair = (bs, nl)
        elif mean_acc == best_mean:
            if best_pair is None or bs > best_pair[0]:
                best_pair = (bs, nl)

    if best_pair is None:
        return ""

    return f"{best_pair[0]},{best_pair[1]},{best_mean:.4f}"


def pristine_valid_runs():
    return [
        data for data in get_pristine_experiments().values()
        if data["run_id"].startswith("run_valid_")
    ]


def test_experiment_inputs_are_intact():
    expected = get_pristine_experiments()
    actual_paths = set(glob.glob('/home/user/experiments/*.json'))
    assert actual_paths == set(expected), "Experiment JSON files were added, removed, or renamed."

    for path, expected_data in expected.items():
        with open(path, 'r') as f:
            actual_data = json.load(f)
        assert actual_data == expected_data, f"Experiment input was modified: {path}"


def test_closest_runs():
    output_path = '/home/user/closest_runs.json'
    assert os.path.exists(output_path), f"File {output_path} does not exist."

    with open(output_path, 'r') as f:
        try:
            student_closest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{output_path} is not valid JSON.")

    valid_runs = get_valid_runs()
    expected_closest = compute_expected_closest_runs(valid_runs)
    assert student_closest == expected_closest, f"Expected closest runs {expected_closest}, but got {student_closest}"

    immutable_expected = compute_expected_closest_runs(pristine_valid_runs())
    assert student_closest == immutable_expected, f"Expected closest runs {immutable_expected}, but got {student_closest}"


def test_best_hyperparams():
    output_path = '/home/user/best_hyperparams.txt'
    assert os.path.exists(output_path), f"File {output_path} does not exist."

    with open(output_path, 'r') as f:
        student_best = f.read().strip()

    valid_runs = get_valid_runs()
    expected_best = compute_expected_best_hyperparams(valid_runs)
    assert student_best == expected_best, f"Expected best hyperparams '{expected_best}', but got '{student_best}'"

    immutable_expected = compute_expected_best_hyperparams(pristine_valid_runs())
    assert student_best == immutable_expected, f"Expected best hyperparams '{immutable_expected}', but got '{student_best}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
