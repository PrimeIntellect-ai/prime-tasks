#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import secrets
from pathlib import Path

import pytest
import requests
import numpy as np
import torch
import torch.nn as nn
from scipy import stats

BASE_URL = "http://127.0.0.1:8000"


def get_expected_data():
    np.random.seed(42)
    feat_0_19 = np.random.rand(1000, 20)
    feat_20 = np.random.normal(loc=3.5, scale=0.8, size=(1000, 1))
    data = np.hstack([feat_0_19, feat_20]).astype(np.float32)
    return data, feat_20.flatten()


def get_expected_stats(feat_20):
    res = stats.ttest_1samp(feat_20, popmean=0.0)
    p_value = res.pvalue
    ci_lower, ci_upper = stats.t.interval(
        0.95,
        df=len(feat_20) - 1,
        loc=np.mean(feat_20),
        scale=stats.sem(feat_20),
    )
    return p_value, ci_lower, ci_upper


def get_expected_embeddings(data):
    torch.manual_seed(42)
    model = nn.Sequential(
        nn.Linear(21, 128),
        nn.ReLU(),
        nn.Linear(128, 64),
        nn.ReLU(),
    )
    with torch.no_grad():
        embeddings = model(torch.tensor(data))
    return embeddings / embeddings.norm(dim=1, keepdim=True)


def get_expected_recommendations(data, item_id=0):
    embeddings = get_expected_embeddings(data)
    sims = torch.mm(embeddings, embeddings.t())[item_id].clone()
    sims[item_id] = -float("inf")
    return torch.topk(sims, 5).indices.tolist()


def listening_server_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                try:
                    port = int(fields[1].rsplit(":", 1)[1], 16)
                except ValueError:
                    continue
                if port == 8000:
                    inodes.add(fields[9])
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                if os.readlink(fd) in {f"socket:[{inode}]" for inode in inodes}:
                    return int(proc.name)
        except (OSError, PermissionError):
            pass
    return None


def authored_python_sources(pid):
    paths = set()
    roots = {Path("/app"), Path("/home/user")}
    try:
        cwd = Path(os.readlink(f"/proc/{pid}/cwd"))
        if cwd != Path("/"):
            roots.add(cwd)
        cmd = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        args = [x.decode(errors="ignore") for x in cmd if x]
    except OSError:
        args = []
        cwd = Path("/")

    app_dir = cwd
    for i, arg in enumerate(args[:-1]):
        if arg == "--app-dir":
            app_dir = Path(args[i + 1])

    for arg in args:
        if arg.endswith(".py"):
            p = Path(arg)
            paths.add(p if p.is_absolute() else cwd / p)
        match = re.fullmatch(r"([A-Za-z_]\w*(?:\.[A-Za-z_]\w)*):[A-Za-z_]\w*", arg)
        if match:
            paths.add(app_dir / (match.group(1).replace(".", "/") + ".py"))

    for root in roots:
        if root.is_dir():
            try:
                for p in root.rglob("*.py"):
                    if not any(part in {"site-packages", ".venv", "venv", "__pycache__"} for part in p.parts):
                        paths.add(p)
            except OSError:
                pass

    result = []
    for p in paths:
        try:
            if p.is_file() and p.stat().st_size <= 1_000_000:
                result.append((p, p.read_text(errors="ignore")))
        except OSError:
            pass
    return result


def call_name(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


def literal_number(node, assigned):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.Name):
        return assigned.get(node.id)
    return None


