#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

EVIL_CORPUS_PATH = "/app/corpus/evil/"
CLEAN_CORPUS_PATH = "/app/corpus/clean/"
DETECTOR_SCRIPT = "/home/user/analysis/detector.py"
VERDICT_JSON = "/home/user/analysis/verdict.json"


def run_detector(corpus_path):
    assert os.path.exists(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector path is not a file: {DETECTOR_SCRIPT}"

    # Remove previous verdict.json if it exists to ensure we are reading fresh output.
    if os.path.exists(VERDICT_JSON):
        os.remove(VERDICT_JSON)

    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, corpus_path],
        capture_output=True,
        text=True,
        timeout=30,
    )

    assert result.returncode == 0, (
        f"Detector script failed on {corpus_path}:\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert os.path.exists(VERDICT_JSON), (
        f"Detector script did not produce {VERDICT_JSON} for {corpus_path}"
    )

    with open(VERDICT_JSON, "r") as f:
        try:
            verdict = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse {VERDICT_JSON} as JSON")

    assert isinstance(verdict, dict), "verdict.json must contain a JSON object"
    return verdict


def test_evil_corpus():
    verdict = run_detector(EVIL_CORPUS_PATH)

    evil_files = [f for f in os.listdir(EVIL_CORPUS_PATH) if f.endswith('.dat')]
    assert len(evil_files) > 0, f"No .dat files found in {EVIL_CORPUS_PATH}"

    bypassed_files = []
    for f in evil_files:
        if verdict.get(f) != "evil":
            bypassed_files.append(f)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_files)}")


def test_clean_corpus():
    verdict = run_detector(CLEAN_CORPUS_PATH)

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_PATH) if f.endswith('.dat')]
    assert len(clean_files) > 0, f"No .dat files found in {CLEAN_CORPUS_PATH}"

    modified_files = []
    for f in clean_files:
        if verdict.get(f) != "clean":
            modified_files.append(f)

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified (incorrectly classified). Offending files: {', '.join(modified_files)}")


def test_opaque_mixed_corpus():
    # Use an unpredictable, label-neutral path and filenames so labels cannot be
    # inferred from the corpus path. Values are freshly generated from the same
    # clean/evil domains as the shipped examples.
    corpus_path = tempfile.mkdtemp(prefix="corpus_" + secrets.token_hex(8) + "_", dir="/tmp")
    expected = {}

    try:
        samples = []

        for _ in range(8):
            values = [secrets.SystemRandom().uniform(0.25, 9.0) for _ in range(3)]
            samples.append(values)

        for i in range(8):
            rng = secrets.SystemRandom()
            if i % 3 == 0:
                values = [0.0, 0.0, 0.0]
            elif i % 3 == 1:
                values = [-rng.uniform(0.25, 9.0) for _ in range(3)]
            else:
                values = [-rng.uniform(0.25, 9.0), 0.0, -rng.uniform(0.25, 9.0)]
            samples.append(values)

        secrets.SystemRandom().shuffle(samples)
        for values in samples:
            filename = secrets.token_hex(12) + ".dat"
            with open(os.path.join(corpus_path, filename), "w") as f:
                f.write(", ".join(f"{value:.10f}" for value in values) + "\n")

            # Labels are derived from the generated mathematical domain, not
            # from a directory or filename convention.
            expected[filename] = "clean" if all(value > 0 for value in values) else "evil"

        verdict = run_detector(corpus_path)
        wrong = [
            filename for filename, label in expected.items()
            if verdict.get(filename) != label
        ]
        if wrong:
            pytest.fail(
                f"{len(wrong)} of {len(expected)} payloads in the opaque mixed corpus "
                f"were classified incorrectly. Offending files: {', '.join(wrong)}"
            )
    finally:
        shutil.rmtree(corpus_path, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
