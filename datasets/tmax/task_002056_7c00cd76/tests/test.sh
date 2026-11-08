#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import resource
import subprocess
import sys
import tempfile
import time


def limit_resources():
    resource.setrlimit(resource.RLIMIT_AS, (256 * 1024 * 1024, 256 * 1024 * 1024))
    resource.setrlimit(resource.RLIMIT_CPU, (2, 2))


def test_report_content():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"{report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) >= 2, f"{report_path} must contain at least two lines."
    assert lines[0] == "REQ-103", f"Expected first line to be 'REQ-103', got '{lines[0]}'."
    assert lines[1] == "1.5", f"Expected second line to be '1.5', got '{lines[1]}'."
    assert len(lines) == 2, f"{report_path} must contain exactly two lines."


def test_test_suite_passes():
    test_suite_path = "/home/user/app/test_suite.py"
    assert os.path.isfile(test_suite_path), f"{test_suite_path} does not exist."

    result = subprocess.run(
        ["python3", test_suite_path],
        capture_output=True,
        text=True,
        timeout=5
    )

    assert result.returncode == 0, f"test_suite.py failed with error:\n{result.stderr}"
    assert "OK" in result.stdout, "test_suite.py did not print 'OK'."


def test_mre_execution_and_call():
    mre_path = "/home/user/mre.py"
    assert os.path.isfile(mre_path), f"{mre_path} does not exist."

    with open(mre_path, "r") as f:
        tree = ast.parse(f.read(), filename=mre_path)

    imported_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "app.processor":
            for name in node.names:
                if name.name == "compute_trajectory":
                    imported_names.add(name.asname or name.name)
    assert imported_names, "mre.py must import compute_trajectory from app.processor."

    has_exact_call = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in imported_names:
            if len(node.args) >= 2:
                try:
                    first = ast.literal_eval(node.args[0])
                    second = ast.literal_eval(node.args[1])
                except Exception:
                    continue
                if first == 2.0 and second == 1.5:
                    has_exact_call = True
    assert has_exact_call, "mre.py must call compute_trajectory with start_val=2.0 and lr=1.5."

    marker = tempfile.mktemp(prefix="mre_calls_", dir="/tmp")
    bootstrap = r'''
import json, os, runpy
import app.processor as processor
original = processor.compute_trajectory
marker = os.environ["MRE_CALL_MARKER"]
def wrapped(*args, **kwargs):
    with open(marker, "a") as f:
        f.write(json.dumps({"args": args, "kwargs": kwargs}) + "\n")
    return original(*args, **kwargs)
processor.compute_trajectory = wrapped
runpy.run_path("/home/user/mre.py", run_name="__main__")
'''
    env = os.environ.copy()
    env["MRE_CALL_MARKER"] = marker
    start_time = time.monotonic()
    result = subprocess.run(
        ["python3", "-c", bootstrap],
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        timeout=2.0,
        preexec_fn=limit_resources
    )
    execution_time = time.monotonic() - start_time

    assert result.returncode == 0, f"mre.py failed to execute:\n{result.stderr}"
    assert execution_time < 1.0, f"mre.py took too long to execute ({execution_time:.2f} seconds), it should finish in under 1 second."
    assert os.path.isfile(marker), "mre.py did not execute the imported compute_trajectory function."
    with open(marker) as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert any(call["args"] == [2.0, 1.5] and not call["kwargs"] for call in calls), \
        "mre.py did not execute compute_trajectory(2.0, 1.5)."


def test_processor_fix():
    processor_path = "/home/user/app/processor.py"
    assert os.path.isfile(processor_path), f"{processor_path} does not exist."

    with open(processor_path, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    has_isnan = "isnan" in content
    has_isinf = "isinf" in content
    assert has_isnan or has_isinf, "processor.py does not seem to contain checks for NaN or Inf as required."

    # Ensure both required math checks are executable calls, rather than comments or strings.
    tree = ast.parse(content, filename=processor_path)
    math_calls = set()
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and isinstance(node.func.value, ast.Name) and node.func.value.id == "math"
                and node.func.attr in {"isnan", "isinf"}):
            math_calls.add(node.func.attr)
    assert math_calls == {"isnan", "isinf"}, \
        "processor.py must call both math.isnan and math.isinf."

    behavioral_test = r'''
import math
import sys
sys.path.insert(0, "/home/user")
from app.processor import compute_trajectory

def check_prefix(history, start, lr):
    assert isinstance(history, list)
    assert history
    assert history[0] == float(start)
    for i in range(min(len(history) - 1, 12)):
        expected = history[i] - lr * (history[i] ** 2 - 2)
        assert history[i + 1] == expected

normal = compute_trajectory(1.0, 0.1)
check_prefix(normal, 1.0, 0.1)
assert len(normal) < 100

divergent = compute_trajectory(2.0, 1.5)
check_prefix(divergent, 2.0, 1.5)
assert len(divergent) < 1000

inf_history = compute_trajectory(float("inf"), 0.1)
nan_history = compute_trajectory(float("nan"), 0.1)
assert isinstance(inf_history, list) and len(inf_history) <= 1
assert isinstance(nan_history, list) and len(nan_history) <= 1
print("BEHAVIOR_OK")
'''
    result = subprocess.run(
        [sys.executable, "-c", behavioral_test],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=3,
        preexec_fn=limit_resources
    )
    assert result.returncode == 0, \
        f"processor.py failed independent behavioral checks:\n{result.stdout}\n{result.stderr}"
    assert "BEHAVIOR_OK" in result.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
