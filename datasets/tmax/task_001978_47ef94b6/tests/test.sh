#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import secrets
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest

REPO = "/home/user/math_engine_repo"
ENGINE = os.path.join(REPO, "build/engine")
ORACLE = "/app/oracle_engine"


def run_checked(executable, input_path, output_path):
    if os.path.exists(output_path):
        os.remove(output_path)
    result = subprocess.run(
        [executable, input_path, output_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"{executable} failed: {result.stderr}"
    assert os.path.isfile(output_path), f"{executable} did not generate {output_path}"


def read_output(path):
    try:
        df = pd.read_csv(path, header=None, names=["id", "val"])
    except Exception as e:
        pytest.fail(f"Failed to read output CSV {path}: {e}")
    assert list(df.columns) == ["id", "val"]
    assert df["id"].notna().all(), "Output contains a missing ID"
    vals = pd.to_numeric(df["val"], errors="coerce")
    assert np.isfinite(vals.to_numpy(dtype=float)).all(), "Output contains a non-finite value"
    return df["id"].astype(str).tolist(), vals.to_numpy(dtype=float)


def expected_trapezoid(lower, upper, steps):
    if steps <= 0:
        return 0.0
    antiderivative = lambda x: x**3 + x**2
    return (antiderivative(upper) - antiderivative(lower)
            + (upper - lower)**3 / (2.0 * steps * steps))


def assert_behavior(executable, workdir):
    token = secrets.token_hex(8)
    cases = [
        (f"single_{token}", 0.0, 1.0, 1),
        (f"negative_{token}", -3.25, -0.5, 7),
        (f"reversed_{token}", 4.75, -1.25, 19),
        (f"zero_steps_{token}", 2.0, 9.0, 0),
        (f"scientific_{token}", 1.25e-2, 6.75, 113),
    ]
    for i in range(7):
        lower = (secrets.randbelow(40001) - 20000) / 1000.0
        upper = (secrets.randbelow(40001) - 20000) / 1000.0
        if upper == lower:
            upper += 0.125
        steps = 2 + secrets.randbelow(997)
        cases.append((f"random_{i}_{token}", lower, upper, steps))

    input_path = os.path.join(workdir, f"queries_{token}.csv")
    output_path = os.path.join(workdir, f"output_{token}.csv")
    with open(input_path, "w", encoding="utf-8") as f:
        for qid, lower, upper, steps in cases:
            f.write(f"{qid},{lower:.17g},{upper:.17g},{steps}\n")

    run_checked(executable, input_path, output_path)
    ids, values = read_output(output_path)
    expected_ids = [case[0] for case in cases]
    expected_values = np.array(
        [expected_trapezoid(case[1], case[2], case[3]) for case in cases],
        dtype=float,
    )
    assert ids == expected_ids, f"Output IDs/order mismatch: {ids} != {expected_ids}"
    assert len(values) == len(expected_values), "Output row count mismatch"
    assert np.allclose(values, expected_values, rtol=0.0, atol=2e-5), (
        f"Incorrect results: got {values}, expected {expected_values}"
    )


def test_engine_executable_exists():
    engine_path = ENGINE
    assert os.path.exists(engine_path), f"Compiled engine not found at {engine_path}"
    assert os.path.isfile(engine_path), f"{engine_path} is not a file"
    assert os.access(engine_path, os.X_OK), f"{engine_path} is not executable"
    with open(engine_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{engine_path} is not an ELF executable"
    with open(engine_path, "rb") as f:
        engine_hash = hashlib.sha256(f.read()).digest()
    with open(ORACLE, "rb") as f:
        oracle_hash = hashlib.sha256(f.read()).digest()
    assert engine_hash != oracle_hash, "Submitted engine is byte-identical to the oracle"


def test_final_output_mse():
    output_path = os.path.join(REPO, "final_output.csv")
    input_path = os.path.join(REPO, "test_queries.csv")
    oracle_output_path = "/tmp/oracle_output.csv"

    assert os.path.exists(output_path), f"Final output not found at {output_path}"
    assert os.path.exists(input_path), f"Input file not found at {input_path}"
    assert os.path.exists(ORACLE), f"Oracle engine not found at {ORACLE}"

    result = subprocess.run([ORACLE, input_path, oracle_output_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Oracle engine failed to run: {result.stderr}"
    assert os.path.exists(oracle_output_path), f"Oracle output not generated at {oracle_output_path}"

    try:
        df_agent = pd.read_csv(output_path, header=None, names=['id', 'val'])
    except Exception as e:
        pytest.fail(f"Failed to read agent output CSV {output_path}: {e}")
    try:
        df_oracle = pd.read_csv(oracle_output_path, header=None, names=['id', 'val'])
    except Exception as e:
        pytest.fail(f"Failed to read oracle output CSV {oracle_output_path}: {e}")

    assert len(df_agent) == len(df_oracle), f"Output rows count mismatch: agent has {len(df_agent)}, oracle has {len(df_oracle)}"
    assert df_agent['id'].astype(str).tolist() == df_oracle['id'].astype(str).tolist(), "Final output IDs/order do not match"
    mse = np.mean((df_agent['val'] - df_oracle['val'])**2)
    threshold = 1e-5
    assert mse <= threshold, f"MSE {mse} exceeds threshold {threshold}"

    executed_output = "/tmp/submitted_engine_fixed_output.csv"
    run_checked(ENGINE, input_path, executed_output)
    run_ids, run_vals = read_output(executed_output)
    oracle_ids, oracle_vals = read_output(oracle_output_path)
    assert run_ids == oracle_ids, "Executed engine produced incorrect IDs/order"
    assert np.allclose(run_vals, oracle_vals, rtol=0.0, atol=2e-5), "Executed engine disagrees with oracle"


def test_submitted_engine_on_unseen_inputs():
    with tempfile.TemporaryDirectory(prefix="engine_dynamic_") as workdir:
        assert_behavior(ENGINE, workdir)


def test_fixed_source_rebuilds_and_works():
    required = [
        os.path.join(REPO, "src/main.cpp"),
        os.path.join(REPO, "src/parser.cpp"),
        os.path.join(REPO, "src/integrator.cpp"),
    ]
    for path in required:
        assert os.path.isfile(path), f"Required source file missing: {path}"

    with tempfile.TemporaryDirectory(prefix="source_rebuild_") as workdir:
        rebuilt = os.path.join(workdir, "engine")
        result = subprocess.run(
            ["g++", "-std=c++14", "-O2", "-o", rebuilt] + required,
            cwd=REPO,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"Fixed source failed to compile: {result.stderr}"
        assert_behavior(rebuilt, workdir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
