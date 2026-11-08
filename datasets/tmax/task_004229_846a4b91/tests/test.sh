#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_results_json_exists():
    assert os.path.isfile("/home/user/results.json"), "The file /home/user/results.json does not exist."

def test_results_json_content():
    with open("/home/user/results.json", "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/results.json is not a valid JSON file.")

    expected_sensors = ["sensor1.fits", "sensor2.fits", "sensor3.fits", "sensor4.fits"]
    for sensor in expected_sensors:
        assert sensor in data, f"Key '{sensor}' is missing from results.json."

        sensor_data = data[sensor]
        assert "calibrated_freq" in sensor_data, f"'calibrated_freq' missing in {sensor}."
        assert "mean_magnitude" in sensor_data, f"'mean_magnitude' missing in {sensor}."

    expected_calibrated_freq = {
        "sensor1.fits": 6.285714285714286,
        "sensor2.fits": 17.714285714285715,
        "sensor3.fits": 32.0,
        "sensor4.fits": 60.57142857142857
    }

    expected_mean_magnitude = {
        "sensor1.fits": 15.65,
        "sensor2.fits": 15.42,
        "sensor3.fits": 15.61,
        "sensor4.fits": 15.53
    }

    for sensor in expected_sensors:
        calib_freq = data[sensor]["calibrated_freq"]
        mean_mag = data[sensor]["mean_magnitude"]

        assert isinstance(calib_freq, (int, float)), f"'calibrated_freq' for {sensor} must be a number."
        assert isinstance(mean_mag, (int, float)), f"'mean_magnitude' for {sensor} must be a number."

        assert abs(calib_freq - expected_calibrated_freq[sensor]) < 0.01, \
            f"Incorrect 'calibrated_freq' for {sensor}. Expected ~{expected_calibrated_freq[sensor]:.4f}, got {calib_freq}."

        assert abs(mean_mag - expected_mean_magnitude[sensor]) / expected_mean_magnitude[sensor] < 0.05, \
            f"Incorrect 'mean_magnitude' for {sensor}. Expected ~{expected_mean_magnitude[sensor]:.2f}, got {mean_mag}."

def test_go_source_exists():
    assert os.path.isfile("/home/user/analyze.go"), "The Go source file /home/user/analyze.go does not exist."

def test_go_module_initialized():
    assert os.path.isfile("/home/user/go.mod"), "Go module not initialized (/home/user/go.mod is missing)."
TEST_EOF

cat << 'GO_EOF' > /tmp/check_analyze_source.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path"
    "strconv"
)

func main() {
    filename := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), filename, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, "cannot parse analyze.go:", err)
        os.Exit(1)
    }

    aliases := map[string]string{}
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil {
            continue
        }
        if p != "github.com/astrogo/fitsio" && p != "github.com/mjibson/go-dsp/fft" {
            continue
        }
        alias := path.Base(p)
        if imp.Name != nil {
            alias = imp.Name.Name
        }
        if alias == "_" || alias == "." {
            fmt.Fprintf(os.Stderr, "%s must be imported and used normally\n", p)
            os.Exit(1)
        }
        aliases[p] = alias
    }

    fitsAlias, haveFits := aliases["github.com/astrogo/fitsio"]
    fftAlias, haveFFT := aliases["github.com/mjibson/go-dsp/fft"]
    haveFitsCall := false
    haveFFTCall := false
    haveGoStmt := false

    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            haveGoStmt = true
        case *ast.CallExpr:
            sel, ok := x.Fun.(*ast.SelectorExpr)
            if !ok {
                return true
            }
            id, ok := sel.X.(*ast.Ident)
            if !ok {
                return true
            }
            if haveFits && id.Name == fitsAlias && sel.Sel.Name == "Open" {
                haveFitsCall = true
            }
            if haveFFT && id.Name == fftAlias && (sel.Sel.Name == "FFTReal" || sel.Sel.Name == "FFT") {
                haveFFTCall = true
            }
        }
        return true
    })

    if !haveFits || !haveFitsCall {
        fmt.Fprintln(os.Stderr, "analyze.go must call github.com/astrogo/fitsio to open FITS data")
        os.Exit(1)
    }
    if !haveFFT || !haveFFTCall {
        fmt.Fprintln(os.Stderr, "analyze.go must call github.com/mjibson/go-dsp/fft to compute the FFT")
        os.Exit(1)
    }
    if !haveGoStmt {
        fmt.Fprintln(os.Stderr, "analyze.go must launch concurrent work with a goroutine")
        os.Exit(1)
    }
}
GO_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_execution.py
import json
import math
import os
from pathlib import Path
import secrets
import subprocess

