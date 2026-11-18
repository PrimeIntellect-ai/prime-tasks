#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pandas.testing as pdt

HOME = "/home/user"
DATA = f"{HOME}/data"
INPUTS = ["sensor_a.csv", "sensor_b.csv", "sensor_c.csv", "target.csv"]
JOINED = f"{DATA}/joined.csv"
RESULTS = f"{HOME}/results.json"
PY_SCRIPT = f"{HOME}/join_data.py"
R_SCRIPT = f"{HOME}/analyze.R"


def run(cmd):
    return subprocess.run(
        cmd, cwd=HOME, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180
    )


def expected_join():
    a = pd.read_csv(f"{DATA}/sensor_a.csv")
    b = pd.read_csv(f"{DATA}/sensor_b.csv")
    c = pd.read_csv(f"{DATA}/sensor_c.csv")
    target = pd.read_csv(f"{DATA}/target.csv")
    return a.merge(b, on="timestamp", how="inner").merge(
        c, on="timestamp", how="inner"
    ).merge(target, on="timestamp", how="inner")


def normalized(df):
    return df.sort_values("timestamp").reset_index(drop=True)


def assert_joined_matches(expected):
    assert os.path.isfile(JOINED), (
        f"File {JOINED} is missing. The Python script should create it."
    )
    actual = pd.read_csv(JOINED)
    assert list(actual.columns) == ["timestamp", "value_a", "value_b", "value_c", "target"]
    pdt.assert_frame_equal(
        normalized(actual), normalized(expected),
        check_dtype=True, check_exact=False, rtol=1e-12, atol=1e-12
    )


def expected_statistics(path):
    code = r'''
args <- commandArgs(trailingOnly=TRUE)
d <- read.csv(args[1], check.names=FALSE)
mu <- (d$value_a / 2.0 + d$value_b / 4.0 + d$value_c / 1.0) /
      (1.0 / 100.0 + 1.0 / 2.0 + 1.0 / 4.0 + 1.0 / 1.0)
r <- cor(mu, d$target, method="pearson")
set.seed(42)
boot <- replicate(10000, {
  idx <- sample.int(nrow(d), nrow(d), replace=TRUE)
  cor(mu[idx], d$target[idx], method="pearson")
})
ci <- quantile(boot, probs=c(0.025, 0.975), names=FALSE)
cat(paste(sprintf("%.4f", round(c(r, ci), 4)), collapse="\t"))
'''
    output = run(["Rscript", "-e", code, path]).stdout.strip().split("\t")
    assert len(output) == 3
    return tuple(float(x) for x in output)


def load_and_validate_results(expected_rows, expected_values):
    assert os.path.isfile(RESULTS), f"File {RESULTS} is missing. The R script should create it."
    try:
        with open(RESULTS, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError("results.json is not a valid JSON file.") from exc

    expected_keys = {"joined_rows", "correlation", "ci_lower", "ci_upper"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"results.json is missing keys: {missing_keys}"
    assert set(data.keys()) == expected_keys, "results.json must contain exactly the required keys"

    assert isinstance(data["joined_rows"], int), "joined_rows must be an integer"
    assert isinstance(data["correlation"], (int, float)), "correlation must be a float"
    assert isinstance(data["ci_lower"], (int, float)), "ci_lower must be a float"
    assert isinstance(data["ci_upper"], (int, float)), "ci_upper must be a float"
    assert data["joined_rows"] == expected_rows

    for key, expected in zip(
        ("correlation", "ci_lower", "ci_upper"), expected_values
    ):
        actual = data[key]
        assert not isinstance(actual, bool) and math.isfinite(actual)
        assert abs(actual - expected) < 5e-8, f"{key}: expected {expected:.4f}, got {actual}"
    return data


def run_pipeline_and_check():
    expected = expected_join()
    if os.path.exists(JOINED):
        os.remove(JOINED)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    run(["python3", PY_SCRIPT])
    assert_joined_matches(expected)
    expected_values = expected_statistics(JOINED)
    run(["Rscript", R_SCRIPT])
    assert_joined_matches(expected)
    return load_and_validate_results(len(expected), expected_values)


def write_randomized_inputs():
    rng = np.random.default_rng(secrets.randbits(64))
    n = 73
    timestamps = pd.date_range("2041-03-01", periods=n, freq="h").astype(str).to_numpy()
    signal = rng.normal(0, 3, n) + np.linspace(-2, 2, n)
    target = 0.7 * signal + rng.normal(0, 0.8, n)
    values = {
        "sensor_a.csv": ("value_a", signal + rng.normal(0, np.sqrt(2.0), n), 61),
        "sensor_b.csv": ("value_b", signal + rng.normal(0, 2.0, n), 65),
        "sensor_c.csv": ("value_c", signal + rng.normal(0, 1.0, n), 69),
    }
    for filename, (column, measurements, count) in values.items():
        idx = rng.choice(n, count, replace=False)
        rng.shuffle(idx)
        pd.DataFrame({"timestamp": timestamps[idx], column: measurements[idx]}).to_csv(
            f"{DATA}/{filename}", index=False
        )
    idx = np.arange(n)
    rng.shuffle(idx)
    pd.DataFrame({"timestamp": timestamps[idx], "target": target[idx]}).to_csv(
        f"{DATA}/target.csv", index=False
    )


def test_complete_pipeline():
    assert os.path.isfile(PY_SCRIPT), "join_data.py is missing"
    assert os.path.isfile(R_SCRIPT), "analyze.R is missing"
    assert os.path.getsize(PY_SCRIPT) > 0, "join_data.py is empty"
    assert os.path.getsize(R_SCRIPT) > 0, "analyze.R is empty"

    # Execute and independently validate the requested pipeline on the supplied data.
    original = run_pipeline_and_check()

    # Preserve the original verifier's value assertions.
    assert original["joined_rows"] == 341, (
        f"Expected 341 joined_rows, got {original['joined_rows']}"
    )
    correlation = original["correlation"]
    assert 0.9500 <= correlation <= 0.9650, (
        f"Correlation {correlation} is outside the expected range [0.9500, 0.9650]"
    )
    ci_lower = original["ci_lower"]
    ci_upper = original["ci_upper"]
    assert ci_lower < correlation < ci_upper, (
        "Correlation should be between ci_lower and ci_upper"
    )
    assert 0.93 <= ci_lower <= 0.96, f"ci_lower {ci_lower} is outside expected range"
    assert 0.96 <= ci_upper <= 0.98, f"ci_upper {ci_upper} is outside expected range"

    # Exercise both scripts on fresh data so hardcoded artifacts cannot pass.
    backup = tempfile.mkdtemp(prefix="pipeline-input-backup-")
    try:
        for name in INPUTS:
            shutil.copy2(f"{DATA}/{name}", f"{backup}/{name}")
        write_randomized_inputs()
        run_pipeline_and_check()
    finally:
        for name in INPUTS:
            shutil.copy2(f"{backup}/{name}", f"{DATA}/{name}")
        shutil.rmtree(backup, ignore_errors=True)
        # Leave the requested outputs corresponding to the supplied data.
        run_pipeline_and_check()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
