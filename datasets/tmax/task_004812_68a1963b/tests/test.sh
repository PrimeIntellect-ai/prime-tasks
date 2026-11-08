#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import contextlib
import io
import json
import math
import os
import runpy
import subprocess
import sys

import numpy as np
import torch
from torch import nn

HOME = "/home/user"
CORPUS = os.path.join(HOME, "corpus.txt")
VOCAB = os.path.join(HOME, "vocab.json")
DATASET = os.path.join(HOME, "dataset.bin")
METRICS = os.path.join(HOME, "metrics.json")


def python_scripts():
    scripts = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in {"__pycache__", "site-packages"}]
        for name in files:
            if name.endswith(".py"):
                scripts.append(os.path.join(root, name))
    return sorted(scripts)


def execute_pipeline(scripts):
    env = os.environ.copy()
    env["PYTHONPATH"] = HOME + os.pathsep + env.get("PYTHONPATH", "")
    completed = 0
    errors = []
    # Two passes support a modular tokenizer/model pipeline regardless of filename order.
    for _ in range(2):
        for script in scripts:
            try:
                result = subprocess.run(
                    [sys.executable, script], cwd=HOME, env=env,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=120
                )
                if result.returncode == 0:
                    completed += 1
                else:
                    errors.append(f"{script}: {result.stderr[-500:]}")
            except subprocess.TimeoutExpired:
                errors.append(f"{script}: timed out")
    assert completed > 0, "No submitted Python script executed successfully: " + " | ".join(errors)


def expected_values(corpus_path=CORPUS, vocab_path=VOCAB):
    with open(corpus_path, "r") as f:
        text = f.read().strip()
    with open(vocab_path, "r") as f:
        vocab = json.load(f)
    tokens = text.split(" ") if text else []
    expected_ids = np.asarray([vocab.get(token, vocab["<unk>"]) for token in tokens], dtype=np.int32)

    torch.manual_seed(42)
    model = nn.Sequential(
        nn.Embedding(len(vocab), 16),
        nn.Linear(16, 8),
        nn.ReLU(),
    )
    first = torch.tensor(expected_ids[:100], dtype=torch.long)
    output = model(first)
    return expected_ids, float(output.mean().item()), float(output.std().item())


def validate_outputs():
    expected_ids, expected_mean, expected_std = expected_values()
    assert os.path.isfile(DATASET), "dataset.bin was not created by the submitted pipeline"
    assert os.path.getsize(DATASET) == expected_ids.size * 4
    actual_ids = np.memmap(DATASET, dtype=np.int32, mode="r", shape=(expected_ids.size,))
    assert np.array_equal(np.asarray(actual_ids), expected_ids), "dataset.bin does not contain the required token-to-ID mapping"

    assert os.path.isfile(METRICS), "metrics.json was not created by the submitted pipeline"
    with open(METRICS, "r") as f:
        metrics = json.load(f)
    assert set(metrics) == {"total_tokens", "output_mean", "output_std"}, "metrics.json must contain exactly the three requested keys"
    assert metrics["total_tokens"] == int(expected_ids.size)
    assert math.isclose(float(metrics["output_mean"]), expected_mean, rel_tol=0.0, abs_tol=1e-6)
    assert math.isclose(float(metrics["output_std"]), expected_std, rel_tol=0.0, abs_tol=1e-6)