import numpy as np
from astropy.io import fits

DATA_DIR = Path("/home/user/data")
RESULTS = Path("/home/user/results.json")
SENSORS = [f"sensor{i}.fits" for i in range(1, 5)]

original_fits = {name: (DATA_DIR / name).read_bytes() for name in SENSORS}
original_results = RESULTS.read_bytes() if RESULTS.exists() else None
rng = np.random.default_rng(secrets.randbits(128))

try:
    expected = {}
    chosen = rng.choice(np.arange(7, 501), size=4, replace=False)
    n = 1024
    t = np.arange(n, dtype=np.float64)

    for i, (name, frequency) in enumerate(zip(SENSORS, chosen)):
        amplitude = rng.uniform(1.2, 3.0)
        secondary = int((int(frequency) + 73 + 19 * i) % 500) + 1
        if secondary == frequency:
            secondary = (secondary % 500) + 1
        phase = rng.uniform(0.0, 2.0 * np.pi)
        flux = (
            rng.uniform(-2.0, 2.0)
            + amplitude * np.sin(2.0 * np.pi * int(frequency) * t / n + phase)
            + 0.12 * np.cos(2.0 * np.pi * secondary * t / n)
            + rng.normal(0.0, 0.01, n)
        )

        column = fits.Column(name="FLUX", format="D", array=flux)
        table = fits.BinTableHDU.from_columns([column])
        fits.HDUList([fits.PrimaryHDU(), table]).writeto(DATA_DIR / name, overwrite=True)

        magnitudes = np.abs(np.fft.fft(flux))
        k = int(np.argmax(magnitudes[1:513])) + 1
        expected[name] = {
            "calibrated_freq": (k + 12.0) / 3.5,
            "mean_magnitude": float(np.sum(magnitudes[1:]) / 1023.0),
        }

    if RESULTS.exists():
        RESULTS.unlink()

    completed = subprocess.run(
        ["go", "run", "/home/user/analyze.go"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, (
        "go run /home/user/analyze.go failed:\n" + completed.stdout + completed.stderr
    )
    assert RESULTS.is_file(), "Running analyze.go did not create /home/user/results.json"

    with RESULTS.open() as f:
        actual = json.load(f)

    assert isinstance(actual, dict), "results.json must contain a JSON object"
    assert set(actual) == set(SENSORS), "results.json must contain exactly the four sensor filenames"

    for name in SENSORS:
        row = actual[name]
        assert isinstance(row, dict), f"Result for {name} must be an object"
        assert set(row) == {"calibrated_freq", "mean_magnitude"}, f"Incorrect keys for {name}"
        calibrated = row["calibrated_freq"]
        mean = row["mean_magnitude"]
        assert isinstance(calibrated, (int, float)) and not isinstance(calibrated, bool)
        assert isinstance(mean, (int, float)) and not isinstance(mean, bool)
        assert math.isfinite(calibrated) and math.isfinite(mean)
        assert abs(calibrated - expected[name]["calibrated_freq"]) < 1e-9, (
            f"Incorrect calibrated_freq for generated {name}"
        )
        assert math.isclose(mean, expected[name]["mean_magnitude"], rel_tol=1e-8, abs_tol=1e-8), (
            f"Incorrect mean_magnitude for generated {name}: expected "
            f"{expected[name]['mean_magnitude']}, got {mean}"
        )
finally:
    for name, content in original_fits.items():
        (DATA_DIR / name).write_bytes(content)
    if original_results is None:
        if RESULTS.exists():
            RESULTS.unlink()
    else:
        RESULTS.write_bytes(original_results)
DYNAMIC_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 \
   && go run /tmp/check_analyze_source.go -- /home/user/analyze.go 2>&1 \
   && python3 /tmp/test_dynamic_execution.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
