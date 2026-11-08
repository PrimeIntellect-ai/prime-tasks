#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'REF_EOF' > /tmp/reference_mh.go
package main

import (
    "encoding/csv"
    "fmt"
    "math"
    "math/rand"
    "os"
    "strconv"
)

func main() {
    f, err := os.Open("/home/user/data.csv")
    if err != nil { panic(err) }
    defer f.Close()
    rows, err := csv.NewReader(f).ReadAll()
    if err != nil { panic(err) }

    xs := make([]float64, 0, len(rows)-1)
    ys := make([]float64, 0, len(rows)-1)
    for _, row := range rows[1:] {
        x, err := strconv.ParseFloat(row[0], 64)
        if err != nil { panic(err) }
        y, err := strconv.ParseFloat(row[1], 64)
        if err != nil { panic(err) }
        xs = append(xs, x)
        ys = append(ys, y)
    }

    var sx, sy float64
    for i := range xs { sx += xs[i]; sy += ys[i] }
    mx, my := sx/float64(len(xs)), sy/float64(len(ys))
    var sxx, sxy float64
    for i := range xs {
        dx := xs[i] - mx
        sxx += dx * dx
        sxy += dx * (ys[i] - my)
    }
    ob := sxy / sxx
    oa := my - ob*mx

    logLike := func(a, b float64) float64 {
        var v float64
        for i := range xs {
            d := ys[i] - a - b*xs[i]
            v -= 0.5*d*d
        }
        return v
    }

    rng := rand.New(rand.NewSource(42))
    a, b := 0.0, 0.0
    ll := logLike(a, b)
    var suma, sumb float64
    for i := 0; i < 100000; i++ {
        na := a + 0.1*rng.NormFloat64()
        nb := b + 0.1*rng.NormFloat64()
        if na >= -100 && na <= 100 && nb >= -100 && nb <= 100 {
            nll := logLike(na, nb)
            if math.Log(rng.Float64()) < nll-ll {
                a, b, ll = na, nb, nll
            }
        }
        if i >= 10000 {
            suma += a
            sumb += b
        }
    }
    fmt.Printf("%.17g %.17g %.17g %.17g\n", oa, ob, suma/90000, sumb/90000)
}
REF_EOF

go build -o /tmp/reference_mh /tmp/reference_mh.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess
import time
import pytest

RESULTS_PATH = "/home/user/results.json"
SOURCE_PATH = "/home/user/mcmc.go"
BINARY_PATH = "/tmp/mcmc_submission"
DATA_PATH = "/home/user/data.csv"

assert os.path.isfile(SOURCE_PATH), f"File {SOURCE_PATH} is missing."
subprocess.run(["go", "build", "-o", BINARY_PATH, SOURCE_PATH], check=True, timeout=60)


def run_submission():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    started = time.monotonic()
    subprocess.run([BINARY_PATH], cwd="/home/user", check=True, timeout=30)
    elapsed = time.monotonic() - started
    assert os.path.isfile(RESULTS_PATH), "Running mcmc.go did not generate results.json"
    with open(RESULTS_PATH, "r") as f:
        data = json.load(f)
    return data, elapsed


# Generate a fresh result from the submitted program; do not trust an artifact
# that was present before verification.
ORIGINAL_RESULTS, ORIGINAL_ELAPSED = run_submission()


def test_source_and_executable_exist_and_build():
    assert os.path.isfile(SOURCE_PATH)
    assert os.path.isfile(BINARY_PATH)
    with open(SOURCE_PATH, "r") as f:
        source = f.read()
    normalized = source.replace("_", "")
    assert re.search(r"rand\s*\.\s*(?:Seed|NewSource)\s*\(\s*42\s*\)", source), "The sampler must seed Go's RNG with 42"
    assert "NormFloat64" in source, "The sampler must use Gaussian random-walk proposals"
    assert "100000" in normalized, "The program must specify 100,000 MCMC iterations"
    assert "10000" in normalized, "The program must specify a 10,000-iteration burn-in"
    assert re.search(r"(?:0\.1|1[eE]-1)", source), "The proposal standard deviation must be 0.1"


def test_results_file_exists():
    assert os.path.isfile(RESULTS_PATH), f"File {RESULTS_PATH} is missing. The Go program must generate this file."


def test_results_json_format():
    data = ORIGINAL_RESULTS
    expected_keys = {
        "ols_alpha",
        "ols_beta",
        "mcmc_alpha",
        "mcmc_beta",
        "accuracy_pass",
        "mcmc_time_seconds"
    }
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"The JSON file is missing required keys: {missing_keys}"


