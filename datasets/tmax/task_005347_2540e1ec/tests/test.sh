#!/bin/bash
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/compute_expected.go
package main

import (
    "encoding/csv"
    "encoding/json"
    "fmt"
    "math"
    "math/rand"
    "os"
    "sort"
    "strconv"
)

type report struct {
    DominantFrequency   float64 `json:"dominant_frequency"`
    WassersteinDistance float64 `json:"wasserstein_distance"`
    BootstrapCILower    float64 `json:"bootstrap_ci_lower"`
    BootstrapCIUpper    float64 `json:"bootstrap_ci_upper"`
}

func round2(v float64) float64 {
    return math.Round(v*100) / 100
}

func main() {
    f, err := os.Open("/home/user/sim_data.csv")
    if err != nil {
        panic(err)
    }
    defer f.Close()

    rows, err := csv.NewReader(f).ReadAll()
    if err != nil {
        panic(err)
    }
    if len(rows) != 1001 {
        panic(fmt.Sprintf("expected header plus 1000 rows, got %d rows", len(rows)))
    }

    times := make([]float64, 1000)
    stable := make([]float64, 1000)
    unstable := make([]float64, 1000)
    for i, row := range rows[1:] {
        if len(row) != 3 {
            panic("CSV row does not have three columns")
        }
        times[i], err = strconv.ParseFloat(row[0], 64)
        if err != nil { panic(err) }
        stable[i], err = strconv.ParseFloat(row[1], 64)
        if err != nil { panic(err) }
        unstable[i], err = strconv.ParseFloat(row[2], 64)
        if err != nil { panic(err) }
    }

    sampleRate := 1.0 / (times[1] - times[0])
    bestBin := 1
    bestMagnitude := -1.0
    for k := 1; k <= len(unstable)/2; k++ {
        var re, im float64
        for j, value := range unstable {
            angle := -2 * math.Pi * float64(k*j) / float64(len(unstable))
            re += value * math.Cos(angle)
            im += value * math.Sin(angle)
        }
        magnitude := math.Hypot(re, im)
        if magnitude > bestMagnitude {
            bestMagnitude = magnitude
            bestBin = k
        }
    }
    dominant := float64(bestBin) * sampleRate / float64(len(unstable))

    sortedStable := append([]float64(nil), stable...)
    sortedUnstable := append([]float64(nil), unstable...)
    sort.Float64s(sortedStable)
    sort.Float64s(sortedUnstable)
    var wasserstein float64
    for i := range sortedStable {
        wasserstein += math.Abs(sortedStable[i] - sortedUnstable[i])
    }
    wasserstein /= float64(len(sortedStable))

    rng := rand.New(rand.NewSource(42))
    means := make([]float64, 1000)
    for iteration := 0; iteration < 1000; iteration++ {
        var sum float64
        for j := 0; j < 1000; j++ {
            sum += unstable[rng.Intn(1000)]
        }
        means[iteration] = sum / 1000
    }
    sort.Float64s(means)

    result := report{
        DominantFrequency: round2(dominant),
        WassersteinDistance: round2(wasserstein),
        BootstrapCILower: round2(means[25]),
        BootstrapCIUpper: round2(means[975]),
    }
    if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
        panic(err)
    }
}
GO_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess

ANALYZE = "/home/user/analyze.go"
CSV_PATH = "/home/user/sim_data.csv"
REPORT_PATH = "/home/user/report.json"
EXPECTED_KEYS = {
    "dominant_frequency",
    "wasserstein_distance",
    "bootstrap_ci_lower",
    "bootstrap_ci_upper",
}


def expected_report():
    proc = subprocess.run(
        ["go", "run", "/tmp/compute_expected.go"],
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert proc.returncode == 0, f"Independent calculation failed: {proc.stderr}"
    return json.loads(proc.stdout)


def run_submission():
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)
    proc = subprocess.run(
        ["go", "run", ANALYZE],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert proc.returncode == 0, (
        f"go run {ANALYZE} failed with exit code {proc.returncode}:\n{proc.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Expected output file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError as exc:
            assert False, f"File {REPORT_PATH} is not valid JSON: {exc}"
    assert set(result.keys()) == EXPECTED_KEYS, (
        f"JSON keys do not match expected. Got {list(result.keys())}"
    )
    for key in EXPECTED_KEYS:
        assert isinstance(result[key], (int, float)) and not isinstance(result[key], bool), (
            f"{key} must be a JSON number"
        )
        assert math.isfinite(result[key]), f"{key} must be finite"
    return result


def assert_exact_metrics(actual, expected):
    for key in EXPECTED_KEYS:
        assert math.isclose(actual[key], expected[key], rel_tol=0.0, abs_tol=1e-9), (
            f"Expected {key} to be {expected[key]:.2f}, got {actual[key]}"
        )


def test_program_and_report():
    assert os.path.isfile(ANALYZE), f"Expected Go source file {ANALYZE} does not exist."
    assert os.path.getsize(ANALYZE) > 0, f"Go source file {ANALYZE} is empty."

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    saved_report = None

    try:
        original_expected = expected_report()
        original_actual = run_submission()

        # Preserve the original verifier's valid assertions.
        assert math.isclose(original_actual["dominant_frequency"], 8.00, abs_tol=0.01), (
            f"Expected dominant_frequency to be 8.00, got {original_actual['dominant_frequency']}"
        )

        stable_err = []
        unstable_err = []
        with open(CSV_PATH, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                stable_err.append(float(row["stable_err"]))
                unstable_err.append(float(row["unstable_err"]))
        stable_err.sort()
        unstable_err.sort()
        wasserstein = sum(abs(s - u) for s, u in zip(stable_err, unstable_err)) / len(stable_err)
        assert math.isclose(
            original_actual["wasserstein_distance"], wasserstein, abs_tol=0.05
        ), (
            f"Expected wasserstein_distance around {wasserstein:.2f}, "
            f"got {original_actual['wasserstein_distance']}"
        )
        assert math.isclose(original_actual["bootstrap_ci_lower"], 0.01, abs_tol=0.05), (
            f"Expected bootstrap_ci_lower around 0.01, got {original_actual['bootstrap_ci_lower']}"
        )

        # Enforce the instructed rounding and the exact seeded Go bootstrap result.
        assert_exact_metrics(original_actual, original_expected)
        with open(REPORT_PATH, "rb") as f:
            saved_report = f.read()

        # Exercise the CSV-processing program on a second 1000-sample signal so a
        # prewritten or hardcoded report cannot pass.
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["time", "stable_err", "unstable_err"])
            for i in range(1000):
                t = i / 100.0
                stable = 0.15 * math.cos(2 * math.pi * 3 * t) + 0.01 * math.sin(2 * math.pi * 17 * t)
                unstable = -0.2 + 1.5 * math.sin(2 * math.pi * 13 * t) + 0.3 * math.sin(2 * math.pi * 5 * t)
                writer.writerow([t, stable, unstable])

        alternate_expected = expected_report()
        alternate_actual = run_submission()
        assert_exact_metrics(alternate_actual, alternate_expected)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if saved_report is not None:
            with open(REPORT_PATH, "wb") as f:
                f.write(saved_report)

PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