def test_pipeline_source_exists_and_contains_required_pipeline():
    pid = listening_server_pid()
    assert pid is not None, "No process is listening on port 8000"
    sources = authored_python_sources(pid)
    assert sources, "No Python pipeline/server source file was found"

    trees = []
    for path, source in sources:
        try:
            trees.append((path, source, ast.parse(source)))
        except SyntaxError:
            continue
    assert trees, "No valid Python pipeline/server source file was found"

    combined = "\n".join(source.lower() for _, source, _ in trees)
    assert "recommend" in combined and "stats" in combined, "Server source must implement both required endpoints"
    assert "tesseract" in combined or "pytesseract" in combined, "Pipeline source does not perform OCR"

    calls = []
    constants = set()
    assigned = {}
    for _, _, tree in trees:
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
                constants.add(node.value)
            if isinstance(node, (ast.Assign, ast.AnnAssign)):
                value = node.value
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                if isinstance(value, ast.Constant) and isinstance(value.value, (int, float)):
                    for target in targets:
                        if isinstance(target, ast.Name):
                            assigned[target.id] = value.value
            if isinstance(node, ast.Call):
                calls.append(node)

    named_calls = [(call_name(c.func), c) for c in calls]
    assert any(name.endswith("seed") and c.args and literal_number(c.args[0], assigned) == 42
               and not name.endswith("manual_seed") for name, c in named_calls), "numpy random seed 42 is missing"
    assert any(name.endswith("manual_seed") and c.args and literal_number(c.args[0], assigned) == 42
               for name, c in named_calls), "torch manual seed 42 is missing"
    assert any(name.split(".")[-1] in {"rand", "random", "uniform"} for name, _ in named_calls), "Uniform feature generation is missing"
    assert any(name.endswith("normal") for name, _ in named_calls), "Normal feature generation is missing"
    assert 1000 in constants and 20 in constants and 21 in constants, "Required dataset dimensions are missing"
    assert any(name.endswith("ReLU") for name, _ in named_calls), "ReLU hidden activations are missing"
    assert any(name.endswith("Linear") for name, _ in named_calls), "PyTorch Linear layers are missing"

    has_output_10 = False
    for name, call in named_calls:
        if not name.endswith("Linear"):
            continue
        if len(call.args) >= 2 and literal_number(call.args[1], assigned) == 10:
            has_output_10 = True
        for kw in call.keywords:
            if kw.arg == "out_features" and literal_number(kw.value, assigned) == 10:
                has_output_10 = True
    assert has_output_10, "The required final 10-dimensional Linear output layer is missing"
    assert any(name.endswith("ttest_1samp") for name, _ in named_calls), "The required one-sample t-test is missing"
    assert any(name.endswith("interval") or name.endswith("ppf") for name, _ in named_calls), "t-distribution confidence interval calculation is missing"


def test_stats_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/stats", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/stats: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    data_json = response.json()
    assert "p_value" in data_json, "Missing 'p_value' in response"
    assert "ci_lower" in data_json, "Missing 'ci_lower' in response"
    assert "ci_upper" in data_json, "Missing 'ci_upper' in response"

    _, feat_20 = get_expected_data()
    expected_p, expected_ci_lower, expected_ci_upper = get_expected_stats(feat_20)
    assert abs(data_json["p_value"] - expected_p) < 1e-5 or (data_json["p_value"] < 1e-10 and expected_p < 1e-10), \
        f"p_value mismatch. Expected ~{expected_p}, got {data_json['p_value']}"
    assert abs(data_json["ci_lower"] - expected_ci_lower) < 1e-2, \
        f"ci_lower mismatch. Expected {expected_ci_lower}, got {data_json['ci_lower']}"
    assert abs(data_json["ci_upper"] - expected_ci_upper) < 1e-2, \
        f"ci_upper mismatch. Expected {expected_ci_upper}, got {data_json['ci_upper']}"


def test_recommend_endpoint():
    data, _ = get_expected_data()
    embeddings = get_expected_embeddings(data)

    # Retain the original fixed assertion for item 0.
    item_ids = [0]
    # Add verifier-time unpredictable coverage across the rest of the dataset.
    item_ids.extend(secrets.SystemRandom().sample(range(1, 1000), 16))

    for item_id in item_ids:
        try:
            response = requests.get(f"{BASE_URL}/recommend?item_id={item_id}", timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to {BASE_URL}/recommend for item {item_id}: {e}")

        assert response.status_code == 200, f"Expected status code 200 for item {item_id}, got {response.status_code}"
        data_json = response.json()
        assert "similar_items" in data_json, "Missing 'similar_items' in response"

        actual = data_json["similar_items"]
        assert isinstance(actual, list) and len(actual) == 5, "similar_items must be a list of five IDs"
        assert all(isinstance(x, int) and 0 <= x < 1000 for x in actual), "similar_items contains an invalid ID"
        assert item_id not in actual and len(set(actual)) == 5, "similar_items must be unique and exclude the query item"

        sims = torch.mm(embeddings, embeddings.t())[item_id].clone()
        sims[item_id] = -float("inf")
        expected_top5 = torch.topk(sims, 5).indices.tolist()
        assert actual == expected_top5, \
            f"similar_items mismatch for item {item_id}. Expected {expected_top5}, got {actual}"
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
