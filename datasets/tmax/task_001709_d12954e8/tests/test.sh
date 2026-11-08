#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import shutil
import subprocess
import tempfile

import netCDF4 as nc
import numpy as np

FIT = "/home/user/fit.go"
DATA = "/home/user/data.nc"
OUTPUT = "/home/user/posterior.json"


def read_and_validate_output(mean_low, mean_high):
    assert os.path.isfile(OUTPUT), f"Expected file {OUTPUT} to exist."
    with open(OUTPUT, "r") as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {OUTPUT} does not contain valid JSON: {exc}")

    assert "mean_theta" in result, "JSON is missing the 'mean_theta' key."
    assert "acceptance_rate" in result, "JSON is missing the 'acceptance_rate' key."

    mean_theta = result["mean_theta"]
    acceptance_rate = result["acceptance_rate"]
    assert isinstance(mean_theta, (int, float)) and not isinstance(mean_theta, bool), "'mean_theta' must be a number."
    assert isinstance(acceptance_rate, (int, float)) and not isinstance(acceptance_rate, bool), "'acceptance_rate' must be a number."
    assert math.isfinite(mean_theta), "'mean_theta' must be finite."
    assert math.isfinite(acceptance_rate), "'acceptance_rate' must be finite."
    assert mean_low <= mean_theta <= mean_high, (
        f"Expected 'mean_theta' to be between {mean_low} and {mean_high}, but got {mean_theta}."
    )
    assert 0.15 <= acceptance_rate <= 0.50, (
        f"Expected 'acceptance_rate' to be between 0.15 and 0.50, but got {acceptance_rate}."
    )
    return result


def run_fit(mean_low, mean_high):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    completed = subprocess.run(
        ["go", "run", FIT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, (
        "fit.go failed to compile or run.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    return read_and_validate_output(mean_low, mean_high)


def test_fit_source_contains_required_pipeline():
    assert os.path.isfile(FIT), f"Expected file {FIT} to exist."
    with open(FIT, "r") as f:
        source = f.read()
    compact = source.replace("_", "")

    assert 'github.com/fhs/go-netcdf/netcdf' in source, "fit.go must use the required go-netcdf package."
    assert "data.nc" in source and "netcdf.OpenFile" in source, "fit.go must open the NetCDF dataset."
    assert re.search(r'\.Var\(\s*["`]t["`]\s*\)', source), "fit.go must read the NetCDF variable 't'."
    assert re.search(r'\.Var\(\s*["`]y["`]\s*\)', source), "fit.go must read the NetCDF variable 'y'."

    iteration_values = [int(x) for x in re.findall(
        r'(?i)(?:iterations|niter|numiterations|numsamples|totaliterations)\s*(?::=|=)\s*(\d+)', compact
    )]
    iteration_values += [int(x) for x in re.findall(r'(?i)for[^\n;{}]*;[^\n;{}]*<\s*(\d{4,})', compact)]
    assert iteration_values and max(iteration_values) >= 10000, "MCMC must run for at least 10,000 iterations."

    burn_values = [int(x) for x in re.findall(
        r'(?i)(?:burnin|burn|burniterations)\s*(?::=|=)\s*(\d+)', compact
    )]
    burn_values += [int(x) for x in re.findall(r'\[\s*(\d+)\s*:', compact)]
    assert burn_values and max(burn_values) >= 2000, "At least 2,000 iterations must be discarded as burn-in."

    assert "rand.Float64" in source, "The Metropolis-Hastings implementation must draw random acceptance values."
    assert "math.Exp" in source or "math.Log" in source, "The Metropolis-Hastings implementation must compare likelihood ratios correctly."


def test_program_runs_and_infers_from_netcdf_data():
    assert os.path.isfile(DATA), f"Expected reference dataset {DATA} to exist."

    with tempfile.TemporaryDirectory() as tmp:
        backup_data = os.path.join(tmp, "data.nc")
        saved_output = os.path.join(tmp, "posterior.json")
        challenge_tmp = os.path.join(tmp, "challenge.nc")
        shutil.copy2(DATA, backup_data)

        try:
            # Preserve the original verifier's assertions on the reference data,
            # while requiring the result to be freshly produced by fit.go.
            reference = run_fit(0.45, 0.55)
            shutil.copy2(OUTPUT, saved_output)

            # Exercise the submitted implementation on data whose answer is
            # derived by this verifier. A fixed, self-reported value cannot pass.
            theta = 0.62
            times = np.linspace(0.0, 10.0, 11)
            observations = 1.0 / (1.0 + theta * times)
            with nc.Dataset(challenge_tmp, "w", format="NETCDF4") as ds:
                ds.createDimension("time", len(times))
                tvar = ds.createVariable("t", "f8", ("time",))
                yvar = ds.createVariable("y", "f8", ("time",))
                tvar[:] = times
                yvar[:] = observations
            os.replace(challenge_tmp, DATA)

            challenge = run_fit(theta - 0.05, theta + 0.05)
            assert challenge["mean_theta"] > reference["mean_theta"] + 0.04, (
                "The reported posterior mean did not respond sufficiently to the changed NetCDF observations."
            )
        finally:
            shutil.copy2(backup_data, DATA)
            if os.path.isfile(saved_output):
                shutil.copy2(saved_output, OUTPUT)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
