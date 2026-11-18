#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import random
import re
import secrets
import subprocess
from collections import Counter
from functools import lru_cache

import numpy as np
import pytest
from scipy.stats import wasserstein_distance

ALL_RUNS = "/home/user/all_runs.txt"
DISTANCE_SCRIPT = "/home/user/distance.py"
RESULT = "/home/user/result.txt"


@lru_cache(maxsize=1)
def expected_runs_and_distance():
    lines = []
    success_conds = []
    fail_conds = []

    for seed in range(1, 1001):
        np.random.seed(seed)
        A = np.random.randn(50, 50)
        if seed % 7 == 0:
            A[1] = A[0] + np.random.randn(50) * 1e-14

        cond = np.linalg.cond(A)
        if cond > 1e11:
            lines.append(f"FAIL {cond}")
            fail_conds.append(cond)
        else:
            lines.append(f"SUCCESS {cond}")
            success_conds.append(cond)

    distance = round(wasserstein_distance(success_conds, fail_conds), 2)
    return lines, distance


def read_result():
    assert os.path.isfile(RESULT), f"The file {RESULT} does not exist."
    with open(RESULT, "r") as f:
        content = f.read().strip()

    number_pattern = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
    assert re.fullmatch(number_pattern, content), (
        f"{RESULT} must contain only one numeric result; found: {content!r}"
    )
    value = float(content)
    assert math.isfinite(value), f"The result must be finite, but got {content!r}."
    return value


def test_all_runs_txt():
    assert os.path.exists(ALL_RUNS), f"The file {ALL_RUNS} does not exist."

    with open(ALL_RUNS, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 1000, (
        f"Expected exactly 1000 lines in {ALL_RUNS}, but found {len(lines)}."
    )

    success_count = sum(1 for line in lines if line.startswith("SUCCESS"))
    fail_count = sum(1 for line in lines if line.startswith("FAIL"))
    assert success_count + fail_count == 1000, (
        "All lines must start with either 'SUCCESS' or 'FAIL'."
    )

    expected_lines, _ = expected_runs_and_distance()
    assert Counter(lines) == Counter(expected_lines), (
        "all_runs.txt does not contain exactly the outputs produced for seeds 1 through 1000."
    )


def test_distance_script_exists_and_uses_scipy():
    assert os.path.exists(DISTANCE_SCRIPT), (
        f"The python script {DISTANCE_SCRIPT} does not exist."
    )
    assert os.path.isfile(DISTANCE_SCRIPT), f"{DISTANCE_SCRIPT} is not a regular file."
    assert os.path.getsize(DISTANCE_SCRIPT) > 0, f"{DISTANCE_SCRIPT} is empty."

    with open(DISTANCE_SCRIPT, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=DISTANCE_SCRIPT)

    direct_names = set()
    scipy_imported = False
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            if node.module == "scipy.stats":
                for alias in node.names:
                    if alias.name == "wasserstein_distance":
                        direct_names.add(alias.asname or alias.name)
            if node.module == "scipy" and any(a.name == "stats" for a in node.names):
                scipy_imported = True
        elif isinstance(node, ast.Import):
            if any(a.name in ("scipy", "scipy.stats") for a in node.names):
                scipy_imported = True

    called = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in direct_names:
            called = True
        if (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == "wasserstein_distance"
            and scipy_imported
        ):
            called = True

    assert called, "distance.py must call scipy.stats.wasserstein_distance."


def test_result_txt():
    assert os.path.exists(RESULT), f"The file {RESULT} does not exist."
    _, expected_distance = expected_runs_and_distance()
    actual_distance = read_result()
    assert actual_distance == expected_distance, (
        f"Expected Wasserstein distance {expected_distance}, but got {actual_distance}."
    )


def test_distance_script_parses_input_and_generates_result():
    with open(ALL_RUNS, "rb") as f:
        original_runs = f.read()
    original_result = None
    if os.path.exists(RESULT):
        with open(RESULT, "rb") as f:
            original_result = f.read()

    rng = random.Random(secrets.randbits(128))
    cases = []
    for _ in range(3):
        success = [rng.uniform(0.1, 5000.0) for _ in range(rng.randint(4, 10))]
        fail = [rng.uniform(7000.0, 25000.0) for _ in range(rng.randint(3, 9))]
        rows = [f"SUCCESS {x:.12g}" for x in success]
        rows += [f"FAIL {x:.12g}" for x in fail]
        rng.shuffle(rows)
        parsed_success = [float(row.split()[1]) for row in rows if row.startswith("SUCCESS")]
        parsed_fail = [float(row.split()[1]) for row in rows if row.startswith("FAIL")]
        expected = round(wasserstein_distance(parsed_success, parsed_fail), 2)
        cases.append((rows, expected))

    try:
        for rows, expected in cases:
            with open(ALL_RUNS, "w") as f:
                f.write("\n".join(rows) + "\n")
            if os.path.exists(RESULT):
                os.remove(RESULT)

            completed = subprocess.run(
                ["python3", DISTANCE_SCRIPT],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert completed.returncode == 0, (
                "distance.py failed when executed.\n"
                f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )
            actual = read_result()
            assert actual == expected, (
                f"distance.py produced {actual}, expected {expected} for supplied input."
            )
    finally:
        with open(ALL_RUNS, "wb") as f:
            f.write(original_runs)
        if original_result is None:
            if os.path.exists(RESULT):
                os.remove(RESULT)
        else:
            with open(RESULT, "wb") as f:
                f.write(original_result)

    completed = subprocess.run(
        ["python3", DISTANCE_SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "distance.py failed on all_runs.txt.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    _, expected_distance = expected_runs_and_distance()
    assert read_result() == expected_distance
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
