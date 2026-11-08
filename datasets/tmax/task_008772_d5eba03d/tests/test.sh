#!/bin/bash
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/reference_mc.go
package main

import (
    "encoding/csv"
    "encoding/json"
    "math"
    "math/rand"
    "os"
    "strconv"
    "strings"
)

type Result struct {
    NoiseSigma           float64 `json:"noise_sigma"`
    OriginalMaxFlux      float64 `json:"original_max_flux"`
    OriginalMaxWavelength float64 `json:"original_max_wavelength"`
    MCMeanPeak            float64 `json:"mc_mean_peak"`
    MCStdPeak             float64 `json:"mc_std_peak"`
    PValue                float64 `json:"p_value"`
}

func main() {
    if len(os.Args) != 4 {
        panic("usage: reference_mc csv noise_sample mc_sample")
    }
    noiseSample := os.Args[2] == "1"
    mcSample := os.Args[3] == "1"

    f, err := os.Open(os.Args[1])
    if err != nil {
        panic(err)
    }
    defer f.Close()

    records, err := csv.NewReader(f).ReadAll()
    if err != nil {
        panic(err)
    }
    if len(records) < 21 {
        panic("not enough spectrum rows")
    }

    wavelengths := make([]float64, 0, len(records)-1)
    fluxes := make([]float64, 0, len(records)-1)
    for _, row := range records[1:] {
        if len(row) < 2 {
            panic("invalid CSV row")
        }
        w, err := strconv.ParseFloat(strings.TrimSpace(row[0]), 64)
        if err != nil {
            panic(err)
        }
        flux, err := strconv.ParseFloat(strings.TrimSpace(row[1]), 64)
        if err != nil {
            panic(err)
        }
        wavelengths = append(wavelengths, w)
        fluxes = append(fluxes, flux)
    }

    noiseMean := 0.0
    for i := 0; i < 20; i++ {
        noiseMean += fluxes[i]
    }
    noiseMean /= 20.0

    noiseSS := 0.0
    for i := 0; i < 20; i++ {
        d := fluxes[i] - noiseMean
        noiseSS += d * d
    }
    noiseDenom := 20.0
    if noiseSample {
        noiseDenom = 19.0
    }
    noiseSigma := math.Sqrt(noiseSS / noiseDenom)

    originalMaxFlux := fluxes[0]
    originalMaxWavelength := wavelengths[0]
    for i := 1; i < len(fluxes); i++ {
        if fluxes[i] > originalMaxFlux {
            originalMaxFlux = fluxes[i]
            originalMaxWavelength = wavelengths[i]
        }
    }

    rng := rand.New(rand.NewSource(42))
    peaks := make([]float64, 10000)
    peakSum := 0.0
    for simulation := 0; simulation < 10000; simulation++ {
        mockMax := math.Inf(-1)
        for _, flux := range fluxes {
            value := flux + rng.NormFloat64()*noiseSigma
            if value > mockMax {
                mockMax = value
            }
        }
        peaks[simulation] = mockMax
        peakSum += mockMax
    }

    mcMean := peakSum / float64(len(peaks))
    mcSS := 0.0
    for _, peak := range peaks {
        d := peak - mcMean
        mcSS += d * d
    }
    mcDenom := float64(len(peaks))
    if mcSample {
        mcDenom = float64(len(peaks) - 1)
    }
    mcStd := math.Sqrt(mcSS / mcDenom)
    z := (mcMean - 12.0) / mcStd
    p := 0.5 * math.Erfc(z/math.Sqrt2)

    result := Result{
        NoiseSigma: noiseSigma,
        OriginalMaxFlux: originalMaxFlux,
        OriginalMaxWavelength: originalMaxWavelength,
        MCMeanPeak: mcMean,
        MCStdPeak: mcStd,
        PValue: p,
    }
    if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
        panic(err)
    }
}
GO_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess

ANALYZE = "/home/user/analyze.go"
SPECTRUM = "/home/user/spectrum.csv"
RESULTS = "/home/user/results.json"
BINARY = "/tmp/submission-analyze"
ORACLE = "/tmp/reference-mc"

REQUIRED_KEYS = [
    "noise_sigma",
    "original_max_flux",
    "original_max_wavelength",
    "mc_mean_peak",
    "mc_std_peak",
    "p_value",
]

