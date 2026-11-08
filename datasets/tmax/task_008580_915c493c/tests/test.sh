#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import textwrap
import pytest


def test_ml_data_stats():
    go_path = "/home/user/prepare_data.go"
    json_path = "/home/user/ml_data_stats.json"
    fasta_path = "/home/user/raw_sequences.fasta"

    assert os.path.isfile(go_path), f"Expected Go program {go_path} does not exist or is not a regular file."
    assert not os.path.islink(go_path), f"Expected {go_path} to be a Go source file, not a symlink."
    assert os.path.exists(fasta_path), f"Input file {fasta_path} does not exist."

    # Require the submitted Go program itself to generate a fresh output file.
    if os.path.lexists(json_path):
        os.remove(json_path)
    result = subprocess.run(
        ["go", "run", go_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"go run {go_path} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(json_path), f"Expected output file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    required_keys = {"extracted_count", "mean_gc", "ci_lower", "ci_upper"}
    assert required_keys.issubset(data.keys()), (
        f"JSON missing required keys. Expected {required_keys}, found {list(data.keys())}"
    )

    # Independently calculate the required values with Go's math/rand implementation,
    # including the exact seed, number of resamples, and percentile indices.
    oracle_source = r'''
package main

import (
    "bufio"
    "encoding/json"
    "fmt"
    "math/rand"
    "os"
    "sort"
    "strings"
)

type Stats struct {
    ExtractedCount int     `json:"extracted_count"`
    MeanGC         float64 `json:"mean_gc"`
    CILower        float64 `json:"ci_lower"`
    CIUpper        float64 `json:"ci_upper"`
}

func main() {
    f, err := os.Open("/home/user/raw_sequences.fasta")
    if err != nil { panic(err) }
    defer f.Close()

    var gcs []float64
    var seq strings.Builder
    process := func() {
        s := seq.String()
        seq.Reset()
        start := strings.Index(s, "GACCAT")
        if start < 0 { return }
        restStart := start + len("GACCAT")
        relativeEnd := strings.Index(s[restStart:], "TGTCGA")
        if relativeEnd <= 0 { return }
        sub := s[restStart : restStart+relativeEnd]
        gc := 0
        for _, b := range sub {
            if b == 'G' || b == 'C' { gc++ }
        }
        gcs = append(gcs, float64(gc)/float64(len(sub)))
    }

    scanner := bufio.NewScanner(f)
    seenHeader := false
    for scanner.Scan() {
        line := strings.TrimSpace(scanner.Text())
        if strings.HasPrefix(line, ">") {
            if seenHeader { process() }
            seenHeader = true
        } else if seenHeader {
            seq.WriteString(line)
        }
    }
    if err := scanner.Err(); err != nil { panic(err) }
    if seenHeader { process() }
    if len(gcs) == 0 { panic("no extracted subsequences") }

    mean := 0.0
    for _, gc := range gcs { mean += gc }
    mean /= float64(len(gcs))

    const B = 10000
    rng := rand.New(rand.NewSource(42))
    means := make([]float64, B)
    for b := 0; b < B; b++ {
        total := 0.0
        for i := 0; i < len(gcs); i++ {
            total += gcs[rng.Intn(len(gcs))]
        }
        means[b] = total / float64(len(gcs))
    }
    sort.Float64s(means)

    out := Stats{
        ExtractedCount: len(gcs),
        MeanGC: mean,
        CILower: means[int(0.025*B)],
        CIUpper: means[int(0.975*B)],
    }
    encoded, err := json.Marshal(out)
    if err != nil { panic(err) }
    fmt.Println(string(encoded))
}
'''
    oracle_path = "/tmp/bootstrap_oracle.go"
    with open(oracle_path, "w") as f:
        f.write(textwrap.dedent(oracle_source))
    oracle_run = subprocess.run(
        ["go", "run", oracle_path],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert oracle_run.returncode == 0, f"Internal oracle failed: {oracle_run.stderr}"
    expected = json.loads(oracle_run.stdout)

    exact_count = expected["extracted_count"]
    exact_mean = expected["mean_gc"]

    assert data["extracted_count"] == exact_count, (
        f"Expected extracted_count {exact_count}, got {data['extracted_count']}"
    )
    assert math.isclose(data["mean_gc"], exact_mean, rel_tol=1e-3), (
        f"Expected mean_gc ~{exact_mean}, got {data['mean_gc']}"
    )

    ci_lower = data["ci_lower"]
    ci_upper = data["ci_upper"]
    assert isinstance(ci_lower, (int, float)) and math.isfinite(ci_lower)
    assert isinstance(ci_upper, (int, float)) and math.isfinite(ci_upper)

    assert ci_lower < exact_mean, f"ci_lower ({ci_lower}) should be less than mean ({exact_mean})"
    assert ci_upper > exact_mean, f"ci_upper ({ci_upper}) should be greater than mean ({exact_mean})"

    ci_width = ci_upper - ci_lower
    assert ci_width < 0.1, f"Confidence interval too wide: {ci_width}. Expected < 0.1 for this sample size."
    assert ci_width > 0.01, f"Confidence interval too narrow: {ci_width}. Expected > 0.01 for this sample size."

    # Permit serialization rounded to four decimal places, as explicitly allowed.
    tolerance = 5.1e-5
    assert math.isclose(ci_lower, expected["ci_lower"], rel_tol=0.0, abs_tol=tolerance), (
        f"Expected ci_lower {expected['ci_lower']}, got {ci_lower}"
    )
    assert math.isclose(ci_upper, expected["ci_upper"], rel_tol=0.0, abs_tol=tolerance), (
        f"Expected ci_upper {expected['ci_upper']}, got {ci_upper}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
