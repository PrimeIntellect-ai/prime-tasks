#!/bin/bash
set -e
mkdir -p /logs/verifier

WORK_DIR="/home/user/oncall/vwap"
VERIFY_TEST=$(mktemp --suffix=_test.go "$WORK_DIR/verifier_XXXXXX")
trap 'rm -f "$VERIFY_TEST"' EXIT
export VWAP_VERIFY_SEED=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')

cat << 'GO_TEST_EOF' > "$VERIFY_TEST"
package vwap

import (
    "math"
    "math/rand"
    "os"
    "strconv"
    "testing"
)

func verifierExpectedVWAP(prices, volumes []float32) float32 {
    var numerator float64
    var denominator float64
    for i := range prices {
        numerator += float64(prices[i]) * float64(volumes[i])
        denominator += float64(volumes[i])
    }
    if denominator == 0 {
        return 0
    }
    return float32(numerator / denominator)
}

func verifierCheckVWAP(t *testing.T, prices, volumes []float32) {
    t.Helper()
    got := ComputeVWAP(prices, volumes)
    want := verifierExpectedVWAP(prices, volumes)
    if math.IsNaN(float64(got)) || math.IsInf(float64(got), 0) {
        t.Fatalf("ComputeVWAP returned non-finite value %v", got)
    }

    ulp := float64(math.Nextafter32(want, float32(math.Inf(1))) - want)
    tolerance := 2 * math.Abs(ulp)
    if tolerance < 0.00001 {
        tolerance = 0.00001
    }
    if math.Abs(float64(got)-float64(want)) > tolerance {
        t.Fatalf("incorrect VWAP for prices=%v volumes=%v: expected %v, got %v", prices, volumes, want, got)
    }
}

func TestVerifierComputeVWAPGeneralInputs(t *testing.T) {
    // Multiple distinct cases deliberately share lengths, preventing a
    // length-based implementation from satisfying the test.
    fixed := []struct {
        prices  []float32
        volumes []float32
    }{
        {[]float32{10, 20, 30}, []float32{1, 2, 7}},
        {[]float32{9000, 2, 17}, []float32{0.25, 80000, 3}},
        {[]float32{1.5, 8.25, 10000000}, []float32{1000000, 3, 0.125}},
        {[]float32{42}, []float32{19}},
        {[]float32{3, 100, 7, 80, 11}, []float32{9, 1, 30, 2, 17}},
    }
    for _, tc := range fixed {
        verifierCheckVWAP(t, tc.prices, tc.volumes)
    }

    seed, err := strconv.ParseInt(os.Getenv("VWAP_VERIFY_SEED"), 10, 64)
    if err != nil {
        t.Fatalf("invalid verifier seed: %v", err)
    }
    rng := rand.New(rand.NewSource(seed))
    for caseNum := 0; caseNum < 64; caseNum++ {
        n := 2 + rng.Intn(126)
        prices := make([]float32, n)
        volumes := make([]float32, n)
        for i := 0; i < n; i++ {
            switch i % 4 {
            case 0:
                prices[i] = float32(1 + rng.Float64()*10000000)
            case 1:
                prices[i] = float32(0.01 + rng.Float64()*25)
            default:
                prices[i] = float32(25 + rng.Float64()*5000)
            }
            if i%5 == 0 {
                volumes[i] = float32(0.01 + rng.Float64())
            } else {
                volumes[i] = float32(1 + rng.Float64()*1000000)
            }
        }
        verifierCheckVWAP(t, prices, volumes)
    }

    // A long, skewed accumulation exposes float32 accumulator precision loss.
    prices := make([]float32, 20000)
    volumes := make([]float32, 20000)
    for i := range prices {
        prices[i] = float32(80 + rng.Float64()*40)
        volumes[i] = float32(50000 + rng.Float64()*100000)
    }
    prices[0] = 10000000
    volumes[0] = 1
    verifierCheckVWAP(t, prices, volumes)
}
GO_TEST_EOF

cat << 'PY_TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import re

WORK_DIR = "/home/user/oncall/vwap"

def test_go_tests_pass():
    """Ensure all shipped and verifier-supplied tests pass consistently."""
    assert os.path.isdir(WORK_DIR), f"Directory {WORK_DIR} does not exist."
    result = subprocess.run(
        ["go", "test", "-count=50"],
        cwd=WORK_DIR,
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    assert result.returncode == 0, f"go test failed. Output:\n{result.stdout}\n{result.stderr}"

def test_function_signature_unchanged():
    """Ensure the exported function signature remains exactly the same."""
    vwap_file = "/home/user/oncall/vwap/vwap.go"
    assert os.path.isfile(vwap_file), f"{vwap_file} is missing."
    with open(vwap_file, "r") as f:
        content = f.read()
    expected_signature = r"func ComputeVWAP\(\s*prices\s+\[\]float32\s*,\s*volumes\s+\[\]float32\s*\)\s+float32"
    assert re.search(expected_signature, content), "The signature of ComputeVWAP was changed or not found."

def test_result_file_correct():
    """Validate that result.txt contains exactly the requested formatted VWAP."""
    result_file = "/home/user/result.txt"
    assert os.path.isfile(result_file), f"{result_file} is missing."
    prices = [10000000.0, 100.0, 105.0]
    volumes = [1.0, 500000.0, 600000.0]
    numerator = sum(p * v for p, v in zip(prices, volumes))
    denominator = sum(volumes)
    expected_str = f"{numerator / denominator:.4f}"
    with open(result_file, "r") as f:
        content = f.read()
    assert content == expected_str, f"Expected exact content '{expected_str}' in {result_file}, but found {content!r}"
PY_TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
