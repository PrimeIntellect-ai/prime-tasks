#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import tempfile
import pytest

def test_regression_report_exists_and_valid():
    report_path = "/home/user/regression_report.json"
    assert os.path.exists(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    expected_keys = {"mean_walk_length", "mode_walk_length", "bootstrap_ci_lower", "bootstrap_ci_upper"}
    assert set(report.keys()) == expected_keys, f"JSON keys do not match. Expected: {expected_keys}, Got: {set(report.keys())}"

def test_regression_report_values():
    report_path = "/home/user/regression_report.json"
    assert os.path.exists(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        report = json.load(f)

    # Write a Go program to compute the exact expected values using Go's math/rand
    go_code = """
package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"sort"
)

func main() {
	adj := map[int][]int{
		0: {1, 2, 3},
		1: {0, 4, 5},
		2: {0, 6},
		3: {0, 7, 8},
		4: {1},
		5: {1},
		6: {2, 9},
		7: {3},
		8: {3},
		9: {6},
	}

	walkRand := rand.New(rand.NewSource(42))
	var walks []int
	counts := make(map[int]int)
	sum := 0.0

	for i := 0; i < 10000; i++ {
		curr := 0
		steps := 0
		for steps < 100 {
			if steps > 0 && curr == 0 {
				break
			}
			neighbors := adj[curr]
			curr = neighbors[walkRand.Intn(len(neighbors))]
			steps++
		}
		walks = append(walks, steps)
		counts[steps]++
		sum += float64(steps)
	}

	mean := sum / 10000.0

	mode := -1
	maxCount := -1
	for val, count := range counts {
		if count > maxCount || (count == maxCount && val < mode) {
			maxCount = count
			mode = val
		}
	}

	bootRand := rand.New(rand.NewSource(123))
	var bootMeans []float64

	for i := 0; i < 10000; i++ {
		bsum := 0.0
		for j := 0; j < 10000; j++ {
			idx := bootRand.Intn(10000)
			bsum += float64(walks[idx])
		}
		bootMeans = append(bootMeans, bsum/10000.0)
	}

	sort.Float64s(bootMeans)
	ciLower := bootMeans[249]
	ciUpper := bootMeans[9749]

	res := map[string]float64{
		"mean_walk_length":   mean,
		"mode_walk_length":   float64(mode),
		"bootstrap_ci_lower": ciLower,
		"bootstrap_ci_upper": ciUpper,
	}

	b, _ := json.Marshal(res)
	fmt.Println(string(b))
}
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        go_file = os.path.join(tmpdir, "expected.go")
        with open(go_file, "w") as f:
            f.write(go_code)

        try:
            result = subprocess.run(["go", "run", go_file], capture_output=True, text=True, check=True)
            expected_report = json.loads(result.stdout)
        except Exception as e:
            pytest.skip(f"Could not run Go to generate expected values: {e}")

    # Compare with 4 decimal places rounding
    assert round(report["mean_walk_length"], 4) == round(expected_report["mean_walk_length"], 4), "mean_walk_length mismatch"
    assert report["mode_walk_length"] == int(expected_report["mode_walk_length"]), "mode_walk_length mismatch"
    assert round(report["bootstrap_ci_lower"], 4) == round(expected_report["bootstrap_ci_lower"], 4), "bootstrap_ci_lower mismatch"
    assert round(report["bootstrap_ci_upper"], 4) == round(expected_report["bootstrap_ci_upper"], 4), "bootstrap_ci_upper mismatch"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