def attr_name(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


def test_submitted_pipeline_on_derived_input_and_restore_original():
    scripts = python_scripts()
    assert scripts, "No Python model/pipeline script was found under /home/user"

    trees = []
    for script in scripts:
        with open(script, "r") as f:
            trees.append((script, ast.parse(f.read(), filename=script)))

    calls = [(script, node) for script, tree in trees for node in ast.walk(tree) if isinstance(node, ast.Call)]

    seed_calls = [node for _, node in calls if attr_name(node.func) in {"torch.manual_seed", "manual_seed"}]
    assert any(node.args and isinstance(node.args[0], ast.Constant) and node.args[0].value == 42 for node in seed_calls), "The script must call torch.manual_seed(42)"

    memmap_ok = False
    for _, node in calls:
        if attr_name(node.func).split(".")[-1] != "memmap":
            continue
        keywords = {kw.arg: kw.value for kw in node.keywords if kw.arg}
        dtype_node = keywords.get("dtype", node.args[1] if len(node.args) > 1 else None)
        mode_node = keywords.get("mode", node.args[2] if len(node.args) > 2 else None)
        dtype_ok = dtype_node is not None and attr_name(dtype_node).split(".")[-1] == "int32"
        mode_ok = isinstance(mode_node, ast.Constant) and mode_node.value == "w+"
        if dtype_ok and mode_ok:
            memmap_ok = True
    assert memmap_ok, "The pipeline must create dataset.bin with numpy.memmap(dtype=np.int32, mode='w+')"

    assert any(attr_name(node).endswith("torch.long") for _, tree in trees for node in ast.walk(tree)), "The script must convert input tokens using torch.long"
    assert any(attr_name(node.func).split(".")[-1] == "mean" for _, node in calls), "The script must calculate the output mean"
    assert any(attr_name(node.func).split(".")[-1] == "std" for _, node in calls), "The script must calculate the output standard deviation"

    with open(CORPUS, "rb") as f:
        original_corpus = f.read()
    with open(VOCAB, "rb") as f:
        original_vocab = f.read()

    challenge_vocab = {"alpha": 0, "beta": 1, "gamma": 2, "<unk>": 3}
    challenge_tokens = (["alpha", "missing", "beta", "gamma", "missing", "alpha", "beta"] * 20)[:137]

    try:
        with open(VOCAB, "w") as f:
            json.dump(challenge_vocab, f)
        with open(CORPUS, "w") as f:
            f.write(" ".join(challenge_tokens))
        for path in (DATASET, METRICS):
            if os.path.lexists(path):
                os.remove(path)
        execute_pipeline(scripts)
        validate_outputs()
    finally:
        with open(CORPUS, "wb") as f:
            f.write(original_corpus)
        with open(VOCAB, "wb") as f:
            f.write(original_vocab)

    for path in (DATASET, METRICS):
        if os.path.lexists(path):
            os.remove(path)
    execute_pipeline(scripts)
    validate_outputs()


def test_model_architecture_and_execution_order():
    scripts = python_scripts()
    with open(VOCAB, "r") as f:
        vocab = json.load(f)
    expected_ids, _, _ = expected_values()
    model_classes = []

    for script in scripts:
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                namespace = runpy.run_path(script, run_name="__verifier_inspection__")
        except BaseException:
            continue
        for obj in namespace.values():
            if isinstance(obj, type) and issubclass(obj, nn.Module) and obj is not nn.Module and obj.__module__ == "__verifier_inspection__":
                model_classes.append(obj)

    assert model_classes, "No torch.nn.Module subclass was found in the submitted script"
    input_tensor = torch.tensor(expected_ids[:100], dtype=torch.long)
    matched = False

    for cls in model_classes:
        instances = []
        for args, kwargs in [
            ((), {}),
            ((len(vocab),), {}),
            ((), {"vocab_size": len(vocab)}),
            ((), {"num_embeddings": len(vocab)}),
        ]:
            try:
                torch.manual_seed(42)
                instances.append(cls(*args, **kwargs))
                break
            except Exception:
                pass
        for model in instances:
            children = list(model.children())
            if len(children) != 3:
                continue
            if not (isinstance(children[0], nn.Embedding) and isinstance(children[1], nn.Linear) and isinstance(children[2], nn.ReLU)):
                continue
            if children[0].num_embeddings != len(vocab) or children[0].embedding_dim != 16:
                continue
            if children[1].in_features != 16 or children[1].out_features != 8:
                continue
            order = []
            hooks = [layer.register_forward_hook(lambda module, inp, out, i=i: order.append(i)) for i, layer in enumerate(children)]
            try:
                output = model(input_tensor)
            finally:
                for hook in hooks:
                    hook.remove()
            if order == [0, 1, 2] and tuple(output.shape) == (100, 8):
                matched = True
    assert matched, "Model must execute exactly Embedding(vocab size,16), Linear(16,8), then ReLU"


def test_dataset_bin():
    dataset_path = "/home/user/dataset.bin"
    assert os.path.isfile(dataset_path), "dataset.bin was not found in /home/user/"

    corpus_path = "/home/user/corpus.txt"
    assert os.path.isfile(corpus_path), "corpus.txt is missing"
    with open(corpus_path, "r") as f:
        text = f.read().strip()

    tokens = text.split(" ") if text else []
    expected_size = len(tokens) * 4
    actual_size = os.path.getsize(dataset_path)
    assert actual_size == expected_size, f"dataset.bin size is {actual_size} bytes, expected {expected_size} bytes (int32 = 4 bytes per token)"


def test_metrics_json():
    metrics_path = "/home/user/metrics.json"
    assert os.path.isfile(metrics_path), "metrics.json was not found in /home/user/"

    with open(metrics_path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, "metrics.json is not valid JSON"

    assert "total_tokens" in metrics, "metrics.json is missing 'total_tokens'"
    assert "output_mean" in metrics, "metrics.json is missing 'output_mean'"
    assert "output_std" in metrics, "metrics.json is missing 'output_std'"

    with open(CORPUS, "r") as f:
        text = f.read().strip()
    tokens = text.split(" ") if text else []
    expected_tokens = len(tokens)
    assert metrics["total_tokens"] == expected_tokens, f"Expected total_tokens to be {expected_tokens}, got {metrics['total_tokens']}"

    expected_mean = 0.1770634651184082
    expected_std = 0.22276535630226135
    actual_mean = float(metrics["output_mean"])
    actual_std = float(metrics["output_std"])
    assert math.isclose(actual_mean, expected_mean, abs_tol=1e-4), f"output_mean {actual_mean} is not within 1e-4 of expected {expected_mean}"
    assert math.isclose(actual_std, expected_std, abs_tol=1e-4), f"output_std {actual_std} is not within 1e-4 of expected {expected_std}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
