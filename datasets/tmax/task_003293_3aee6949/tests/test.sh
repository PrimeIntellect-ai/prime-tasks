#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hooks
cat << 'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import json
import numpy as np

_LOG = "/tmp/perf_profile_rng_calls.jsonl"
_real_default_rng = np.random.default_rng

def _jsonable(value):
    if isinstance(value, tuple):
        return list(value)
    if isinstance(value, np.generic):
        return value.item()
    return value

class _GeneratorProxy:
    def __init__(self, generator, seed):
        self._generator = generator
        self._seed = seed

    def normal(self, *args, **kwargs):
        loc = args[0] if len(args) > 0 else kwargs.get("loc", 0.0)
        scale = args[1] if len(args) > 1 else kwargs.get("scale", 1.0)
        size = args[2] if len(args) > 2 else kwargs.get("size", None)
        record = {
            "seed": _jsonable(self._seed),
            "loc": _jsonable(loc),
            "scale": _jsonable(scale),
            "size": _jsonable(size),
        }
        with open(_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")
        return self._generator.normal(*args, **kwargs)

    def __getattr__(self, name):
        return getattr(self._generator, name)

def _wrapped_default_rng(seed=None):
    return _GeneratorProxy(_real_default_rng(seed), seed)

np.random.default_rng = _wrapped_default_rng
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import subprocess
import sys

import numpy as np
import pytest
from scipy.stats import wasserstein_distance

SCRIPT = "/home/user/perf_profile/analyze_step.py"
OUTPUT = "/home/user/perf_profile/optimal_dt.txt"
RNG_LOG = "/tmp/perf_profile_rng_calls.jsonl"
DTS = [0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.001]


def _reference_result():
    initial = np.random.default_rng(42).normal(0, 1, (1000, 2))
    finals = {}
    with np.errstate(over="ignore", invalid="ignore"):
        for dt in DTS:
            x = initial[:, 0].copy()
            y = initial[:, 1].copy()
            for _ in range(round(5.0 / dt)):
                radius_term = 1.0 - x * x - y * y
                dx = y + x * radius_term
                dy = -x + y * radius_term
                x, y = x + dt * dx, y + dt * dy
            finals[dt] = x
    reference = finals[0.001]
    distances = {
        dt: wasserstein_distance(finals[dt], reference)
        for dt in DTS[:-1]
    }
    return max(dt for dt in DTS[:-1] if distances[dt] < 0.05)


def _contains_required_dt_sequence(tree):
    for node in ast.walk(tree):
        if isinstance(node, (ast.List, ast.Tuple)) and len(node.elts) == len(DTS):
            values = []
            for element in node.elts:
                try:
                    values.append(float(ast.literal_eval(element)))
                except (ValueError, TypeError, SyntaxError):
                    break
            if values == DTS:
                return True
    return False


def _has_vectorized_state_access(tree):
    for node in ast.walk(tree):
        if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Tuple):
            if any(isinstance(part, ast.Slice) for part in node.slice.elts):
                return True
        if isinstance(node, ast.Attribute) and node.attr == "T":
            return True
        if isinstance(node, ast.Call):
            name = node.func.attr if isinstance(node.func, ast.Attribute) else None
            if name in {"transpose", "split", "hsplit", "take"}:
                return True
    return False


def _uses_obvious_particle_loop(tree):
    for node in ast.walk(tree):
        if not isinstance(node, (ast.For, ast.comprehension)):
            continue
        iterator = node.iter
        if isinstance(iterator, ast.Call):
            name = iterator.func.id if isinstance(iterator.func, ast.Name) else None
            if name == "range":
                for arg in iterator.args:
                    if isinstance(arg, ast.Constant) and arg.value == 1000:
                        return True
                    if isinstance(arg, ast.Call) and isinstance(arg.func, ast.Name) and arg.func.id == "len":
                        return True
    return False


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT), f"Script file {SCRIPT} was not found."
    assert os.path.isfile(SCRIPT), f"Script file {SCRIPT} is not a regular file."

    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    assert _contains_required_dt_sequence(tree), "The required time-step sequence was not found in the script."
    assert _has_vectorized_state_access(tree), "No vectorized multidimensional state access was found."
    assert not _uses_obvious_particle_loop(tree), "The solver appears to loop over individual particles instead of vectorizing them."
    assert any(isinstance(node, (ast.For, ast.While)) for node in ast.walk(tree)), "No Forward Euler integration loop was found."

    for path in (OUTPUT, RNG_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = "/tmp/verifier_hooks" + ((":" + old_pythonpath) if old_pythonpath else "")
    completed = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user/perf_profile",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert completed.returncode == 0, (
        f"analyze_step.py exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    assert os.path.exists(RNG_LOG), "The script did not generate initial states through numpy.random.default_rng().normal()."
    with open(RNG_LOG, "r", encoding="utf-8") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert any(
        call.get("seed") == 42
        and float(call.get("loc")) == 0.0
        and float(call.get("scale")) == 1.0
        and call.get("size") == [1000, 2]
        for call in calls
    ), "The required default_rng(42).normal(0, 1, (1000, 2)) call was not executed."


def test_script_exists():
    """Check that the script was created."""
    assert os.path.exists(SCRIPT), f"Script file {SCRIPT} was not found."


def test_output_file_exists():
    """Check that the output file was created."""
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} was not found."


def test_optimal_dt_value():
    """Check that the optimal dt value is correct."""
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} was not found."

    with open(OUTPUT, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert re.fullmatch(r"(?:0|[1-9][0-9]*)(?:\.[0-9]+)?", content), (
        "The output must contain only one decimal value."
    )
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse '{content}' as a float.")

    expected = _reference_result()
    assert expected == 0.02, f"Verifier reference calculation unexpectedly produced {expected}."
    assert val == expected, f"Expected optimal dt to be {expected}, but got {val}."
    assert val == 0.02, f"Expected optimal dt to be 0.02, but got {val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
