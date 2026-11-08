#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import math
import os
import subprocess
import uuid
from pathlib import Path

import numpy as np
import pytest
from scipy.stats import ttest_1samp


def run_filter(script_path: Path, target_file: Path) -> str:
    result = subprocess.run(
        ["python3", str(script_path), str(target_file)],
        capture_output=True,
        text=True,
        timeout=5
    )
    return result.stdout.strip()


def test_artifact_filter_exists():
    script_path = Path("/home/user/artifact_filter.py")
    assert script_path.exists(), f"Script missing at {script_path}"
    assert script_path.is_file(), f"Path {script_path} is not a file"


def test_clean_corpus_classification():
    script_path = Path("/home/user/artifact_filter.py")
    clean_dir = Path("/app/corpora/clean")
    assert clean_dir.exists() and clean_dir.is_dir(), "Clean corpus directory missing."

    json_files = list(clean_dir.glob("*.json"))
    assert len(json_files) > 0, "No JSON files in clean corpus."

    failures = []
    for json_file in json_files:
        output = run_filter(script_path, json_file)
        if output != "CLEAN":
            failures.append(f"{json_file.name} (output: {output!r})")

    if failures:
        pytest.fail(f"{len(failures)} of {len(json_files)} clean files modified/rejected (expected CLEAN): {', '.join(failures)}")


def test_evil_corpus_classification():
    script_path = Path("/home/user/artifact_filter.py")
    evil_dir = Path("/app/corpora/evil")
    assert evil_dir.exists() and evil_dir.is_dir(), "Evil corpus directory missing."

    json_files = list(evil_dir.glob("*.json"))
    assert len(json_files) > 0, "No JSON files in evil corpus."

    failures = []
    for json_file in json_files:
        output = run_filter(script_path, json_file)
        if output != "EVIL":
            failures.append(f"{json_file.name} (output: {output!r})")

    if failures:
        pytest.fail(f"{len(failures)} of {len(json_files)} evil files bypassed (expected EVIL): {', '.join(failures)}")


def test_generated_mixed_holdouts(tmp_path):
    script_path = Path("/home/user/artifact_filter.py")
    mixed_dir = tmp_path / uuid.uuid4().hex
    mixed_dir.mkdir()

    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    cases = []
    counts = {"CLEAN": 0, "EVIL": 0}

    # Generate opaque, mixed-label holdouts and derive every expected statistical
    # answer independently using the required two-tailed one-sample t-test.
    attempts = 0
    while min(counts.values()) < 10:
        attempts += 1
        assert attempts < 10000, "Unable to generate balanced holdouts"
        n = int(rng.integers(6, 161))
        sigma = float(np.exp(rng.uniform(math.log(0.15), math.log(10.0))))
        delta = float(rng.uniform(-4.0, 4.0))
        values = rng.normal(38.4 + delta, sigma, n).tolist()
        p_value = float(ttest_1samp(values, popmean=38.4).pvalue)
        if not math.isfinite(p_value) or abs(p_value - 0.01) < 0.003:
            continue
        expected = "EVIL" if p_value < 0.01 else "CLEAN"
        if counts[expected] >= 10:
            continue
        counts[expected] += 1
        cases.append(({"inference_times": values}, expected))

    # Exercise the explicitly required malformed-input rules in the same opaque
    # directory as both kinds of statistically valid input.
    cases.extend([
        ({}, "EVIL"),
        ({"inference_times": []}, "EVIL"),
        ({"inference_times": [38.4, "not-a-number", 38.5]}, "EVIL"),
        ({"inference_times": [38.4, None, 38.5]}, "EVIL"),
    ])
    rng.shuffle(cases)

    failures = []
    for payload, expected in cases:
        target = mixed_dir / f"{uuid.uuid4().hex}.json"
        target.write_text(json.dumps(payload), encoding="utf-8")
        output = run_filter(script_path, target)
        if output != expected:
            failures.append(f"{target.name}: expected {expected}, got {output!r}")

    if failures:
        pytest.fail("Generated holdout failures: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
