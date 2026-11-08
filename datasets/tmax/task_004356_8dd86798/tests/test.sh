#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/filter.sh"
SCORER_PATH = "/app/anomaly_scorer"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"


def test_script_exists_and_executable():
    """Verify that the student's script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    # Even if not executable, we run it with `bash`, but it's good practice to check if it's a file


def test_clean_corpus_preserved():
    """Verify that all clean logs are accepted (exit code 0)."""
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus directory missing: {CLEAN_CORPUS}"

    clean_files = [
        os.path.join(CLEAN_CORPUS, f)
        for f in os.listdir(CLEAN_CORPUS)
        if os.path.isfile(os.path.join(CLEAN_CORPUS, f))
    ]
    assert len(clean_files) > 0, f"No files found in clean corpus directory: {CLEAN_CORPUS}"

    modified = []
    for filepath in clean_files:
        result = subprocess.run(["bash", SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            modified.append(os.path.basename(filepath))

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified: {', '.join(modified)}")


def test_evil_corpus_rejected():
    """Verify that all evil logs are rejected (exit code 1)."""
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus directory missing: {EVIL_CORPUS}"

    evil_files = [
        os.path.join(EVIL_CORPUS, f)
        for f in os.listdir(EVIL_CORPUS)
        if os.path.isfile(os.path.join(EVIL_CORPUS, f))
    ]
    assert len(evil_files) > 0, f"No files found in evil corpus directory: {EVIL_CORPUS}"

    bypassed = []
    for filepath in evil_files:
        result = subprocess.run(["bash", SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed.append(os.path.basename(filepath))

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def derive_features(path):
    with open(path, "r", encoding="utf-8") as f:
        rows = [line.rstrip("\n").split(",") for line in f]

    assert rows and all(len(row) == 4 for row in rows)
    errors = {row[2] for row in rows if row[2] not in ("", "0", "None")}
    retries = [int(row[3]) for row in rows]
    return len(rows), len(errors), max(retries)


def make_log(path, n, unique_errors, max_retries, rng):
    codes = [str(400 + i * 7 + rng.randrange(0, 5)) for i in range(unique_errors)]
    error_values = list(codes)
    fillers = codes + ["", "0", "None"]
    while len(error_values) < n:
        error_values.append(fillers[(len(error_values) - unique_errors) % len(fillers)])

    retries = [rng.randint(0, max_retries) for _ in range(n)]
    retries[rng.randrange(n)] = max_retries
    rows = [
        f"{1700000000 + i},{'EVENT_' + str(rng.randrange(1, 20))},{error_values[i]},{retries[i]}"
        for i in range(n)
    ]
    rng.shuffle(rows)
    with open(path, "w", encoding="utf-8", newline="") as f:
        for row in rows:
            f.write(row + "\n")


@pytest.fixture
def instrumented_scorer():
    assert os.path.isfile(SCORER_PATH), f"Scoring model missing: {SCORER_PATH}"
    assert os.access(SCORER_PATH, os.X_OK), f"Scoring model is not executable: {SCORER_PATH}"

    token = uuid.uuid4().hex
    backup = f"/app/.anomaly_scorer.verify.{token}"
    trace = f"/tmp/.scorer_trace.{token}"
    os.replace(SCORER_PATH, backup)

    wrapper = f'''#!/usr/bin/python3
import json
import subprocess
import sys
BACKUP = {backup!r}
TRACE = {trace!r}
with open(TRACE, "a", encoding="utf-8") as out:
    out.write(json.dumps(sys.argv[1:]) + "\\n")
result = subprocess.run([BACKUP] + sys.argv[1:])
sys.exit(result.returncode)
'''
    with open(SCORER_PATH, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(SCORER_PATH, 0o755)

    try:
        yield backup, trace
    finally:
        try:
            os.unlink(SCORER_PATH)
        except FileNotFoundError:
            pass
        if os.path.exists(backup):
            os.replace(backup, SCORER_PATH)
        try:
            os.unlink(trace)
        except FileNotFoundError:
            pass


def test_generated_logs_are_parsed_and_scored(instrumented_scorer):
    """Exercise unpredictable paths and verify exact features reach the real model."""
    backup, trace = instrumented_scorer
    rng = random.SystemRandom()
    workdir = tempfile.mkdtemp(prefix=f"telemetry-{uuid.uuid4().hex}-")

    # Includes a rounded score of exactly 0.75, clearly anomalous and clean cases,
    # plus randomized feature combinations and ignored error-code values.
    specs = [(8, 2, 1), (3, 2, 8), (20, 0, 0), (15, 3, 2)]
    for _ in range(8):
        n = rng.randint(4, 35)
        specs.append((n, rng.randint(0, min(7, n)), rng.randint(0, 12)))

    seen_expected = set()
    try:
        for index, (n, errors, retries) in enumerate(specs):
            path = os.path.join(workdir, f"sample-{uuid.uuid4().hex}-{index}.csv")
            make_log(path, n, errors, retries, rng)
            features = derive_features(path)

            model = subprocess.run(
                [backup, *(str(value) for value in features)],
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert model.returncode == 0, "The supplied scoring model failed"
            score = float(model.stdout.strip())
            assert 0.0 <= score <= 1.0
            expected = 1 if score > 0.75 else 0
            seen_expected.add(expected)

            with open(trace, "w", encoding="utf-8"):
                pass
            result = subprocess.run(
                ["bash", SCRIPT_PATH, path],
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert result.returncode == expected, (
                f"Wrong decision for generated log with features {features} "
                f"and model score {score:.2f}: expected exit {expected}, got {result.returncode}"
            )

            with open(trace, "r", encoding="utf-8") as f:
                calls = [json.loads(line) for line in f if line.strip()]
            wanted_call = [str(value) for value in features]
            assert calls == [wanted_call], (
                f"Expected exactly one anomaly_scorer invocation with {wanted_call}, got {calls}"
            )

        assert seen_expected == {0, 1}, "Generated tests must cover both decisions"
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
