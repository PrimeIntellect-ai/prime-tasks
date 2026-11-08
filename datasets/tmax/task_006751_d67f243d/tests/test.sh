#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import uuid

import pytest

PIPELINE_DIR = "/home/user/artifact_pipeline"


def test_makefile_exists_and_runs():
    makefile_path = os.path.join(PIPELINE_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile is missing in {PIPELINE_DIR}"

    # Run make ci-run to ensure it executes successfully
    result = subprocess.run(["make", "ci-run"], cwd=PIPELINE_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"'make ci-run' failed with exit code {result.returncode}.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"


def test_artifacts_json_is_patched():
    artifacts_path = os.path.join(PIPELINE_DIR, "artifacts.json")
    assert os.path.isfile(artifacts_path), f"File {artifacts_path} is missing."

    with open(artifacts_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {artifacts_path} is not valid JSON.")

    # Find build-102 and verify it was patched
    build_102 = next((item for item in data if item.get("id") == "build-102"), None)
    assert build_102 is not None, "build-102 is missing from artifacts.json"

    assert build_102.get("coverage") == 0.95, "artifacts.json was not properly patched: coverage for build-102 should be 0.95"
    assert build_102.get("complexity") == 3, "artifacts.json was not properly patched: complexity for build-102 should be 3"


def test_approved_txt_content():
    approved_path = os.path.join(PIPELINE_DIR, "approved.txt")
    assert os.path.isfile(approved_path), f"{approved_path} does not exist. Ensure scorer.py generates it."

    with open(approved_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["build-101", "build-102"]
    assert set(lines) == set(expected), f"approved.txt does not contain the expected artifact IDs. Expected {expected}, got {lines}"
    assert len(lines) == len(expected), "approved.txt contains duplicate or extra lines."


def test_scorer_parses_formula_and_scores_runtime_inputs():
    scorer_path = os.path.join(PIPELINE_DIR, "scorer.py")
    artifacts_path = os.path.join(PIPELINE_DIR, "artifacts.json")
    formula_path = os.path.join(PIPELINE_DIR, "formula.txt")
    approved_path = os.path.join(PIPELINE_DIR, "approved.txt")

    assert os.path.isfile(scorer_path), f"scorer.py is missing in {PIPELINE_DIR}"

    with open(artifacts_path, "rb") as f:
        original_artifacts = f.read()
    with open(formula_path, "rb") as f:
        original_formula = f.read()
    approved_existed = os.path.exists(approved_path)
    original_approved = None
    if approved_existed:
        with open(approved_path, "rb") as f:
            original_approved = f.read()

    # Values and IDs are generated at verification time. The expression uses every
    # required operator, including mathematical exponentiation via '^'.
    rng = random.SystemRandom()
    desired_scores = [rng.uniform(15.0, 45.0), rng.uniform(55.0, 75.0), rng.uniform(80.0, 120.0)]
    runtime_artifacts = []
    expected = []
    for desired in desired_scores:
        coverage = rng.uniform(0.1, 4.0)
        complexity = rng.randint(1, 6)
        tests_passed = ((desired + 7.0) * (complexity ** 2) / 3.0) - coverage
        artifact_id = "runtime-" + uuid.uuid4().hex
        runtime_artifacts.append({
            "id": artifact_id,
            "coverage": coverage,
            "complexity": complexity,
            "tests_passed": tests_passed,
        })
        calculated = ((coverage + tests_passed) * 3.0) / (complexity ** 2) - 7.0
        if calculated > 50.0:
            expected.append(artifact_id)

    try:
        with open(artifacts_path, "w") as f:
            json.dump(runtime_artifacts, f)
        with open(formula_path, "w") as f:
            f.write("((coverage + tests_passed) * 3) / (complexity ^ 2) - 7\n")
        if os.path.exists(approved_path):
            os.unlink(approved_path)

        result = subprocess.run(
            ["python3", scorer_path], cwd=PIPELINE_DIR, capture_output=True, text=True
        )
        assert result.returncode == 0, (
            f"scorer.py failed on valid runtime inputs.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )
        assert os.path.isfile(approved_path), "scorer.py did not create approved.txt"
        with open(approved_path, "r") as f:
            actual = [line.strip() for line in f if line.strip()]
        assert set(actual) == set(expected), f"scorer.py produced {actual}; expected {expected}"
        assert len(actual) == len(expected), "scorer.py wrote duplicate or extra approval lines"
    finally:
        with open(artifacts_path, "wb") as f:
            f.write(original_artifacts)
        with open(formula_path, "wb") as f:
            f.write(original_formula)
        if approved_existed:
            with open(approved_path, "wb") as f:
                f.write(original_approved)
        elif os.path.exists(approved_path):
            os.unlink(approved_path)


def test_ci_run_actually_invokes_scorer():
    scorer_path = os.path.join(PIPELINE_DIR, "scorer.py")
    approved_path = os.path.join(PIPELINE_DIR, "approved.txt")
    marker_path = "/tmp/scorer-invoked-" + uuid.uuid4().hex

    assert os.path.isfile(scorer_path), f"scorer.py is missing in {PIPELINE_DIR}"
    with open(scorer_path, "rb") as f:
        original_scorer = f.read()
    original_mode = stat.S_IMODE(os.stat(scorer_path).st_mode)
    approved_existed = os.path.exists(approved_path)
    original_approved = None
    if approved_existed:
        with open(approved_path, "rb") as f:
            original_approved = f.read()

    replacement = f'''#!/usr/bin/env python3
from pathlib import Path
Path({marker_path!r}).write_text("invoked")
Path({approved_path!r}).write_text("build-101\\nbuild-102\\n")
'''

    try:
        with open(scorer_path, "w") as f:
            f.write(replacement)
        os.chmod(scorer_path, 0o755)
        if os.path.exists(approved_path):
            os.unlink(approved_path)

        result = subprocess.run(
            ["make", "-B", "ci-run"], cwd=PIPELINE_DIR, capture_output=True, text=True
        )
        assert result.returncode == 0, (
            f"'make ci-run' failed during invocation check.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )
        assert os.path.isfile(marker_path), "The ci-run target did not execute scorer.py"
    finally:
        with open(scorer_path, "wb") as f:
            f.write(original_scorer)
        os.chmod(scorer_path, original_mode)
        if os.path.exists(marker_path):
            os.unlink(marker_path)
        if approved_existed:
            with open(approved_path, "wb") as f:
                f.write(original_approved)
        elif os.path.exists(approved_path):
            os.unlink(approved_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
