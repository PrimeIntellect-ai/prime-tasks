#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import math
import os
import secrets
import shutil
import subprocess
import sys
import tempfile

PROJECT = "/home/user/geo_project"
GEO_PATH = os.path.join(PROJECT, "geo_math.py")
FUZZER_PATH = os.path.join(PROJECT, "fuzzer.py")
VERIFY_PATH = os.path.join(PROJECT, "verify.py")
SUCCESS_PATH = os.path.join(PROJECT, "success.txt")


def load_geo_math():
    assert os.path.isfile(GEO_PATH), f"The file {GEO_PATH} does not exist."
    spec = importlib.util.spec_from_file_location("submitted_geo_math", GEO_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_geo_math_assertions_and_behavior():
    with open(GEO_PATH, "r") as f:
        content = f.read()

    # Preserve the original exact-source assertions.
    assert 'assert isinstance(theta, float), "theta must be a float"' in content, "Missing or incorrect type assertion in geo_math.py."
    assert 'assert theta >= 0.0, "theta must be non-negative"' in content, "Missing or incorrect value assertion in geo_math.py."

    # Ensure those strings are actual leading assertions, not comments or dead text.
    tree = ast.parse(content, filename=GEO_PATH)
    funcs = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "compute_chord_length"]
    assert len(funcs) == 1, "compute_chord_length must be defined exactly once."
    body = funcs[0].body
    assert len(body) >= 2 and isinstance(body[0], ast.Assert) and isinstance(body[1], ast.Assert), \
        "The two required assertions must be the first statements in compute_chord_length."

    module = load_geo_math()
    fn = getattr(module, "compute_chord_length", None)
    assert callable(fn), "compute_chord_length is not callable."

    try:
        fn("string")
        raise AssertionError("Missing type assertion.")
    except AssertionError as e:
        assert "theta must be a float" in str(e), "Incorrect type assertion message."

    try:
        fn(-1.0)
        raise AssertionError("Missing value assertion.")
    except AssertionError as e:
        assert "theta must be non-negative" in str(e), "Incorrect value assertion message."

    rng = secrets.SystemRandom()
    test_vals = [0.0, 1e-10, 1e-9, 1e-8, 1e-7, 1.0, 3.14]
    test_vals += [10.0 ** rng.uniform(-10.0, -7.0) for _ in range(100)]
    test_vals += [rng.uniform(1e-7, math.pi) for _ in range(100)]

    for theta in test_vals:
        result = fn(float(theta))
        expected = 2.0 * math.sin(theta / 2.0)
        assert isinstance(result, (int, float)) and math.isfinite(result), f"Non-finite result for theta={theta}."
        assert math.isclose(result, expected, rel_tol=1e-12, abs_tol=0.0), \
            f"Incorrect chord length for theta={theta}: got {result}, expected {expected}."
        if theta > 0.0:
            assert result > 0.0, f"compute_chord_length returned a non-positive value for theta={theta}."


def run_instrumented_fuzzer(return_zero):
    with tempfile.TemporaryDirectory() as tmp:
        copied_fuzzer = os.path.join(tmp, "fuzzer.py")
        shutil.copyfile(FUZZER_PATH, copied_fuzzer)
        calls_path = os.path.join(tmp, "calls.json")
        fake_geo = os.path.join(tmp, "geo_math.py")
        with open(fake_geo, "w") as f:
            f.write('''import atexit\nimport json\nimport os\n_calls = []\ndef compute_chord_length(theta):\n    _calls.append(theta)\n    return 0.0 if os.environ.get("FAKE_ZERO") == "1" else theta\ndef _save():\n    with open(os.environ["CALLS_PATH"], "w") as out:\n        json.dump(_calls, out)\natexit.register(_save)\n''')

        env = os.environ.copy()
        env["CALLS_PATH"] = calls_path
        env["FAKE_ZERO"] = "1" if return_zero else "0"
        proc = subprocess.run(
            [sys.executable, copied_fuzzer], cwd=tmp, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert os.path.isfile(calls_path), f"The fuzzer did not call the instrumented compute_chord_length. stderr: {proc.stderr}"
        with open(calls_path, "r") as f:
            calls = json.load(f)
        return proc, calls


def test_fuzzer_script_exists_executes_and_finds_bug():
    assert os.path.isfile(FUZZER_PATH), f"The fuzzer script was not found at {FUZZER_PATH}."
    assert os.path.getsize(FUZZER_PATH) > 0, "The fuzzer script is empty."
    with open(FUZZER_PATH, "r") as f:
        content = f.read()
    assert len(content.strip()) > 0, "The fuzzer script only contains whitespace."

    # Execute the submitted artifact against the repaired implementation.
    real_run = subprocess.run(
        [sys.executable, FUZZER_PATH], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert real_run.returncode == 0, f"fuzzer.py failed against the repaired implementation: {real_run.stdout}{real_run.stderr}"

    # Instrument it to verify that it performs exactly 10,000 in-range trials.
    normal_run, calls = run_instrumented_fuzzer(False)
    assert normal_run.returncode == 0, f"fuzzer.py exited unsuccessfully on nonzero results: {normal_run.stdout}{normal_run.stderr}"
    assert len(calls) == 10000, f"fuzzer.py must test exactly 10,000 theta values; observed {len(calls)}."
    assert all(isinstance(v, (int, float)) and 1e-10 <= v <= 1e-7 for v in calls), \
        "Every theta generated by fuzzer.py must be in [1e-10, 1e-7]."
    assert len(set(calls)) > 1, "fuzzer.py must generate varying theta values rather than repeatedly testing one constant."

    # A forced zero must be reported and must stop the loop immediately.
    bug_run, bug_calls = run_instrumented_fuzzer(True)
    assert bug_run.returncode == 1, f"fuzzer.py must exit with code 1 when compute_chord_length returns 0.0; got {bug_run.returncode}."
    assert len(bug_calls) == 1, f"fuzzer.py did not exit immediately after finding a zero result; observed {len(bug_calls)} calls."
    assert "BUG FOUND:" in bug_run.stdout, "fuzzer.py did not print the required 'BUG FOUND: <theta>' message."


def test_verify_generates_correct_success_file():
    assert os.path.isfile(VERIFY_PATH), f"The verification script was not found at {VERIFY_PATH}."
    if os.path.exists(SUCCESS_PATH):
        os.remove(SUCCESS_PATH)

    proc = subprocess.run(
        [sys.executable, VERIFY_PATH], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert proc.returncode == 0, f"verify.py failed: {proc.stdout}{proc.stderr}"
    assert os.path.isfile(SUCCESS_PATH), f"The file {SUCCESS_PATH} was not generated by verify.py."

    test_vals = [1e-9, 1e-8, 1e-7, 1.0, 3.14]
    expected_lines = [f"{2.0 * math.sin(t / 2.0):.12e}" for t in test_vals]
    with open(SUCCESS_PATH, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in success.txt, got {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch on line {i+1} of success.txt: expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
