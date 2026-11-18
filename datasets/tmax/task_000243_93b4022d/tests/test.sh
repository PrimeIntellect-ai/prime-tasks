#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import subprocess
import sys
import pytest

SCRIPT_PATH = "/home/user/video_processor.py"
OUTPUT_PATH = "/home/user/fixed_timestamps.json"


def load_module():
    spec = importlib.util.spec_from_file_location("video_processor", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, "Could not load video_processor.py."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_script_uses_non_recursive_loop_implementation():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Expected {SCRIPT_PATH} to be a file."

    with open(SCRIPT_PATH, "r") as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as e:
        pytest.fail(f"Failed to parse {SCRIPT_PATH}: {e}")

    functions = [
        node for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "get_timestamps"
    ]
    assert len(functions) == 1, "video_processor.py must define get_timestamps exactly once."
    function = functions[0]

    assert any(isinstance(node, (ast.For, ast.While)) for node in ast.walk(function)), (
        "get_timestamps must use a standard loop."
    )
    assert not any(
        isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node is not function
        for node in ast.walk(function)
    ), "get_timestamps must not use a nested recursive helper."
    assert not any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "get_timestamps"
        for node in ast.walk(function)
    ), "get_timestamps must not call itself recursively."
    assert not any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "setrecursionlimit"
        for node in ast.walk(tree)
    ), "The recursion-limit workaround must be removed rather than increased."


def test_get_timestamps_behavior():
    module = load_module()
    assert callable(getattr(module, "get_timestamps", None)), "get_timestamps must be callable."

    for duration, fps in [(5.0, 30), (2.0, 24), (1.25, 8), (3.0, 7)]:
        expected_frames = int(duration * fps)
        expected = [i / float(fps) for i in range(expected_frames)]
        actual = module.get_timestamps(duration, fps)

        assert isinstance(actual, list), "get_timestamps must return a list."
        assert len(actual) == expected_frames, (
            f"get_timestamps({duration}, {fps}) returned the wrong number of timestamps."
        )
        assert all(isinstance(value, float) for value in actual), (
            "get_timestamps must return timestamps as floats."
        )
        mse = sum((a - e) ** 2 for a, e in zip(actual, expected)) / expected_frames
        assert mse <= 1e-10, (
            f"get_timestamps({duration}, {fps}) has MSE {mse}, exceeding 1e-10."
        )


def test_fixed_timestamps_mse():
    output_path = "/home/user/fixed_timestamps.json"

    if os.path.lexists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Running {SCRIPT_PATH} failed with exit code {result.returncode}: {result.stderr}"
    )

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Expected {output_path} to be a file."

    try:
        with open(output_path, "r") as f:
            agent_ts = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to read or parse JSON from {output_path}: {e}")

    duration = 5.0
    fps = 30
    expected_frames = int(duration * fps)

    assert isinstance(agent_ts, list), "Output JSON must contain a list of floats."
    assert len(agent_ts) == expected_frames, f"Expected {expected_frames} timestamps, but got {len(agent_ts)}."
    assert all(isinstance(value, float) for value in agent_ts), "Output JSON must contain only floats."

    expected_ts = [i / float(fps) for i in range(expected_frames)]

    mse = sum((a - e) ** 2 for a, e in zip(agent_ts, expected_ts)) / expected_frames

    threshold = 1e-10
    assert mse <= threshold, f"MSE {mse} is greater than the allowed threshold of {threshold}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
