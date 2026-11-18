#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import sys

import pytest
import torch

SCRIPT_PATH = "/home/user/fit_model.py"
DATA_PATH = "/home/user/data.csv"
RESULTS_PATH = "/home/user/results.json"
AUDIT_PATH = "/tmp/fit_model_audit.json"
AUDIT_RUNNER_PATH = "/tmp/fit_model_audit_runner.py"

ORIGINAL_X = [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]
ORIGINAL_Y = [-4.5, -4.8, -2.5, 1.1, 4.6, 6.9, 7.6]

AUDIT_RUNNER = r'''
import json
import os
import runpy
import torch

SCRIPT_PATH = "/home/user/fit_model.py"
AUDIT_PATH = "/tmp/fit_model_audit.json"

audit = {
    "manual_seeds": [],
    "randn_calls": [],
    "mse_constructions": 0,
    "optimizer_constructions": [],
    "events": [],
}

original_manual_seed = torch.manual_seed
original_randn = torch.randn
original_mse_loss = torch.nn.MSELoss
original_sgd = torch.optim.SGD

parameter_ids = []

def audited_manual_seed(seed):
    audit["manual_seeds"].append(seed)
    audit["events"].append("seed")
    return original_manual_seed(seed)

def audited_randn(*args, **kwargs):
    result = original_randn(*args, **kwargs)
    audit["events"].append("randn")
    audit["randn_calls"].append({
        "shape_is_exact": args == (1,),
        "requires_grad_is_true": kwargs.get("requires_grad") is True,
        "dtype_is_float32": kwargs.get("dtype") is torch.float32,
        "result_id": id(result),
    })
    parameter_ids.append(id(result))
    return result

def audited_mse_loss(*args, **kwargs):
    audit["mse_constructions"] += 1
    module = original_mse_loss(*args, **kwargs)
    original_forward = module.forward

    def forward(input_tensor, target_tensor):
        output = original_forward(input_tensor, target_tensor)
        audit["events"].append("loss")
        if output.requires_grad:
            output.register_hook(lambda grad: (audit["events"].append("backward"), grad)[1])
        return output

    module.forward = forward
    return module

def audited_sgd(params, *args, **kwargs):
    params_list = list(params)
    lr = kwargs.get("lr", args[0] if args else None)
    audit["optimizer_constructions"].append({
        "parameter_ids": [id(value) for value in params_list],
        "lr": lr,
    })
    optimizer = original_sgd(params_list, *args, **kwargs)
    original_zero_grad = optimizer.zero_grad
    original_step = optimizer.step

    def zero_grad(*zargs, **zkwargs):
        audit["events"].append("zero_grad")
        return original_zero_grad(*zargs, **zkwargs)

    def step(*sargs, **skwargs):
        audit["events"].append("step")
        return original_step(*sargs, **skwargs)

    optimizer.zero_grad = zero_grad
    optimizer.step = step
    return optimizer

torch.manual_seed = audited_manual_seed
torch.randn = audited_randn
torch.nn.MSELoss = audited_mse_loss
torch.optim.SGD = audited_sgd

os.chdir("/home/user")
try:
    runpy.run_path(SCRIPT_PATH, run_name="__main__")
finally:
    audit["parameter_ids"] = parameter_ids
    with open(AUDIT_PATH, "w") as handle:
        json.dump(audit, handle)
'''


def expected_results(xs, ys):
    torch.manual_seed(42)
    a = torch.randn(1, requires_grad=True, dtype=torch.float32)
    b = torch.randn(1, requires_grad=True, dtype=torch.float32)
    c = torch.randn(1, requires_grad=True, dtype=torch.float32)
    x = torch.tensor(xs, dtype=torch.float32)
    y = torch.tensor(ys, dtype=torch.float32)
    criterion = torch.nn.MSELoss()
    optimizer = torch.optim.SGD([a, b, c], lr=0.05)

    for _ in range(500):
        optimizer.zero_grad()
        y_pred = a * torch.sin(x) + b * x + c
        loss = criterion(y_pred, y)
        loss.backward()
        optimizer.step()

    return {
        "a": round(a.item(), 4),
        "b": round(b.item(), 4),
        "c": round(c.item(), 4),
        "final_loss": round(loss.item(), 4),
    }


def assert_results(expected):
    assert os.path.isfile(RESULTS_PATH), f"Expected results file {RESULTS_PATH} does not exist."
    with open(RESULTS_PATH, "r") as handle:
        try:
            student_results = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

    expected_keys = {"a", "b", "c", "final_loss"}
    assert set(student_results.keys()) == expected_keys, (
        f"JSON keys in {RESULTS_PATH} do not match expected keys. "
        f"Expected {expected_keys}, got {set(student_results.keys())}"
    )
    for key in expected_keys:
        student_val = student_results[key]
        expected_val = expected[key]
        assert isinstance(student_val, (int, float)), f"Value for '{key}' must be a number."
        assert abs(student_val - expected_val) <= 1e-3, (
            f"Value for '{key}' is incorrect. Expected {expected_val}, got {student_val}."
        )


