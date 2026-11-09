#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import shutil
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/bayes_pipeline"
METRICS = "/home/user/benchmark_metrics.json"
SOURCE = os.path.join(PROJECT, "src/main.rs")

ORIGINAL_DATA = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0]

DATA_DECLARATION = re.compile(
    r"let\s+data(?:\s*:\s*Vec\s*<\s*f64\s*>)?\s*=\s*"
    r"vec!\s*\[\s*10(?:\.0)?\s*,\s*20(?:\.0)?\s*,\s*30(?:\.0)?\s*,"
    r"\s*40(?:\.0)?\s*,\s*50(?:\.0)?\s*,\s*60(?:\.0)?\s*,"
    r"\s*70(?:\.0)?\s*,\s*80(?:\.0)?\s*,\s*90(?:\.0)?\s*,"
    r"\s*100(?:\.0)?\s*\]\s*;"
)


def run_cargo(project):
    return subprocess.run(
        ["cargo", "run", "--release"],
        cwd=project,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )


def read_metrics():
    assert os.path.isfile(METRICS), (
        "The file /home/user/benchmark_metrics.json was not found. "
        "Did you run 'cargo run --release' successfully?"
    )
    with open(METRICS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/benchmark_metrics.json is not valid JSON.")


def expected_values(data):
    train_data = data[:8]
    test_data = data[8:]
    mean = sum(train_data) / len(train_data)
    variance = sum((x - mean) ** 2 for x in train_data) / len(train_data)
    std_dev = math.sqrt(variance)
    return [(x - mean) / std_dev for x in test_data]


def assert_normalized(metrics, expected):
    assert "test_set_normalized" in metrics, (
        "The key 'test_set_normalized' is missing from benchmark_metrics.json"
    )
    normalized_test = metrics["test_set_normalized"]
    assert isinstance(normalized_test, list), "test_set_normalized should be a list"
    assert len(normalized_test) == 2, "test_set_normalized should contain exactly 2 elements"
    for actual, wanted in zip(normalized_test, expected):
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
        assert math.isclose(actual, wanted, rel_tol=1e-5), (
            f"Data leakage bug not fixed correctly. Expected normalized value close to {wanted}, "
            f"but got {actual}."
        )


def make_variant(data):
    with open(SOURCE, "r") as f:
        source = f.read()
    replacement = "let data: Vec<f64> = vec![" + ", ".join(repr(x) for x in data) + "];"
    modified, count = DATA_DECLARATION.subn(replacement, source, count=1)
    assert count == 1, "Could not locate the required hardcoded dataset in src/main.rs"

    tempdir = tempfile.mkdtemp(prefix="bayes_pipeline_verify_")
    shutil.copy2(os.path.join(PROJECT, "Cargo.toml"), os.path.join(tempdir, "Cargo.toml"))
    lockfile = os.path.join(PROJECT, "Cargo.lock")
    if os.path.isfile(lockfile):
        shutil.copy2(lockfile, os.path.join(tempdir, "Cargo.lock"))
    os.mkdir(os.path.join(tempdir, "src"))
    with open(os.path.join(tempdir, "src/main.rs"), "w") as f:
        f.write(modified)
    return tempdir


def test_project_is_compiled_and_run():
    if os.path.exists(METRICS):
        os.remove(METRICS)
    result = run_cargo(PROJECT)
    assert result.returncode == 0, (
        "cargo run --release failed.\nstdout:\n"
        + result.stdout
        + "\nstderr:\n"
        + result.stderr
    )
    assert os.path.isfile(METRICS), (
        "The application did not generate /home/user/benchmark_metrics.json"
    )


def test_benchmark_metrics_exists():
    assert os.path.isfile(METRICS), (
        "The file /home/user/benchmark_metrics.json was not found. "
        "Did you run 'cargo run --release' successfully?"
    )


def test_data_leakage_fixed():
    metrics = read_metrics()
    assert_normalized(metrics, expected_values(ORIGINAL_DATA))


def test_schema_enforcement_remains():
    assert os.path.isfile(SOURCE), "src/main.rs is missing"
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "<= 0.0" in content, "Schema enforcement (checking for <= 0.0) appears to be removed."
    assert "panic!" in content, "Schema enforcement panic appears to be removed."


def test_pipeline_uses_training_statistics_on_derived_data():
    variants = [
        [3.0, 7.0, 12.0, 18.0, 25.0, 33.0, 42.0, 52.0, 63.0, 75.0],
        [101.0, 104.0, 109.0, 116.0, 125.0, 136.0, 149.0, 164.0, 181.0, 200.0],
    ]
    for data in variants:
        tempdir = make_variant(data)
        try:
            if os.path.exists(METRICS):
                os.remove(METRICS)
            result = run_cargo(tempdir)
            assert result.returncode == 0, (
                "The pipeline failed on a derived positive dataset.\nstdout:\n"
                + result.stdout
                + "\nstderr:\n"
                + result.stderr
            )
            assert_normalized(read_metrics(), expected_values(data))
        finally:
            shutil.rmtree(tempdir, ignore_errors=True)


def test_schema_enforcement_is_executed():
    invalid_data = [-10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0]
    tempdir = make_variant(invalid_data)
    try:
        if os.path.exists(METRICS):
            os.remove(METRICS)
        result = run_cargo(tempdir)
        assert result.returncode != 0, (
            "The application accepted a non-positive value; schema enforcement is not active"
        )
        assert not os.path.exists(METRICS), (
            "The application wrote metrics despite the schema violation"
        )
    finally:
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