def test_results_values():
    data = ORIGINAL_RESULTS
    ols_alpha = data.get("ols_alpha")
    ols_beta = data.get("ols_beta")
    mcmc_alpha = data.get("mcmc_alpha")
    mcmc_beta = data.get("mcmc_beta")
    accuracy_pass = data.get("accuracy_pass")
    mcmc_time = data.get("mcmc_time_seconds")

    assert isinstance(ols_alpha, (int, float)), "ols_alpha must be a number"
    assert isinstance(ols_beta, (int, float)), "ols_beta must be a number"
    assert isinstance(mcmc_alpha, (int, float)), "mcmc_alpha must be a number"
    assert isinstance(mcmc_beta, (int, float)), "mcmc_beta must be a number"
    assert isinstance(accuracy_pass, bool), "accuracy_pass must be a boolean"
    assert isinstance(mcmc_time, (int, float)), "mcmc_time_seconds must be a number"

    assert all(math.isfinite(float(data[k])) for k in (
        "ols_alpha", "ols_beta", "mcmc_alpha", "mcmc_beta", "mcmc_time_seconds"
    )), "All numeric results must be finite"

    assert abs(ols_alpha - 2.222) <= 0.05, f"ols_alpha is {ols_alpha}, expected ~2.222"
    assert abs(ols_beta - 1.332) <= 0.05, f"ols_beta is {ols_beta}, expected ~1.332"
    assert accuracy_pass is True, "accuracy_pass must be true"
    assert abs(mcmc_alpha - ols_alpha) <= 0.05, f"mcmc_alpha {mcmc_alpha} is not within 0.05 of ols_alpha {ols_alpha}"
    assert abs(mcmc_beta - ols_beta) <= 0.05, f"mcmc_beta {mcmc_beta} is not within 0.05 of ols_beta {ols_beta}"
    assert mcmc_time > 0, f"mcmc_time_seconds must be a positive float, got {mcmc_time}"
    assert mcmc_time <= ORIGINAL_ELAPSED + 0.5, "Reported MCMC-loop time cannot exceed total observed program time"


def write_dataset(rows):
    with open(DATA_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["X", "Y"])
        writer.writerows(rows)


def reference_values():
    out = subprocess.check_output(["/tmp/reference_mh"], text=True, timeout=30)
    return tuple(float(v) for v in out.split())


def check_hidden(rows, expected_accuracy):
    write_dataset(rows)
    expected_oa, expected_ob, expected_ma, expected_mb = reference_values()
    result, elapsed = run_submission()

    required = {"ols_alpha", "ols_beta", "mcmc_alpha", "mcmc_beta", "accuracy_pass", "mcmc_time_seconds"}
    assert not (required - set(result)), "Hidden run omitted required JSON fields"
    for key in required - {"accuracy_pass"}:
        assert isinstance(result[key], (int, float)) and math.isfinite(float(result[key]))

    assert abs(result["ols_alpha"] - expected_oa) <= 1e-7
    assert abs(result["ols_beta"] - expected_ob) <= 1e-7
    # Allow harmless implementation-order differences while checking the
    # seeded MH output against an independently executed implementation.
    assert abs(result["mcmc_alpha"] - expected_ma) <= 0.08
    assert abs(result["mcmc_beta"] - expected_mb) <= 0.08
    actual_accuracy = (
        abs(result["mcmc_alpha"] - result["ols_alpha"]) <= 0.05 and
        abs(result["mcmc_beta"] - result["ols_beta"]) <= 0.05
    )
    assert result["accuracy_pass"] is actual_accuracy
    assert result["accuracy_pass"] is expected_accuracy
    assert result["mcmc_time_seconds"] > 0
    assert result["mcmc_time_seconds"] <= elapsed + 0.5


def test_program_on_derived_unseen_inputs():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    try:
        ordinary = []
        for i in range(120):
            x = -4.0 + 8.0*i/119.0
            noise = 0.18*math.sin(i*1.71) + 0.07*math.cos(i*0.37)
            ordinary.append((x, -3.4 + 2.15*x + noise))
        check_hidden(ordinary, True)

        # Here the exact OLS intercept lies outside the stated uniform prior.
        # A real sampler must remain within the prior and report failed OLS
        # accuracy rather than merely copying the OLS values into MCMC fields.
        bounded = []
        for i in range(160):
            x = -3 комиссия.0 + 6.0*i/159.0
            noise = 0.03*math.sin(i*0.91)
            bounded.append((x, 105.0 + 0.5*x + noise))
        check_hidden(bounded, False)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        run_submission()
TEST_EOF

# Correct a token that is deliberately kept out of shell interpolation above.
sed -i 's/-3 комиссия\.0/-3.0/' /tmp/test_final_state.py

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
