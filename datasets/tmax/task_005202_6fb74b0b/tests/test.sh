#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import random
import subprocess
import sys

import pytest

SERVICE_DIR = "/home/user/audio_service"
SOLUTION_PATH = os.path.join(SERVICE_DIR, "solution.py")
MATH_CORE_PATH = os.path.join(SERVICE_DIR, "math_core.py")
REQUIREMENTS_PATH = os.path.join(SERVICE_DIR, "requirements.txt")
ORACLE_PATH = "/app/bin/oracle_audio_sig"

INITIAL_MATH_CORE = """from typing import List

def compute_signature(audio_array: List[float]) -> List[float]:
    denominator = 1.0 - sum(audio_array)
    return [x / denominator for x in audio_array]
"""


def expected_signature(values):
    denominator = 1.0 - sum(values)
    if abs(denominator) < 1e-9:
        denominator = -1e-9 if denominator < 0 else 1e-9
    return [value / denominator for value in values]


def test_solution_file_exists():
    assert os.path.isfile(SOLUTION_PATH), "The file /home/user/audio_service/solution.py is missing."


def test_math_core_was_fixed_and_wrapper_imports_it():
    assert os.path.isfile(MATH_CORE_PATH), "math_core.py is missing"
    with open(MATH_CORE_PATH, "r", encoding="utf-8") as handle:
        math_source = handle.read()
    assert math_source != INITIAL_MATH_CORE, "math_core.py was not modified"

    with open(SOLUTION_PATH, "r", encoding="utf-8") as handle:
        solution_source = handle.read()
    tree = ast.parse(solution_source, filename=SOLUTION_PATH)
    imports_compute_signature = any(
        isinstance(node, ast.ImportFrom)
        and node.module == "math_core"
        and any(alias.name == "compute_signature" for alias in node.names)
        for node in ast.walk(tree)
    )
    imports_math_core = any(
        isinstance(node, ast.Import)
        and any(alias.name == "math_core" for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imports_compute_signature or imports_math_core, (
        "solution.py must import the fixed implementation from math_core.py"
    )


def test_requirements_resolve():
    assert os.path.isfile(REQUIREMENTS_PATH), "requirements.txt is missing"
    with open(REQUIREMENTS_PATH, "r", encoding="utf-8") as handle:
        requirements = handle.read()
    assert requirements.strip(), "requirements.txt is empty"
    assert requirements.strip().splitlines() != [
        "numpy==1.22.0", "scipy>=1.8.0", "audio_core"
    ], "requirements.txt still contains the original unresolved dependency set"

    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--dry-run",
         "--disable-pip-version-check", "-r", REQUIREMENTS_PATH],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        "requirements.txt does not resolve successfully:\n" + result.stdout + result.stderr
    )


def test_compute_signature_directly():
    sys.path.insert(0, SERVICE_DIR)
    try:
        sys.modules.pop("math_core", None)
        from math_core import compute_signature
    finally:
        sys.path.pop(0)

    cases = [
        [0.5, 0.5],
        [1.0],
        [0.5000000005, 0.5],
        [0.5000000015, 0.5],
        [-1.0, 0.25, 0.125],
        [0.0] * 16,
    ]
    rng = random.Random(99173)
    for _ in range(100):
        cases.append([round(rng.uniform(-1.0, 1.0), 6)
                      for _ in range(rng.randint(1, 40))])

    for values in cases:
        result = compute_signature(list(values))
        expected = expected_signature(values)
        assert isinstance(result, list), "compute_signature must return a list"
        assert len(result) == len(expected), "compute_signature returned the wrong length"
        assert all(isinstance(value, (int, float)) and math.isfinite(float(value))
                   for value in result), "compute_signature returned a non-finite value"
        assert result == expected, (
            f"compute_signature is not bit-exact for {values!r}: "
            f"expected {expected!r}, got {result!r}"
        )


def test_fuzz_equivalence():
    oracle_path = ORACLE_PATH
    agent_script = SOLUTION_PATH

    assert os.path.isfile(oracle_path), f"Oracle program missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle program at {oracle_path} is not executable"

    random.seed(42)
    N = 1000

    for i in range(N):
        length = random.randint(10, 100)
        inputs = [str(round(random.uniform(-1.0, 1.0), 6)) for _ in range(length)]

        if i == 0:
            inputs = ["0.5", "0.5"] + ["0.0"] * 8

        oracle_cmd = [oracle_path] + inputs
        agent_cmd = ["python3", agent_script] + inputs

        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True,
                                        timeout=2, check=True)
            oracle_output = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as error:
            pytest.fail(f"Oracle failed on input: {' '.join(inputs)}\nError: {error.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: {' '.join(inputs)}")

        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, timeout=2)
            agent_output = agent_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: {' '.join(inputs)}")

        if agent_res.returncode != 0:
            pytest.fail(f"Agent script crashed on input: {' '.join(inputs)}\nError: {agent_res.stderr}")

        oracle_tokens = oracle_output.split()
        agent_tokens = agent_output.split()

        if len(oracle_tokens) != len(agent_tokens):
            pytest.fail(f"Output length mismatch on input: {' '.join(inputs)}\nOracle: {oracle_output}\nAgent: {agent_output}")

        for j, (o_tok, a_tok) in enumerate(zip(oracle_tokens, agent_tokens)):
            try:
                o_val = float(o_tok)
                a_val = float(a_tok)
                if not math.isfinite(a_val):
                    pytest.fail(
                        f"Non-finite agent output at index {j} on input: {' '.join(inputs)}\n"
                        f"Agent token: {a_tok}"
                    )
                if o_tok != a_tok and abs(o_val - a_val) > 1e-6:
                    pytest.fail(f"Mismatch at index {j} on input: {' '.join(inputs)}\nOracle: {o_tok}\nAgent: {a_tok}\nFull Oracle: {oracle_output}\nFull Agent: {agent_output}")
            except ValueError:
                if o_tok != a_tok:
                    pytest.fail(f"Mismatch at index {j} (non-float) on input: {' '.join(inputs)}\nOracle: {o_tok}\nAgent: {a_tok}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
