#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import runpy
import subprocess
import sys
import types
import importlib.util

TICKET_DIR = "/home/user/ticket_4489"


def load_summarize():
    summarize_path = os.path.join(TICKET_DIR, "summarize.py")
    assert os.path.isfile(summarize_path), f"{summarize_path} is missing."
    spec = importlib.util.spec_from_file_location("ticket_4489_summarize", summarize_path)
    assert spec is not None and spec.loader is not None, "summarize.py is not a loadable Python module."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "sum_values", None)), "sum_values is missing or not callable."
    assert callable(getattr(module, "fast_process", None)), "fast_process is missing or not callable."
    return module


def test_resolution_file():
    res_path = os.path.join(TICKET_DIR, "resolution.txt")
    assert os.path.isfile(res_path), f"{res_path} is missing."
    with open(res_path, "r") as f:
        content = f.read().strip()
    assert content == "RESOLVED", f"Expected 'RESOLVED' in resolution.txt, got '{content}'."


def test_summarize_precision_fix():
    summarize = load_summarize()
    rng = random.SystemRandom()
    cases = [
        [0.1] * 10,
        [1e16, 1.0, -1e16],
        [1e100, 1.0, -1e100, 3.0],
        [2.0 ** -53] * 1001 + [1.0],
        [1.0, 1e-16, 1e-16, -1.0],
    ]
    for _ in range(30):
        length = rng.randint(5, 80)
        values = [rng.uniform(-1e8, 1e8) for _ in range(length)]
        values.extend([1e16, 1.0, -1e16])
        rng.shuffle(values)
        cases.append(values)

    for values in cases:
        expected = math.fsum(values)
        try:
            actual = summarize.sum_values(values)
        except Exception as exc:
            raise AssertionError(f"sum_values raised an exception for {values!r}: {exc}")
        assert isinstance(actual, float), "sum_values should return a float."
        assert actual == expected, (
            f"sum_values returned {actual!r}; exact floating-point result is {expected!r} "
            f"for input {values!r}."
        )


def invoke_fast_process(values):
    code = r'''
import importlib.util
import json
import os
import sys
path = os.path.join(sys.argv[1], "summarize.py")
spec = importlib.util.spec_from_file_location("summarize_child", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
values = json.loads(sys.stdin.read())
result = module.fast_process(values)
print("__RESULT__" + json.dumps({"value": result, "is_float": isinstance(result, float)}))
'''
    result = subprocess.run(
        [sys.executable, "-c", code, TICKET_DIR],
        input=json.dumps(values),
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"fast_process crashed or failed for length {len(values)} "
        f"(return code {result.returncode}). Stderr: {result.stderr}"
    )
    marker_lines = [line for line in result.stdout.splitlines() if line.startswith("__RESULT__")]
    assert marker_lines, f"Could not obtain fast_process result. Output: {result.stdout!r}"
    return json.loads(marker_lines[-1][len("__RESULT__"):])


def test_summarize_boundary_fix_and_results():
    rng = random.SystemRandom()
    cases = [
        [1.0] * 10,
        [1.0, 2.0, 3.0, 4.0, 5.0],
        [-4.5, 2.25, 8.0, -1.0, 3.5, 7.25],
    ]
    for _ in range(20):
        length = rng.randint(5, 50)
        cases.append([rng.uniform(-1000.0, 1000.0) for _ in range(length)])

    for values in cases:
        payload = invoke_fast_process(values)
        assert payload["is_float"], "fast_process should return a float."
        # The binary treats its integer argument as the last valid index: it reads
        # indices 0 through argument inclusive, then divides by that argument.
        expected = sum(values) / (len(values) - 1)
        assert payload["value"] == expected, (
            f"fast_process returned {payload['value']!r}, expected {expected!r} "
            f"for input {values!r}."
        )


def run_with_injected_summarize(script_path, fake_module):
    previous = sys.modules.get("summarize")
    previous_argv = sys.argv[:]
    sys.modules["summarize"] = fake_module
    sys.argv = [script_path]
    error = None
    try:
        runpy.run_path(script_path, run_name="__main__")
    except BaseException as exc:
        error = exc
    finally:
        sys.argv = previous_argv
        if previous is None:
            sys.modules.pop("summarize", None)
        else:
            sys.modules["summarize"] = previous
    return error


def run_script_normally(script_path):
    try:
        result = subprocess.run(
            [sys.executable, script_path],
            cwd=TICKET_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"{os.path.basename(script_path)} timed out: {exc}")
    assert result.returncode == 0, (
        f"{os.path.basename(script_path)} failed to run. Stderr: {result.stderr}"
    )


def test_regression_script():
    script_path = os.path.join(TICKET_DIR, "test_regression.py")
    assert os.path.isfile(script_path), f"{script_path} is missing."
    run_script_normally(script_path)

    calls = {"sum": 0, "fast": 0}
    fake = types.ModuleType("summarize")

    def wrong_sum(values):
        calls["sum"] += 1
        return 0.9999999999999999

    def good_fast(values):
        calls["fast"] += 1
        return 1.0

    fake.sum_values = wrong_sum
    fake.fast_process = good_fast
    error = run_with_injected_summarize(script_path, fake)
    assert calls["sum"] > 0, "Regression test does not call sum_values."
    assert error is not None, "Regression test does not reject an incorrect precision result."

    calls = {"sum": 0, "fast": 0}
    fake = types.ModuleType("summarize")

    def exact_sum(values):
        calls["sum"] += 1
        return 1.0

    def crashing_fast(values):
        calls["fast"] += 1
        raise RuntimeError("simulated C-library failure")

    fake.sum_values = exact_sum
    fake.fast_process = crashing_fast
    error = run_with_injected_summarize(script_path, fake)
    assert calls["fast"] > 0, "Regression test does not call fast_process."
    assert error is not None, "Regression test does not fail when fast_process fails."


def test_fuzzer_script():
    script_path = os.path.join(TICKET_DIR, "fuzzer.py")
    assert os.path.isfile(script_path), f"{script_path} is missing."
    run_script_normally(script_path)

    calls = {"sum": 0, "fast": 0}
    invalid_inputs = []
    fake = types.ModuleType("summarize")

    def validate(values):
        if not isinstance(values, list) or not 5 <= len(values) <= 50 or not all(isinstance(v, float) for v in values):
            invalid_inputs.append(values)

    def counted_sum(values):
        validate(values)
        calls["sum"] += 1
        return math.fsum(values)

    def counted_fast(values):
        validate(values)
        calls["fast"] += 1
        return 0.0

    fake.sum_values = counted_sum
    fake.fast_process = counted_fast
    error = run_with_injected_summarize(script_path, fake)
    assert error is None, f"fuzzer.py failed under call instrumentation: {error}"
    assert not invalid_inputs, "Fuzzer must generate lists of floats with lengths between 5 and 50."
    assert calls["sum"] >= 1000, f"Fuzzer called sum_values only {calls['sum']} times; expected at least 1000."
    assert calls["fast"] >= 1000, f"Fuzzer called fast_process only {calls['fast']} times; expected at least 1000."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