def write_dataset(xs, ys):
    with open(DATA_PATH, "w") as handle:
        handle.write("x,y\n")
        for x, y in zip(xs, ys):
            handle.write(f"{x},{y}\n")


def run_script(command):
    result = subprocess.run(
        command,
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"fit_model.py failed when executed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_audit():
    assert os.path.isfile(AUDIT_PATH), "Execution audit was not produced."
    with open(AUDIT_PATH, "r") as handle:
        audit = json.load(handle)

    assert audit["manual_seeds"] == [42], "The script must call torch.manual_seed(42) before initialization."
    assert len(audit["randn_calls"]) == 3, "Parameters must be initialized by exactly three torch.randn calls."
    assert all(call["shape_is_exact"] for call in audit["randn_calls"]), "Each parameter must use torch.randn(1, ...)."
    assert all(call["requires_grad_is_true"] for call in audit["randn_calls"]), "Each parameter must require gradients."
    assert all(call["dtype_is_float32"] for call in audit["randn_calls"]), "Each parameter must be float32."

    events = audit["events"]
    assert events.index("seed") < events.index("randn"), "The seed must be set before random initialization."

    optimizers = audit["optimizer_constructions"]
    assert len(optimizers) == 1, "The script must construct one SGD optimizer."
    assert abs(float(optimizers[0]["lr"]) - 0.05) < 1e-12, "SGD learning rate must be 0.05."
    assert optimizers[0]["parameter_ids"] == audit["parameter_ids"], (
        "The SGD parameters must be a, b, and c in their initialization order."
    )
    assert audit["mse_constructions"] == 1, "The script must construct torch.nn.MSELoss()."

    training_events = [event for event in events if event in {"loss", "zero_grad", "backward", "step"}]
    epochs = []
    current = []
    for event in training_events:
        current.append(event)
        if event == "step":
            epochs.append(current)
            current = []

    assert not current, "Training operations remained after the final optimizer step."
    assert len(epochs) == 500, f"Expected exactly 500 optimizer steps, got {len(epochs)}."
    for index, epoch in enumerate(epochs, 1):
        assert epoch.count("loss") == 1, f"Epoch {index} must calculate MSE loss exactly once."
        assert epoch.count("zero_grad") == 1, f"Epoch {index} must zero gradients exactly once."
        assert epoch.count("backward") == 1, f"Epoch {index} must backpropagate exactly once."
        assert epoch.count("step") == 1, f"Epoch {index} must step SGD exactly once."
        assert epoch.index("loss") < epoch.index("backward") < epoch.index("step"), (
            f"Epoch {index} has an invalid loss/backward/step order."
        )
        assert epoch.index("zero_grad") < epoch.index("backward"), (
            f"Epoch {index} must zero gradients before backpropagation."
        )


def test_script_pipeline_and_results():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    assert not os.path.islink(SCRIPT_PATH), f"Expected {SCRIPT_PATH} to be a regular submitted script, not a symlink."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as handle:
        source = handle.read()
    compile(source, SCRIPT_PATH, "exec")

    # Preserve the original verifier's assertion about the result left by the agent.
    assert_results(expected_results(ORIGINAL_X, ORIGINAL_Y))

    original_data = open(DATA_PATH, "rb").read()
    original_results = open(RESULTS_PATH, "rb").read()
    try:
        with open(AUDIT_RUNNER_PATH, "w") as handle:
            handle.write(AUDIT_RUNNER)
        if os.path.exists(AUDIT_PATH):
            os.remove(AUDIT_PATH)
        os.remove(RESULTS_PATH)
        run_script([sys.executable, AUDIT_RUNNER_PATH])
        assert_audit()
        assert_results(expected_results(ORIGINAL_X, ORIGINAL_Y))

        rng = secrets.SystemRandom()
        xs = [value / 10.0 for value in sorted(rng.sample(range(-45, 46), 9))]
        ys = [round(0.8 * x * x - 1.7 * x + rng.uniform(-2.0, 2.0), 6) for x in xs]
        write_dataset(xs, ys)
        os.remove(RESULTS_PATH)
        run_script([sys.executable, SCRIPT_PATH])
        assert_results(expected_results(xs, ys))
    finally:
        with open(DATA_PATH, "wb") as handle:
            handle.write(original_data)
        with open(RESULTS_PATH, "wb") as handle:
            handle.write(original_results)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
