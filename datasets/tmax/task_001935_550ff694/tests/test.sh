#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import string
import subprocess
import tempfile

import pytest

BASELINE_PATH = "/home/user/baseline.txt"
FILTER_PATH = "/home/user/trace_filter"
FILTER_SOURCE = "/home/user/trace_filter.go"
ANALYZER_SOURCE = "/home/user/trace_analyzer.go"


def run_filter(path):
    try:
        return subprocess.run(
            [FILTER_PATH, path],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"trace_filter timed out on {path}")


def random_id(prefix):
    suffix = ''.join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=18))
    return prefix + suffix


def test_baseline_transcription():
    """Verify that the baseline audio was correctly transcribed."""
    assert os.path.exists(BASELINE_PATH), f"File {BASELINE_PATH} does not exist."

    with open(BASELINE_PATH, "r") as f:
        content = f.read().strip().splitlines()

    content = [line.strip() for line in content if line.strip()]
    expected = ["42.7", "-0.003", "812"]
    assert content == expected, f"Baseline transcription is incorrect. Expected {expected}, got {content}"


def test_trace_sources_exist_and_build():
    """Verify both requested Go programs exist and are compilable."""
    for source in (FILTER_SOURCE, ANALYZER_SOURCE):
        assert os.path.isfile(source), f"Required Go source {source} does not exist."
        with tempfile.TemporaryDirectory(prefix="go-build-") as td:
            output = os.path.join(td, "program")
            result = subprocess.run(
                ["go", "build", "-o", output, source],
                capture_output=True,
                text=True,
                timeout=30,
            )
            assert result.returncode == 0, f"{source} does not compile:\n{result.stderr}"

    with open(ANALYZER_SOURCE, "r", encoding="utf-8") as f:
        analyzer = f.read().lower()
    for field in ("parent_id", "duration_ns", "invocations"):
        assert field in analyzer, f"trace_analyzer.go does not process {field}"
    assert "/" in analyzer, "trace_analyzer.go does not calculate duration_ns / invocations"
    assert re.search(r"\bmap\s*\[|children|parent", analyzer), \
        "trace_analyzer.go does not contain call-graph reconstruction logic"


def test_trace_filter_exists():
    """Verify that the trace_filter binary was compiled."""
    assert os.path.exists(FILTER_PATH), f"Compiled binary {FILTER_PATH} does not exist."
    assert os.path.isfile(FILTER_PATH), f"Compiled binary {FILTER_PATH} is not a regular file."
    assert os.access(FILTER_PATH, os.X_OK), f"File {FILTER_PATH} is not executable."
    with open(FILTER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{FILTER_PATH} is not a compiled Linux executable."


def test_adversarial_corpus():
    """Retain validation against every provided clean and evil corpus file."""
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]

    assert len(clean_files) > 0, "No clean JSON files found to test."
    assert len(evil_files) > 0, "No evil JSON files found to test."

    clean_failed = [os.path.basename(f) for f in clean_files if run_filter(f) != 0]
    evil_failed = [os.path.basename(f) for f in evil_files if run_filter(f) == 0]

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")
    if errors:
        pytest.fail("Adversarial corpus validation failed:\n" + "\n".join(errors))


def test_filter_on_generated_unpredictable_traces():
    """Exercise graph and numerical validation using fresh paths, IDs, and values."""
    rng = random.SystemRandom()
    root = random_id("root_")
    child = random_id("child_")
    grandchild = random_id("grandchild_")
    other_root = random_id("other_")

    root_inv = rng.randint(1, 25)
    child_inv = rng.randint(1, 25)
    grand_inv = rng.randint(1, 25)
    valid = [
        {"id": root, "parent_id": "", "duration_ns": root_inv * rng.uniform(0.25, 5000.0), "invocations": root_inv},
        {"id": child, "parent_id": root, "duration_ns": child_inv * rng.uniform(0.25, 5000.0), "invocations": child_inv},
        {"id": grandchild, "parent_id": child, "duration_ns": grand_inv * rng.uniform(0.25, 5000.0), "invocations": grand_inv},
        {"id": other_root, "parent_id": "", "duration_ns": rng.uniform(0.25, 5000.0), "invocations": 1},
    ]
    assert all(math.isfinite(n["duration_ns"] / n["invocations"]) and
               n["duration_ns"] / n["invocations"] > 0 for n in valid)

    cycle_a, cycle_b, cycle_c = random_id("a_"), random_id("b_"), random_id("c_")
    invalid_cases = [
        [
            {"id": cycle_a, "parent_id": cycle_c, "duration_ns": rng.uniform(1, 1000), "invocations": 1},
            {"id": cycle_b, "parent_id": cycle_a, "duration_ns": rng.uniform(1, 1000), "invocations": 2},
            {"id": cycle_c, "parent_id": cycle_b, "duration_ns": rng.uniform(1, 1000), "invocations": 3},
        ],
        [{"id": random_id("self_"), "parent_id": "SELF_REPLACED", "duration_ns": 12.0, "invocations": 1}],
        [{"id": random_id("zero_inv_"), "parent_id": "", "duration_ns": rng.uniform(1, 1000), "invocations": 0}],
        [{"id": random_id("negative_inv_"), "parent_id": "", "duration_ns": rng.uniform(1, 1000), "invocations": -rng.randint(1, 9)}],
        [{"id": random_id("negative_duration_"), "parent_id": "", "duration_ns": -rng.uniform(0.01, 1000), "invocations": rng.randint(1, 9)}],
        [{"id": random_id("zero_cost_"), "parent_id": "", "duration_ns": 0.0, "invocations": rng.randint(1, 9)}],
        [{"id": random_id("missing_"), "parent_id": ""}],
    ]
    invalid_cases[1][0]["parent_id"] = invalid_cases[1][0]["id"]

    with tempfile.TemporaryDirectory(prefix="trace-validation-") as td:
        valid_path = os.path.join(td, random_id("valid_") + ".json")
        with open(valid_path, "w", encoding="utf-8") as f:
            json.dump(valid, f)
        assert run_filter(valid_path) == 0, "Generated valid forest was rejected"

        for index, trace in enumerate(invalid_cases):
            path = os.path.join(td, random_id(f"invalid_{index}_") + ".json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(trace, f)
            assert run_filter(path) != 0, f"Generated invalid trace {index} was accepted"

        overflow_path = os.path.join(td, random_id("overflow_") + ".json")
        with open(overflow_path, "w", encoding="utf-8") as f:
            f.write('[{"id":"x","parent_id":"","duration_ns":1e309,"invocations":1}]')
        assert run_filter(overflow_path) != 0, "Non-finite/overflowing duration was accepted"

        malformed_path = os.path.join(td, random_id("malformed_") + ".json")
        with open(malformed_path, "w", encoding="utf-8") as f:
            f.write('[{"id":')
        assert run_filter(malformed_path) != 0, "Malformed JSON was accepted"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
