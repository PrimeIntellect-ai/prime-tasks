#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import copy
import importlib
import json
import os
import random
import secrets
import subprocess
import sys
import tempfile

import pytest
import requests

VENDORED_ROOT = "/app/pydatatransform-1.2.0"
URL = "http://127.0.0.1:8888/api/v1/diff"


def oracle_apply_diff(base_data, diff_data):
    result = copy.deepcopy(base_data)
    if not isinstance(diff_data, dict):
        return copy.deepcopy(diff_data)
    for key, value in diff_data.items():
        if isinstance(value, dict) and key in result and isinstance(result[key], dict):
            result[key] = oracle_apply_diff(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def get_process_rss(pid):
    """Return the RSS memory of the given PID in kilobytes."""
    with open(f"/proc/{pid}/status", "r") as f:
        for line in f:
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    return 0


def get_server_pid(port):
    """Find the PID of the process listening on the given port."""
    try:
        output = subprocess.check_output(["ss", "-lptn"], stderr=subprocess.DEVNULL).decode()
        for line in output.splitlines():
            if f":{port}" in line and "LISTEN" in line:
                parts = line.split("pid=")
                if len(parts) > 1:
                    return int(parts[1].split(",")[0])
    except Exception:
        pass
    return None


def _literal_value(node, bindings):
    if isinstance(node, ast.Name) and node.id in bindings:
        return _literal_value(bindings[node.id], bindings)
    if isinstance(node, ast.Subscript):
        container = _literal_value(node.value, bindings)
        index = _literal_value(node.slice, bindings)
        return container[index]
    return ast.literal_eval(node)


def test_mre_exists_and_runs():
    mre_path = "/home/user/mre.py"
    assert os.path.isfile(mre_path), f"MRE script missing at {mre_path}"

    # Preserve the original assertion: the MRE must run successfully against the real package.
    result = subprocess.run([sys.executable, mre_path], capture_output=True, text=True)
    assert result.returncode == 0, f"MRE script failed to run. Stderr: {result.stderr}"

    source = open(mre_path, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=mre_path)
    function_aliases = set()
    module_aliases = set()
    bindings = {}

    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "pydatatransform":
            for name in node.names:
                if name.name == "apply_diff":
                    function_aliases.add(name.asname or name.name)
        elif isinstance(node, ast.Import):
            for name in node.names:
                if name.name == "pydatatransform":
                    module_aliases.add(name.asname or "pydatatransform")
        elif isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            bindings[node.targets[0].id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.value is not None:
            bindings[node.target.id] = node.value

    calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in function_aliases:
            calls.append(node)
        elif (isinstance(node.func, ast.Attribute) and node.func.attr == "apply_diff"
              and isinstance(node.func.value, ast.Name)
              and node.func.value.id in module_aliases):
            calls.append(node)

    assert function_aliases or module_aliases, "MRE must directly import pydatatransform/apply_diff"
    assert len(calls) == 1, f"MRE must contain exactly one direct apply_diff call, found {len(calls)}"

    call = calls[0]
    arguments = list(call.args)
    keyword_arguments = {kw.arg: kw.value for kw in call.keywords if kw.arg is not None}
    base_node = arguments[0] if len(arguments) > 0 else keyword_arguments.get("base_data")
    diff_node = arguments[1] if len(arguments) > 1 else keyword_arguments.get("diff_data")
    assert base_node is not None and diff_node is not None, "MRE must pass base and diff payloads"
    try:
        base_value = _literal_value(base_node, bindings)
        diff_value = _literal_value(diff_node, bindings)
    except Exception as exc:
        pytest.fail(f"MRE payload must be hardcoded: {exc}")
    assert isinstance(base_value, dict) and isinstance(diff_value, dict), "MRE mock payload must contain hardcoded dictionaries"

    # Execute with an instrumented module to prove the direct call is actually reached once.
    record_fd, record_path = tempfile.mkstemp(prefix="mre_calls_", suffix=".json")
    os.close(record_fd)
    wrapper = r'''
import copy, json, os, runpy, sys, types
calls = []
def oracle(base, diff):
    result = copy.deepcopy(base)
    if not isinstance(diff, dict):
        return copy.deepcopy(diff)
    for k, v in diff.items():
        if isinstance(v, dict) and k in result and isinstance(result[k], dict):
            result[k] = oracle(result[k], v)
        else:
            result[k] = copy.deepcopy(v)
    return result
def checked_apply_diff(base_data, diff_data):
    calls.append([base_data, diff_data])
    return oracle(base_data, diff_data)
pkg = types.ModuleType("pydatatransform")
pkg.__path__ = []
pkg.apply_diff = checked_apply_diff
core = types.ModuleType("pydatatransform.core")
core.apply_diff = checked_apply_diff
sys.modules["pydatatransform"] = pkg
sys.modules["pydatatransform.core"] = core
code = 0
try:
    runpy.run_path(sys.argv[1], run_name="__main__")
except SystemExit as exc:
    code = exc.code if isinstance(exc.code, int) else (0 if exc.code is None else 1)
finally:
    with open(os.environ["MRE_RECORD"], "w") as f:
        json.dump({"calls": calls, "code": code}, f)
if code:
    raise SystemExit(code)
'''
    env = os.environ.copy()
    env["MRE_RECORD"] = record_path
    instrumented = subprocess.run([sys.executable, "-c", wrapper, mre_path], env=env,
                                  capture_output=True, text=True)
    try:
        assert instrumented.returncode == 0, f"Instrumented MRE failed: {instrumented.stderr}"
        with open(record_path, "r") as f:
            record = json.load(f)
        assert len(record["calls"]) == 1, f"MRE executed apply_diff {len(record['calls'])} times instead of once"
    finally:
        os.unlink(record_path)


def _random_json(rng, depth=0):
    if depth >= 3:
        return rng.choice([None, rng.randint(-100000, 100000), secrets.token_hex(4), bool(rng.randrange(2))])
    choice = rng.randrange(4)
    if choice == 0:
        return {secrets.token_hex(3): _random_json(rng, depth + 1) for _ in range(rng.randrange(1, 4))}
    if choice == 1:
        return [_random_json(rng, depth + 1) for _ in range(rng.randrange(0, 4))]
    return rng.choice([None, rng.randint(-100000, 100000), secrets.token_hex(5), bool(rng.randrange(2))])


def _recursive_case(rng):
    shared = secrets.token_hex(5)
    nested = secrets.token_hex(5)
    replaced = secrets.token_hex(5)
    added = secrets.token_hex(5)
    base = {
        shared: {
            nested: {"keep": _random_json(rng), replaced: _random_json(rng)},
            "untouched": _random_json(rng),
        },
        "top_untouched": _random_json(rng),
        "type_change": [_random_json(rng)],
    }
    diff = {
        shared: {
            nested: {replaced: _random_json(rng), added: _random_json(rng)},
            "new_sibling": _random_json(rng),
        },
        "type_change": {"now": "a dictionary", secrets.token_hex(3): _random_json(rng)},
        secrets.token_hex(5): _random_json(rng),
    }
    return base, diff


def test_vendored_apply_diff_matches_oracle_and_does_not_retain_inputs():
    sys.path.insert(0, VENDORED_ROOT)
    for name in list(sys.modules):
        if name == "pydatatransform" or name.startswith("pydatatransform."):
            del sys.modules[name]
    package = importlib.import_module("pydatatransform")
    core = importlib.import_module("pydatatransform.core")
    assert os.path.realpath(package.__file__).startswith(os.path.realpath(VENDORED_ROOT) + os.sep)

    history = getattr(core, "_audit_history", None)
    history_size = len(history) if isinstance(history, list) else None
    rng = random.SystemRandom()
    for _ in range(80):
        base, diff = _recursive_case(rng)
        original_base = copy.deepcopy(base)
        original_diff = copy.deepcopy(diff)
        expected = oracle_apply_diff(base, diff)
        actual = package.apply_diff(base, diff)
        assert actual == expected
        assert base == original_base, "apply_diff mutated its base input"
        assert diff == original_diff, "apply_diff mutated its diff input"

    if history_size is not None:
        assert len(history) <= history_size, "apply_diff still retains request payloads in _audit_history"


def test_server_running_and_correct():
    payload = {"base": {"key": "value1"}, "diff": {"key": "value2"}}

    try:
        response = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {URL}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except Exception:
        pytest.fail(f"Failed to parse JSON response: {response.text}")

    assert data == {"key": "value2"}, f"Expected merged dictionary {{'key': 'value2'}}, got {data}"


def test_server_handles_general_recursive_diffs():
    rng = random.SystemRandom()
    for _ in range(25):
        base, diff = _recursive_case(rng)
        expected = oracle_apply_diff(base, diff)
        response = requests.post(URL, json={"base": base, "diff": diff}, timeout=3)
        assert response.status_code == 200
        assert response.json() == expected


def test_server_memory_leak_fixed():
    pid = get_server_pid(8888)
    assert pid is not None, "Could not find server process listening on port 8888"

    payload = {"base": {"key": "value1", "other": "data"}, "diff": {"key": "value2", "new": "data"}}

    # Warm up
    for _ in range(10):
        requests.post(URL, json=payload)

    initial_rss = get_process_rss(pid)
    assert initial_rss > 0, "Could not read initial RSS memory"

    # Send 2000 requests
    for _ in range(2000):
        response = requests.post(URL, json=payload)
        assert response.status_code == 200

    final_rss = get_process_rss(pid)

    # Check that memory hasn't grown by more than 5MB (5120 KB)
    growth = final_rss - initial_rss
    assert growth < 5120, f"Memory leak detected: RSS grew by {growth} KB (from {initial_rss} to {final_rss} KB)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
