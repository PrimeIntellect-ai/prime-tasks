#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

import pytest

REPO = "/home/user/pipeline_repo"
DB = "/home/user/sensor_data.db"


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kwargs)
    if result.returncode != 0:
        raise RuntimeError(
            f"Command {cmd!r} failed with return code {result.returncode}. "
            f"Stdout: {result.stdout} Stderr: {result.stderr}"
        )
    return result


def get_output(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise RuntimeError(f"Command '{cmd}' failed with return code {result.returncode}. Stderr: {result.stderr}")
    try:
        value = float(result.stdout.strip())
    except ValueError:
        raise ValueError(f"Could not parse output of '{cmd}' as float. Output was: {result.stdout.strip()}")
    assert math.isfinite(value), f"Command '{cmd}' produced a non-finite value: {value}"
    return value


def stable_variance(values):
    count = 0
    mean = 0.0
    m2 = 0.0
    for value in values:
        count += 1
        delta = value - mean
        mean += delta / count
        m2 += delta * (value - mean)
    return m2 / (count - 1)


def write_database(values):
    if os.path.exists(DB):
        os.unlink(DB)
    conn = sqlite3.connect(DB)
    try:
        conn.execute("CREATE TABLE sensor_data (value REAL)")
        conn.executemany("INSERT INTO sensor_data VALUES (?)", [(v,) for v in values])
        conn.commit()
    finally:
        conn.close()


def test_bad_commit_file():
    bad_commit_path = "/home/user/bad_commit.txt"
    assert os.path.isfile(bad_commit_path), f"File {bad_commit_path} does not exist."

    with open(bad_commit_path, "r") as f:
        content = f.read().strip()

    assert re.match(r"^[0-9a-f]{40}$", content), f"File {bad_commit_path} does not contain a valid 40-character git commit hash. Found: '{content}'"

    commits = run(["git", "rev-list", "--reverse", "HEAD"], cwd=REPO).stdout.splitlines()
    expected = None
    for commit in commits:
        shown = subprocess.run(
            ["git", "show", f"{commit}:c_src/agg.c"],
            cwd=REPO,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if shown.returncode != 0:
            continue
        source = shown.stdout
        if "sum_sq" in source and "(sum_sq / count) - (mean * mean)" in source:
            expected = commit
            break

    assert expected is not None, "Could not locate the regression-introducing commit in repository history."
    assert content == expected, f"Incorrect first bad commit: expected {expected}, found {content}."


def test_build_fixed_extension():
    for artifact in glob.glob(os.path.join(REPO, "_fast_agg*.so")):
        os.unlink(artifact)
    run([sys.executable, "setup.py", "build_ext", "--inplace", "--force"], cwd=REPO)
    assert glob.glob(os.path.join(REPO, "_fast_agg*.so")), "Building the C extension did not create _fast_agg."


def test_pipeline_output_matches_oracle():
    oracle_val = get_output("/app/oracle_bin")
    agent_val = get_output("cd /home/user/pipeline_repo && python3 process_data.py")

    error = abs(oracle_val - agent_val)
    threshold = 1e-5

    assert error <= threshold, f"Numerical output mismatch! Oracle: {oracle_val}, Agent: {agent_val}, Absolute Error: {error} (Threshold: {threshold})"


def test_aggregation_on_unseen_inputs():
    sys.path.insert(0, REPO)
    if "_fast_agg" in sys.modules:
        del sys.modules["_fast_agg"]
    import _fast_agg

    rng = random.SystemRandom()
    datasets = [
        [1e12 + rng.uniform(-0.75, 0.75) for _ in range(613)],
        [1e8 + rng.gauss(0.0, 0.2) for _ in range(997)],
        [(-1.0 if i % 2 else 1.0) * 1e6 + rng.uniform(-2.0, 2.0) for i in range(401)],
    ]

    for values in datasets:
        expected = stable_variance(values)
        actual = float(_fast_agg.variance(values))
        assert math.isfinite(actual), "_fast_agg.variance returned a non-finite result."
        assert math.isclose(actual, expected, rel_tol=2e-9, abs_tol=5e-10), (
            f"_fast_agg.variance is numerically unstable on an unseen input: "
            f"expected {expected}, got {actual}"
        )


def test_pipeline_on_unseen_databases():
    fd, backup = tempfile.mkstemp(prefix="sensor_data_backup_", suffix=".db")
    os.close(fd)
    shutil.copy2(DB, backup)
    rng = random.SystemRandom()
    datasets = [
        [1e11 + rng.uniform(-0.4, 0.4) for _ in range(521)],
        [1e9 + rng.gauss(0.0, 0.05) for _ in range(733)],
    ]

    try:
        for values in datasets:
            write_database(values)
            expected = stable_variance(values)
            actual = get_output("cd /home/user/pipeline_repo && python3 process_data.py")
            assert math.isclose(actual, expected, rel_tol=2e-8, abs_tol=2e-8), (
                f"Pipeline output is incorrect on an unseen database: expected {expected}, got {actual}"
            )
    finally:
        if os.path.exists(DB):
            os.unlink(DB)
        shutil.move(backup, DB)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