HIDDEN_SPECTRUM = """wavelength,flux
510.5,8.80
511.0,9.12
511.5,8.91
512.0,9.25
512.5,8.76
513.0,9.04
513.5,9.18
514.0,8.87
514.5,9.09
515.0,8.95
515.5,9.21
516.0,8.82
516.5,9.02
517.0,9.14
517.5,8.89
518.0,9.07
518.5,8.93
519.0,9.16
519.5,8.85
520.0,9.11
520.5,9.30
521.0,9.85
521.5,10.70
522.0,11.95
522.5,12.72
523.0,12.31
523.5,11.40
524.0,10.10
524.5,9.45
"""


def run_checked(command):
    return subprocess.run(command, check=True, text=True, capture_output=True)


def load_results():
    assert os.path.exists(RESULTS), f"The file {RESULTS} does not exist."
    assert os.path.isfile(RESULTS), f"The path {RESULTS} is not a file."
    try:
        with open(RESULTS, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        assert False, f"The file {RESULTS} does not contain valid JSON."

    for key in REQUIRED_KEYS:
        assert key in data, f"Missing required key '{key}' in results.json."
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), \
            f"Result '{key}' must be numeric."
        assert math.isfinite(data[key]), f"Result '{key}' must be finite."
    return data


def execute_submission():
    if os.path.lexists(RESULTS):
        if os.path.isdir(RESULTS) and not os.path.islink(RESULTS):
            shutil.rmtree(RESULTS)
        else:
            os.unlink(RESULTS)
    run_checked([BINARY])
    return load_results()


def oracle_variants():
    variants = []
    for noise_sample in ("0", "1"):
        for mc_sample in ("0", "1"):
            output = run_checked([ORACLE, SPECTRUM, noise_sample, mc_sample]).stdout
            variants.append(json.loads(output))
    return variants


def close_value(actual, expected, key):
    if key == "p_value":
        return math.isclose(actual, expected, rel_tol=1e-4, abs_tol=1e-300)
    return math.isclose(actual, expected, rel_tol=1e-7, abs_tol=1e-6)


def assert_matches_seeded_pipeline(actual):
    variants = oracle_variants()
    assert any(
        all(close_value(actual[key], expected[key], key) for key in REQUIRED_KEYS)
        for expected in variants
    ), "results do not match the required 10,000-trial Go Monte Carlo pipeline with seed 42"


def test_complete_analysis_program():
    assert os.path.exists(ANALYZE), f"The file {ANALYZE} does not exist."
    assert os.path.isfile(ANALYZE), f"The path {ANALYZE} is not a file."

    run_checked(["go", "build", "-o", BINARY, ANALYZE])
    run_checked(["go", "build", "-o", ORACLE, "/tmp/reference_mc.go"])

    with open(SPECTRUM, "rb") as f:
        original_spectrum = f.read()

    try:
        data = execute_submission()

        # Preserve the original verifier's scientific assertions.
        assert abs(data["original_max_flux"] - 14.20) < 0.01, \
            f"Expected original_max_flux around 14.20, got {data['original_max_flux']}"
        assert abs(data["original_max_wavelength"] - 426.0) < 0.01, \
            f"Expected original_max_wavelength around 426.0, got {data['original_max_wavelength']}"
        assert 0.07 < data["noise_sigma"] < 0.09, \
            f"Expected noise_sigma between 0.07 and 0.09, got {data['noise_sigma']}"
        assert 14.1 < data["mc_mean_peak"] < 14.3, \
            f"Expected mc_mean_peak between 14.1 and 14.3, got {data['mc_mean_peak']}"
        assert 0.07 < data["mc_std_peak"] < 0.09, \
            f"Expected mc_std_peak between 0.07 and 0.09, got {data['mc_std_peak']}"
        assert data["p_value"] < 1e-5, \
            f"Expected p_value < 1e-5, got {data['p_value']}"

        assert_matches_seeded_pipeline(data)

        # Exercise the compiled artifact on an unseen spectrum so fixed JSON cannot pass.
        with open(SPECTRUM, "w") as f:
            f.write(HIDDEN_SPECTRUM)
        hidden_data = execute_submission()
        assert_matches_seeded_pipeline(hidden_data)
    finally:
        with open(SPECTRUM, "wb") as f:
            f.write(original_spectrum)
        if os.path.isfile(BINARY):
            subprocess.run([BINARY], text=True, capture_output=True)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
